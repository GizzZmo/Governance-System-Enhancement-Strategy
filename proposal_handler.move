// File: sources/proposal_handler.move
// Handles the execution logic for different types of governance proposals
// after they have been approved by the main governance module.

// Assumes the package name defined in Move.toml is HybridGovernance
module hybrid_governance::proposal_handler {
    use std::signer; // May not be needed directly if actions are based on passed proposal data
    use std::option::{Self, Option, some, none};
    use std::vector;
    use sui::object::{Self, ID, UID, new};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;

    // Import necessary modules and types
    use hybrid_governance::governance::{Self, Proposal}; // To read proposal details
    use hybrid_governance::treasury::{Self, TreasuryChest, TreasuryAccessCap}; // To interact with treasury
    use hybrid_governance::delegation_staking::{Self, GovernanceSystemState, Validator, StakedSui}; // To change staking params etc.

    // === Structs ===

    /// Capability held by the `governance` module, required to call `handle_proposal_execution`.
    /// This ensures that proposal execution can only be triggered after successful voting checks.
    struct ProposalExecutionCap has key, store {
        id: UID,
        // description: vector<u8>, // e.g., "Capability for Governance Module to execute proposals"
    }

    // === Events ===

    struct FundingProposalExecuted has copy, drop {
        proposal_object_id: ID, // ID of the Proposal object from governance module
        recipient: address,
        amount: u64,
    }

    struct ParameterChangeExecuted has copy, drop {
        proposal_object_id: ID,
        parameter_name: vector<u8>, // e.g., "min_validator_stake"
        new_value: vector<u8>, // Store value as string/bytes for flexibility
    }

    struct GeneralProposalActionExecuted has copy, drop {
        proposal_object_id: ID,
        action_description: vector<u8>, // Description of the action taken
    }

    // === Errors ===
    const E_INVALID_EXECUTION_CAPABILITY: u64 = 301; // If the capability is missing/wrong
    const E_UNSUPPORTED_PROPOSAL_TYPE: u64 = 302;
    const E_MISSING_FUNDING_PARAMETERS: u64 = 303; // If funding proposal lacks amount/recipient
    const E_MISSING_PARAMETER_CHANGE_DATA: u64 = 304;
    const E_TREASURY_INTERACTION_FAILED: u64 = 305; // Generic error for treasury calls
    const E_STAKING_INTERACTION_FAILED: u64 = 306; // Generic error for staking calls

    // === Init ===
    // Creates the ProposalExecutionCap and transfers it to the deployer/admin.
    // This capability must then be securely transferred or assigned to the governance module.
    fun init(ctx: &mut TxContext) {
        transfer::transfer(
            ProposalExecutionCap { id: object::new(ctx) },
            sender(ctx) // Deployer gets the cap initially
        );
    }

    // === Public Entry Function (Called by Governance Module) ===

    /// The main entry point called by the `governance::execute_proposal` function.
    /// It requires the `ProposalExecutionCap` and the approved `Proposal` object.
    public entry fun handle_proposal_execution(
        _exec_cap: &ProposalExecutionCap, // Proof of authorization from governance module
        proposal: &Proposal, // Pass the approved proposal object (immutable borrow is likely sufficient)
        // --- References to other modules needed for execution ---
        treasury_chest: &mut TreasuryChest,
        treasury_access_cap: &TreasuryAccessCap, // Cap needed to call treasury withdrawal
        staking_system_state: &mut GovernanceSystemState,
        // Potentially references to other configurable modules/objects
        ctx: &mut TxContext
    ) {
        // Re-check execution status? governance module should guarantee it's not executed.
        // assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED_IN_HANDLER); // Should not happen

        let proposal_type = proposal.proposal_type;

        if (proposal_type == 0) { // General Proposal
            execute_general_action(proposal, ctx);
        } else if (proposal_type == 1 || proposal_type == 2) { // Minor or Critical Parameter Change
            execute_parameter_change(proposal, staking_system_state, treasury_chest, ctx);
        } else if (proposal_type == 3) { // Funding Request
            execute_funding_request(proposal, treasury_chest, treasury_access_cap, ctx);
        } else if (proposal_type == 4) { // Emergency Action
            execute_emergency_action(proposal, staking_system_state, treasury_chest, ctx);
        } else {
            abort(E_UNSUPPORTED_PROPOSAL_TYPE)
        };

        // Note: The `governance` module is responsible for marking the proposal as executed *after*
        // this handler function successfully completes. If this handler aborts, the proposal remains unexecuted.
    }

    // === Internal Execution Functions ===

    /// Executes a funding request by calling the treasury module.
    fun execute_funding_request(
        proposal: &Proposal,
        treasury_chest: &mut TreasuryChest,
        treasury_access_cap: &TreasuryAccessCap,
        ctx: &mut TxContext
    ) {
        // --- Extract funding details from the proposal ---
        // This assumes the Proposal struct in governance.move is extended
        // to hold funding_amount and recipient, or these are encoded in the description.
        // For now, let's assume they are placeholder values.
        let amount: u64 = 1000; // Placeholder - fetch from proposal data
        let recipient: address = @0xRECIPIENT; // Placeholder - fetch from proposal data
        assert!(amount > 0, E_MISSING_FUNDING_PARAMETERS);
        // assert!(recipient != @0x0, E_MISSING_FUNDING_PARAMETERS); // Basic check

        // Call the treasury module function that requires the capability
        treasury::process_approved_funding_by_governance(
            treasury_chest,
            treasury_access_cap,
            amount,
            recipient,
            ctx // Pass context for coin creation/transfer
        ); // Error will abort if treasury call fails

        event::emit(FundingProposalExecuted {
            proposal_object_id: object::id(proposal), // Get the ID of the proposal object
            recipient,
            amount,
        });
    }

    /// Executes a parameter change. This needs specific logic based on the parameter being changed.
    fun execute_parameter_change(
        proposal: &Proposal,
        staking_system_state: &mut GovernanceSystemState,
        treasury_chest: &mut TreasuryChest,
        ctx: &mut TxContext
    ) {
        // --- Extract parameter details from the proposal description ---
        // Example: Description might be "PARAM_CHANGE:min_validator_stake=2000000000"
        // This requires parsing logic (complex in Move, often done off-chain preparing the proposal)
        let param_name_bytes: vector<u8> = b"min_validator_stake"; // Placeholder
        let new_value_bytes: vector<u8> = b"2000000000"; // Placeholder

        // --- Apply the change based on parameter name ---
        if (param_name_bytes == b"min_validator_stake") {
            // Update logic in delegation_staking module (needs a setter function)
            // let new_stake = std::bcs::deserialize<u64>(&new_value_bytes); // Example parsing
            // delegation_staking::update_min_validator_stake(staking_system_state, new_stake, ctx);
        } else if (param_name_bytes == b"treasury_min_approvals") {
            // Update logic in treasury module (needs a setter function like update_treasury_config)
            // let new_min_approvals = std::bcs::deserialize<u64>(&new_value_bytes);
            // treasury::update_treasury_config(treasury_chest, new_min_approvals, treasury::get_max_approvers(treasury_chest), ctx);
        } else {
            // Parameter not recognized or handled here
            abort(E_MISSING_PARAMETER_CHANGE_DATA);
        };

        event::emit(ParameterChangeExecuted {
            proposal_object_id: object::id(proposal),
            parameter_name: param_name_bytes,
            new_value: new_value_bytes,
        });
    }

    /// Executes an emergency action. Logic depends heavily on the nature of the emergency.
    fun execute_emergency_action(
        proposal: &Proposal,
        _staking_system_state: &mut GovernanceSystemState, // May need to pause staking
        _treasury_chest: &mut TreasuryChest, // May need to pause withdrawals
        _ctx: &mut TxContext
    ) {
        // Example: Pause staking system (requires function in delegation_staking)
        // delegation_staking::set_staking_paused(staking_system_state, true, ctx);

        // Example: Pause treasury withdrawals (requires function in treasury)
        // treasury::set_withdrawals_paused(treasury_chest, true, ctx);

        // Emit a generic event for now
        event::emit(GeneralProposalActionExecuted {
            proposal_object_id: object::id(proposal),
            action_description: b"Emergency action executed based on proposal description.",
        });
    }

    /// Placeholder for executing general proposals that don't fit other categories.
    fun execute_general_action(
        proposal: &Proposal,
        _ctx: &mut TxContext
    ) {
        // Logic depends entirely on what the general proposal entails.
        // Could involve emitting a signal, logging information, or triggering an off-chain process.

        event::emit(GeneralProposalActionExecuted {
            proposal_object_id: object::id(proposal),
            action_description: b"General proposal action executed based on description.",
        });
    }

    // === Capability Management ===
    // Function to allow the owner (deployer/admin) to transfer the capability
    // to the governance module address/object owner.
    public entry fun transfer_execution_cap(
        cap: ProposalExecutionCap,
        recipient: address, // The address that controls the governance module
        ctx: &mut TxContext
    ) {
        // Only the owner of the cap can transfer it. Sui framework handles this.
        transfer::transfer(cap, recipient);
    }

}
