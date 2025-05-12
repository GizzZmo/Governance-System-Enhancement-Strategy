// File: sources/treasury.move
// Manages the community treasury, funding proposals, and multi-signature controls.
module hybrid_governance_pkg::treasury {
    use std::option::{Self, Option, some, none, is_some, borrow as option_borrow, destroy_some};
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, zero, join, split, value, from_value, destroy_zero};
    use sui::sui::SUI; // Assuming SUI is the treasury token
    use sui::object::{Self, ID, UID, new, id as object_id};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender}; // Removed unused 'epoch'
    use sui::table::{Self, Table, add as table_add, borrow as table_borrow, borrow_mut as table_borrow_mut, contains as table_contains, remove as table_remove};
    use sui::event;

    // === Structs ===

    /// Capability object for general treasury access (e.g., by governance for funding).
    /// Transferred to the governance module or proposal_handler.
    struct TreasuryAccessCap has key, store { id: UID }

    /// Capability object for administrative actions on the treasury (e.g., changing config, managing approvers).
    /// Transferred to an admin or the governance module.
    struct TreasuryAdminCap has key, store { id: UID }

    /// The main Treasury object, a shared object holding funds and configuration.
    struct TreasuryChest has key {
        id: UID,
        funds: Balance<SUI>,
        // --- Multi-Sig Configuration & State ---
        approvers: vector<address>, // List of addresses authorized to approve direct withdrawals
        min_approvals_required: u64, // Minimum approvals needed for a direct withdrawal proposal
        max_approvers: u64, // Maximum number of approvers allowed
        withdrawal_proposals: Table<u64, WithdrawalProposal>, // Tracks pending direct withdrawals
        next_withdrawal_proposal_id: u64,
    }

    /// Represents a pending direct withdrawal proposal requiring multi-sig approval.
    struct WithdrawalProposal has key, store { // Added key for direct object access if needed
        id: UID, // UID of this WithdrawalProposal object
        proposal_internal_id: u64, // Sequential ID for easier reference in the Table
        proposer: address,
        recipient: address,
        amount: u64,
        reason: vector<u8>, // String as vector<u8>
        approvals_received: vector<address>, // Addresses that have approved this
        executed: bool,
    }

    // === Events ===
    struct FundsDeposited has copy, drop { depositor: address, amount: u64, new_balance: u64 }
    struct FundsWithdrawnByGovernance has copy, drop { proposal_id: ID, recipient: address, amount: u64, remaining_balance: u64 }
    struct DirectWithdrawalProposed has copy, drop { withdrawal_proposal_id: u64, proposer: address, recipient: address, amount: u64, reason: vector<u8> }
    struct DirectWithdrawalApproved has copy, drop { withdrawal_proposal_id: u64, approver: address, current_approvals: u64, required_approvals: u64 }
    struct DirectWithdrawalExecuted has copy, drop { withdrawal_proposal_id: u64, executor: address, recipient: address, amount: u64, remaining_balance: u64 }
    struct ApproverAdded has copy, drop { new_approver: address, added_by: address, current_approver_count: u64 }
    struct ApproverRemoved has copy, drop { removed_approver: address, removed_by: address, current_approver_count: u64 }
    struct TreasuryConfigUpdated has copy, drop { updated_by: address, new_min_approvals: u64, new_max_approvers: u64 }

    // === Errors ===
    const E_INSUFFICIENT_FUNDS_IN_TREASURY: u64 = 201;
    const E_NOT_AN_APPROVER: u64 = 202;
    const E_ALREADY_APPROVED: u64 = 203;
    const E_WITHDRAWAL_PROPOSAL_NOT_FOUND: u64 = 204;
    const E_NOT_ENOUGH_APPROVALS: u64 = 205;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 206;
    const E_AMOUNT_MUST_BE_POSITIVE: u64 = 208;
    const E_APPROVER_LIST_FULL: u64 = 209;
    const E_APPROVER_ALREADY_EXISTS: u64 = 210;
    const E_CANNOT_REMOVE_NON_EXISTENT_APPROVER: u64 = 211;
    const E_UNAUTHORIZED_ADMIN_ACTION: u64 = 212;
    const E_INVALID_CONFIG_VALUE: u64 = 213;
    const E_PROPOSER_MUST_BE_APPROVER: u64 = 214; // For direct withdrawal proposals
    const E_REASON_TOO_LONG: u64 = 215; // Example for input validation

    // === Init ===
    /// Initializes the Treasury: creates TreasuryChest, TreasuryAccessCap, and TreasuryAdminCap.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(TreasuryChest {
            id: object::new(ctx),
            funds: balance::zero(),
            approvers: vector::empty<address>(), // Start with no approvers; add via admin function
            min_approvals_required: 1, // Default, sensible if only 1 approver added initially
            max_approvers: 5,          // Default max approvers
            withdrawal_proposals: table::new(ctx),
            next_withdrawal_proposal_id: 0,
        });

        // TreasuryAccessCap is for governance-controlled withdrawals (via proposals)
        transfer::transfer(TreasuryAccessCap { id: object::new(ctx) }, sender(ctx));
        // TreasuryAdminCap is for administrative actions (config, approver list)
        transfer::transfer(TreasuryAdminCap { id: object::new(ctx) }, sender(ctx));
    }

    // === Public Entry Functions ===

    /// Deposits SUI into the TreasuryChest. Anyone can call this.
    public entry fun deposit_funds(
        treasury_chest: &mut TreasuryChest,
        coins_to_deposit: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&coins_to_deposit);
        assert!(amount > 0, E_AMOUNT_MUST_BE_POSITIVE);
        balance::join(&mut treasury_chest.funds, coin::into_balance(coins_to_deposit));

        event::emit(FundsDeposited {
            depositor: sender(ctx),
            amount,
            new_balance: balance::value(&treasury_chest.funds),
        });
    }

    /// Called by `proposal_handler` after a governance funding proposal is approved.
    /// Requires `TreasuryAccessCap`.
    public entry fun process_approved_funding_by_governance(
        treasury_chest: &mut TreasuryChest,
        _access_cap: &TreasuryAccessCap, // Proof of authorization from governance
        proposal_id_ref: ID, // ID of the original governance proposal for event logging
        amount_to_withdraw: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(amount_to_withdraw > 0, E_AMOUNT_MUST_BE_POSITIVE);
        assert!(balance::value(&treasury_chest.funds) >= amount_to_withdraw, E_INSUFFICIENT_FUNDS_IN_TREASURY);

        let withdrawn_balance = balance::split(&mut treasury_chest.funds, amount_to_withdraw);
        let withdrawn_coins = coin::from_balance(withdrawn_balance, ctx);
        transfer::public_transfer(withdrawn_coins, recipient);

        event::emit(FundsWithdrawnByGovernance {
            proposal_id: proposal_id_ref,
            recipient,
            amount: amount_to_withdraw,
            remaining_balance: balance::value(&treasury_chest.funds),
        });
    }

    // --- On-Chain Multi-Sig Direct Withdrawal Functions ---

    /// Proposes a direct withdrawal from treasury, initiated by an approver.
    public entry fun propose_direct_withdrawal(
        treasury_chest: &mut TreasuryChest,
        recipient: address,
        amount: u64,
        reason: vector<u8>, // Max length check example
        ctx: &mut TxContext
    ) {
        let proposer = sender(ctx);
        assert!(vector::contains(&treasury_chest.approvers, &proposer), E_PROPOSER_MUST_BE_APPROVER);
        assert!(amount > 0, E_AMOUNT_MUST_BE_POSITIVE);
        assert!(vector::length(&reason) <= 256, E_REASON_TOO_LONG); // Example validation

        let proposal_internal_id = treasury_chest.next_withdrawal_proposal_id;
        treasury_chest.next_withdrawal_proposal_id = proposal_internal_id + 1;

        let withdrawal_proposal_uid = object::new(ctx);
        let withdrawal_proposal = WithdrawalProposal {
            id: withdrawal_proposal_uid,
            proposal_internal_id,
            proposer,
            recipient,
            amount,
            reason, // Store directly
            approvals_received: vector::singleton(proposer), // Proposer automatically approves
            executed: false,
        };
        // This proposal object itself is not shared; it's stored in the table.
        table_add(&mut treasury_chest.withdrawal_proposals, proposal_internal_id, withdrawal_proposal);

        event::emit(DirectWithdrawalProposed {
            withdrawal_proposal_id: proposal_internal_id,
            proposer, recipient, amount, reason // Emit the reason
        });
        event::emit(DirectWithdrawalApproved { // Proposer's auto-approval
            withdrawal_proposal_id: proposal_internal_id, approver: proposer, current_approvals: 1,
            required_approvals: treasury_chest.min_approvals_required,
        });
    }

    /// Approves a pending direct withdrawal proposal. Called by an approver.
    public entry fun approve_direct_withdrawal(
        treasury_chest: &mut TreasuryChest,
        withdrawal_proposal_id: u64,
        ctx: &mut TxContext
    ) {
        let approver = sender(ctx);
        assert!(vector::contains(&treasury_chest.approvers, &approver), E_NOT_AN_APPROVER);
        assert!(table_contains(&treasury_chest.withdrawal_proposals, withdrawal_proposal_id), E_WITHDRAWAL_PROPOSAL_NOT_FOUND);

        let proposal = table_borrow_mut(&mut treasury_chest.withdrawal_proposals, withdrawal_proposal_id);
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        assert!(!vector::contains(&proposal.approvals_received, &approver), E_ALREADY_APPROVED);

        vector::push_back(&mut proposal.approvals_received, approver);
        event::emit(DirectWithdrawalApproved {
            withdrawal_proposal_id, approver, current_approvals: vector::length(&proposal.approvals_received),
            required_approvals: treasury_chest.min_approvals_required,
        });
    }

    /// Executes a direct withdrawal proposal that has received sufficient approvals.
    public entry fun execute_direct_withdrawal(
        treasury_chest: &mut TreasuryChest,
        withdrawal_proposal_id: u64,
        ctx: &mut TxContext
    ) {
        assert!(table_contains(&treasury_chest.withdrawal_proposals, withdrawal_proposal_id), E_WITHDRAWAL_PROPOSAL_NOT_FOUND);
        // Borrow immutably first for checks
        let proposal_ref = table_borrow(&treasury_chest.withdrawal_proposals, withdrawal_proposal_id);
        assert!(!proposal_ref.executed, E_PROPOSAL_ALREADY_EXECUTED);
        assert!(vector::length(&proposal_ref.approvals_received) >= treasury_chest.min_approvals_required, E_NOT_ENOUGH_APPROVALS);
        let amount_to_withdraw = proposal_ref.amount;
        let recipient = proposal_ref.recipient;
        assert!(balance::value(&treasury_chest.funds) >= amount_to_withdraw, E_INSUFFICIENT_FUNDS_IN_TREASURY);

        // Borrow mutably to execute
        let proposal = table_borrow_mut(&mut treasury_chest.withdrawal_proposals, withdrawal_proposal_id);
        proposal.executed = true; // Mark executed

        let withdrawn_balance = balance::split(&mut treasury_chest.funds, amount_to_withdraw);
        let withdrawn_coins = coin::from_balance(withdrawn_balance, ctx);
        transfer::public_transfer(withdrawn_coins, recipient);

        event::emit(DirectWithdrawalExecuted {
            withdrawal_proposal_id, executor: sender(ctx), recipient, amount: amount_to_withdraw,
            remaining_balance: balance::value(&treasury_chest.funds),
        });
        // Optional: Remove executed proposal from table and delete its object
        // let executed_proposal_obj = table_remove(&mut treasury_chest.withdrawal_proposals, withdrawal_proposal_id);
        // object::delete(executed_proposal_obj.id);
    }

    // --- Administrative Functions (Require TreasuryAdminCap) ---

    /// Updates key treasury configuration parameters (min/max approvers).
    public entry fun admin_update_treasury_config(
        _admin_cap: &TreasuryAdminCap, // Authorization
        treasury_chest: &mut TreasuryChest,
        new_min_approvals: u64,
        new_max_approvers: u64,
        ctx: &mut TxContext
    ) {
        assert!(new_min_approvals > 0 && new_min_approvals <= new_max_approvers, E_INVALID_CONFIG_VALUE);
        let current_approver_count = vector::length(&treasury_chest.approvers);
        assert!(current_approver_count <= new_max_approvers, E_INVALID_CONFIG_VALUE); // Cannot set max lower than current count
        assert!(new_min_approvals <= current_approver_count || current_approver_count == 0, E_INVALID_CONFIG_VALUE); // Min cannot be > current unless 0

        treasury_chest.min_approvals_required = new_min_approvals;
        treasury_chest.max_approvers = new_max_approvers;

        event::emit(TreasuryConfigUpdated {
            updated_by: sender(ctx), new_min_approvals, new_max_approvers,
        });
    }

    /// Adds an approver to the multi-sig list. Requires TreasuryAdminCap.
    public entry fun admin_add_approver(
        _admin_cap: &TreasuryAdminCap,
        treasury_chest: &mut TreasuryChest,
        new_approver: address,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&treasury_chest.approvers) < treasury_chest.max_approvers, E_APPROVER_LIST_FULL);
        assert!(!vector::contains(&treasury_chest.approvers, &new_approver), E_APPROVER_ALREADY_EXISTS);
        vector::push_back(&mut treasury_chest.approvers, new_approver);
        event::emit(ApproverAdded { new_approver, added_by: sender(ctx), current_approver_count: vector::length(&treasury_chest.approvers) });
    }

    /// Removes an approver from the multi-sig list. Requires TreasuryAdminCap.
    public entry fun admin_remove_approver(
        _admin_cap: &TreasuryAdminCap,
        treasury_chest: &mut TreasuryChest,
        approver_to_remove: address,
        ctx: &mut TxContext
    ) {
        let mut i = 0;
        let mut found = false;
        let approvers_len = vector::length(&treasury_chest.approvers);
        // Ensure removing an approver doesn't make it impossible to meet min_approvals_required
        assert!((approvers_len - 1) >= treasury_chest.min_approvals_required || treasury_chest.min_approvals_required == 0 || approvers_len == 1, E_INVALID_CONFIG_VALUE);

        while (i < approvers_len) {
            if (*vector::borrow(&treasury_chest.approvers, i) == approver_to_remove) {
                vector::remove(&mut treasury_chest.approvers, i);
                found = true;
                break
            };
            i = i + 1;
        };
        assert!(found, E_CANNOT_REMOVE_NON_EXISTENT_APPROVER);
        event::emit(ApproverRemoved { removed_approver: approver_to_remove, removed_by: sender(ctx), current_approver_count: vector::length(&treasury_chest.approvers) });
    }

    /// Transfers the TreasuryAccessCap to a new address. Only current owner can call.
    public entry fun transfer_treasury_access_cap(cap: TreasuryAccessCap, recipient: address, _ctx: &mut TxContext) {
        transfer::transfer(cap, recipient);
    }

    /// Transfers the TreasuryAdminCap to a new address. Only current owner can call.
    public entry fun transfer_treasury_admin_cap(cap: TreasuryAdminCap, recipient: address, _ctx: &mut TxContext) {
        transfer::transfer(cap, recipient);
    }

    // === Getter Functions (Read-only) ===
    public fun get_treasury_balance(treasury_chest: &TreasuryChest): u64 { value(&treasury_chest.funds) }
    public fun get_approvers(treasury_chest: &TreasuryChest): vector<address> { *&treasury_chest.approvers } // Returns a copy
    public fun get_min_approvals_required(treasury_chest: &TreasuryChest): u64 { treasury_chest.min_approvals_required }
    public fun get_max_approvers(treasury_chest: &TreasuryChest): u64 { treasury_chest.max_approvers }
    public fun get_withdrawal_proposal(treasury_chest: &TreasuryChest, proposal_id: u64): &WithdrawalProposal {
        assert!(table_contains(&treasury_chest.withdrawal_proposals, proposal_id), E_WITHDRAWAL_PROPOSAL_NOT_FOUND);
        table_borrow(&treasury_chest.withdrawal_proposals, proposal_id)
    }
    public fun get_next_direct_withdrawal_proposal_id(treasury_chest: &TreasuryChest): u64 { treasury_chest.next_withdrawal_proposal_id }
}

