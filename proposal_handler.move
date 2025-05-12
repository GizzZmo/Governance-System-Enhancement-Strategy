// File: sources/proposal_handler.move
// Handles the execution logic for different types of governance proposals
// after they have been approved by the main governance module.
module hybrid_governance_pkg::proposal_handler {
    use std::option::{Self, Option, is_some, borrow as option_borrow};
    use std::string::{Self, String, utf8};
    use std::vector;
    use std::bcs; // For deserializing parameter values

    use sui::object::{Self, ID, UID, new};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::event;

    // Import necessary types from other modules within the same package
    use hybrid_governance_pkg::governance::{Self, Proposal}; // To read proposal details
    use hybrid_governance_pkg::treasury::{Self, TreasuryChest, TreasuryAccessCap, TreasuryAdminCap};
    use hybrid_governance_pkg::delegation_staking::{Self, GovernanceSystemState, AdminCap as StakingAdminCap};

    // === Structs ===

    /// Capability held by the `governance` module, required to call `handle_proposal_execution`.
    /// This ensures that proposal execution can only be triggered after successful voting checks.
    struct ProposalExecutionCap has key, store {
        id: UID,
    }

    // === Events ===
    struct FundingProposalExecuted has copy, drop { proposal_id: ID, recipient: address, amount: u64 }
    struct ParameterChangeExecuted has copy, drop { proposal_id: ID, target_module: String, parameter_name: String, new_value_bcs: vector<u8> }
    struct GeneralActionExecuted has copy, drop { proposal_id: ID, action_description: String } // Changed to String
    struct EmergencyActionExecuted has copy, drop { proposal_id: ID, action_description: String } // Changed to String

    // === Errors ===
    // const E_INVALID_EXECUTION_CAPABILITY: u64 = 301; // Implicitly checked by type system
    const E_UNSUPPORTED_PROPOSAL_TYPE: u64 = 302;
    const E_MISSING_FUNDING_PARAMETERS: u64 = 303;
    const E_MISSING_PARAMETER_CHANGE_DATA: u64 = 304;
    const E_TREASURY_INTERACTION_FAILED: u64 = 305; // Generic error, specific errors in treasury module
    const E_STAKING_INTERACTION_FAILED: u64 = 306;  // Generic error, specific errors in staking module
    const E_INVALID_TARGET_MODULE_OR_PARAM_NAME: u64 = 307;
    const E_PARAMETER_DESERIALIZATION_FAILED: u64 = 309;
    const E_ACTION_FAILED_PLACEHOLDER: u64 = 310; // For actions not yet fully implemented

    // === Init ===
    /// Initializes the module, creating the ProposalExecutionCap.
    /// This capability should be transferred to the `governance` module or its admin.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(ProposalExecutionCap { id: new(ctx) }, sender(ctx));
    }

    // === Public Entry Function (Called by Governance Module) ===

    /// The main entry point called by `governance::execute_proposal`.
    public entry fun handle_proposal_execution(
        _exec_cap: &ProposalExecutionCap, // Authorization from governance module
        proposal: &Proposal,              // Immutable reference to the approved Proposal object
        // --- Mutable objects for state changes & Capabilities for restricted actions ---
        treasury_chest: &mut TreasuryChest,
        staking_system_state: &mut GovernanceSystemState,
        treasury_access_cap: &TreasuryAccessCap, // For funding withdrawals
        treasury_admin_cap: &TreasuryAdminCap,   // For treasury config changes
        staking_admin_cap: &StakingAdminCap,     // For staking config changes
        ctx: &mut TxContext
    ) {
        let proposal_type = proposal.proposal_type;

        if (proposal_type == 0) { // General Proposal
            execute_general_action(proposal, ctx);
        } else if (proposal_type == 1 || proposal_type == 2) { // Minor or Critical Parameter Change
            execute_parameter_change(
                proposal,
                staking_system_state,
                treasury_chest,
                staking_admin_cap,
                treasury_admin_cap,
                ctx
            );
        } else if (proposal_type == 3) { // Funding Request
            execute_funding_request(
                proposal,
                treasury_chest,
                treasury_access_cap, // Only needs access cap for funding
                ctx
            );
        } else if (proposal_type == 4) { // Emergency Action
            execute_emergency_action(proposal, staking_system_state, treasury_chest, staking_admin_cap, treasury_admin_cap, ctx);
        } else {
            abort(E_UNSUPPORTED_PROPOSAL_TYPE)
        };
    }

    // === Internal Execution Functions ===

    /// Executes a funding request by calling the treasury module.
    fun execute_funding_request(
        proposal: &Proposal,
        treasury_chest: &mut TreasuryChest,
        treasury_access_cap: &TreasuryAccessCap,
        ctx: &mut TxContext
    ) {
        assert!(is_some(&proposal.funding_amount) && is_some(&proposal.funding_recipient), E_MISSING_FUNDING_PARAMETERS);
        let amount = *option_borrow(&proposal.funding_amount);
        let recipient = *option_borrow(&proposal.funding_recipient);

        // Call the treasury module function that requires the TreasuryAccessCap
        treasury::process_approved_funding_by_governance(
            treasury_chest,
            treasury_access_cap,
            proposal.id, // Pass proposal ID for event logging
            amount,
            recipient,
            ctx
        ); // Errors from treasury will abort

        // Event already emitted by treasury::process_approved_funding_by_governance
        // No need to emit FundingProposalExecuted here if treasury does it well.
        // However, if specific handler event is desired:
        // event::emit(FundingProposalExecuted { proposal_id: proposal.id, recipient, amount });
    }

    /// Executes a parameter change by calling admin functions in target modules.
    fun execute_parameter_change(
        proposal: &Proposal,
        staking_system_state: &mut GovernanceSystemState,
        treasury_chest: &mut TreasuryChest,
        staking_admin_cap: &StakingAdminCap,
        treasury_admin_cap: &TreasuryAdminCap,
        ctx: &mut TxContext
    ) {
        assert!(is_some(&proposal.param_target_module) &&
                is_some(&proposal.param_name) &&
                is_some(&proposal.param_new_value_bcs), E_MISSING_PARAMETER_CHANGE_DATA);

        let target_module_str = option_borrow(&proposal.param_target_module);
        let param_name_str = option_borrow(&proposal.param_name);
        let new_value_bcs_ref = option_borrow(&proposal.param_new_value_bcs);

        if (*target_module_str == string::utf8(b"staking")) {
            if (*param_name_str == string::utf8(b"min_validator_stake_threshold")) {
                let new_value: u64 = bcs::from_bytes(new_value_bcs_ref); // Add error handling for from_bytes if possible
                delegation_staking::admin_update_min_validator_stake(
                    staking_admin_cap, staking_system_state, new_value, ctx
                );
            } else {
                abort(E_INVALID_TARGET_MODULE_OR_PARAM_NAME);
            }
        } else if (*target_module_str == string::utf8(b"treasury")) {
            if (*param_name_str == string::utf8(b"min_approvals_required")) {
                let new_value: u64 = bcs::from_bytes(new_value_bcs_ref);
                // Get current max_approvers to pass to the config update function
                let current_max_approvers = treasury::get_max_approvers(treasury_chest);
                treasury::admin_update_treasury_config(
                    treasury_admin_cap, treasury_chest, new_value, current_max_approvers, ctx
                );
            } else if (*param_name_str == string::utf8(b"max_approvers")) {
                let new_value: u64 = bcs::from_bytes(new_value_bcs_ref);
                // Get current min_approvals to pass to the config update function
                let current_min_approvals = treasury::get_min_approvals_required(treasury_chest);
                treasury::admin_update_treasury_config(
                    treasury_admin_cap, treasury_chest, current_min_approvals, new_value, ctx
                );
            } else {
                abort(E_INVALID_TARGET_MODULE_OR_PARAM_NAME);
            }
        } else {
            abort(E_INVALID_TARGET_MODULE_OR_PARAM_NAME); // Invalid target module
        };

        event::emit(ParameterChangeExecuted {
            proposal_id: proposal.id,
            target_module: *target_module_str,
            parameter_name: *param_name_str,
            new_value_bcs: *new_value_bcs_ref, // Copy the vector for the event
        });
    }

    /// Executes an emergency action. Logic depends heavily on the nature of the emergency.
    fun execute_emergency_action(
        proposal: &Proposal,
        staking_system_state: &mut GovernanceSystemState,
        _treasury_chest: &mut TreasuryChest, // Example, might not be needed
        staking_admin_cap: &StakingAdminCap, // Example, if pausing staking
        _treasury_admin_cap: &TreasuryAdminCap, // Example, if pausing treasury
        ctx: &mut TxContext
    ) {
        // Example: Proposal description might indicate "PAUSE_STAKING"
        // This requires parsing proposal.description or having structured emergency action types.
        let action_description_str = string::utf8(b"Emergency action: Staking system paused (example).");
        if (proposal.description == string::utf8(b"EMERGENCY:PAUSE_STAKING")) { // Highly simplified
             // delegation_staking::admin_set_staking_paused(staking_admin_cap, staking_system_state, true, ctx);
             abort(E_ACTION_FAILED_PLACEHOLDER); // Placeholder until pause function exists
        } else {
            action_description_str = string::utf8(b"Emergency action: Unspecified action based on proposal description.");
        };

        event::emit(EmergencyActionExecuted {
            proposal_id: proposal.id,
            action_description: action_description_str,
        });
    }

    /// Placeholder for executing general proposals that don't fit other categories.
    fun execute_general_action(
        proposal: &Proposal,
        _ctx: &mut TxContext
    ) {
        // Logic depends entirely on what the general proposal entails.
        // Could involve emitting a signal, logging information, or relying on off-chain interpretation.
        event::emit(GeneralActionExecuted {
            proposal_id: proposal.id,
            action_description: proposal.description, // Use proposal's description
        });
    }

    /// Transfers the ProposalExecutionCap to a new address. Only current owner can call.
    public entry fun transfer_proposal_execution_cap(cap: ProposalExecutionCap, recipient: address, _ctx: &mut TxContext) {
        transfer::transfer(cap, recipient);
    }
}

