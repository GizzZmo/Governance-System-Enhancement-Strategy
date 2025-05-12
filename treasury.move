// File: sources/treasury.move
// Manages the community treasury, funding proposals, and multi-signature controls.
// Enhanced version with on-chain multi-sig proposals and improved access control.

module hybrid_governance::treasury {
    use std::signer;
    use std::option::{Self, Option, some, none};
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, zero, join, split, value};
    use sui::sui::SUI; // Assuming SUI is the treasury token
    use sui::object::{Self, ID, UID, new};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender, epoch};
    use sui::table::{Self, Table};
    use sui::event; // Import the event module

    // === Structs ===

    /// The main Treasury object, a shared object holding funds and configuration.
    struct TreasuryChest has key {
        id: UID,
        funds: Balance<SUI>,
        // --- Multi-Sig Configuration ---
        approvers: vector<address>, // List of addresses authorized to approve withdrawals
        min_approvals_required: u64, // Minimum approvals needed for a withdrawal proposal
        max_approvers: u64, // Maximum number of approvers allowed
        // --- On-Chain Multi-Sig State ---
        withdrawal_proposals: Table<u64, WithdrawalProposal>, // Track pending withdrawals
        next_withdrawal_proposal_id: u64,
        // --- Governance Access ---
        // TreasuryAccessCap object ID is stored elsewhere (e.g., governance module)
    }

    /// Represents a pending withdrawal proposal requiring multi-sig approval.
    struct WithdrawalProposal has key, store { // Added key for potential direct access if needed
        id: UID, // Use object ID as the unique identifier
        proposal_internal_id: u64, // Sequential ID for easier reference
        proposer: address,
        recipient: address,
        amount: u64,
        reason: vector<u8>,
        approvals_received: vector<address>, // Addresses that have approved this
        executed: bool,
        // created_epoch: u64, // Optional: Track creation time
        // expiry_epoch: u64, // Optional: Add expiry logic
    }

    /// Capability object, held by the governance module (or proposal_handler),
    /// authorizing it to request funds from the treasury upon successful proposal execution.
    struct TreasuryAccessCap has key, store {
        id: UID,
        // description: vector<u8>, // e.g., "Capability for Governance Module to access Treasury"
    }

    // === Events ===

    struct FundsDeposited has copy, drop {
        depositor: address,
        amount: u64,
        new_balance: u64,
    }

    struct FundsWithdrawnByGovernance has copy, drop {
        recipient: address,
        amount: u64,
        remaining_balance: u64,
    }

    struct WithdrawalProposed has copy, drop {
        proposal_id: u64,
        proposer: address,
        recipient: address,
        amount: u64,
    }

    struct WithdrawalApproved has copy, drop {
        proposal_id: u64,
        approver: address,
        current_approvals: u64,
        required_approvals: u64,
    }

    struct WithdrawalExecuted has copy, drop {
        proposal_id: u64,
        executor: address, // Address that called the execute function
        recipient: address,
        amount: u64,
        remaining_balance: u64,
    }

    struct ApproverAdded has copy, drop {
        new_approver: address,
        added_by: address, // Or indicate if by multi-sig action
        current_approver_count: u64,
    }

    struct ApproverRemoved has copy, drop {
        removed_approver: address,
        removed_by: address, // Or indicate if by multi-sig action
        current_approver_count: u64,
    }

    struct ConfigUpdated has copy, drop {
        setter: address,
        new_min_approvals: u64,
        new_max_approvers: u64,
    }


    // === Errors ===
    const E_INSUFFICIENT_FUNDS_IN_TREASURY: u64 = 201;
    const E_NOT_AN_APPROVER: u64 = 202;
    const E_ALREADY_APPROVED: u64 = 203;
    const E_WITHDRAWAL_PROPOSAL_NOT_FOUND: u64 = 204;
    const E_NOT_ENOUGH_APPROVALS: u64 = 205;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 206;
    const E_INVALID_TREASURY_ACCESS_CAP: u64 = 207; // Keep for governance access
    const E_AMOUNT_MUST_BE_POSITIVE: u64 = 208;
    const E_APPROVER_LIST_FULL: u64 = 209;
    const E_APPROVER_ALREADY_EXISTS: u64 = 210;
    const E_CANNOT_REMOVE_NON_EXISTENT_APPROVER: u64 = 211;
    const E_SENDER_NOT_AUTHORIZED_FOR_CONFIG: u64 = 212; // For admin/config changes
    const E_INVALID_CONFIG_VALUE: u64 = 213; // e.g., min_approvals > num_approvers
    const E_PROPOSER_MUST_BE_APPROVER: u64 = 214; // Require approvers to propose withdrawals

    // === Init ===
    fun init(ctx: &mut TxContext) {
        // Initial approvers could be set here or added via governance/admin action later
        let initial_approvers = vector::empty<address>();
        // Example: Add deployer as the first approver
        // vector::push_back(&mut initial_approvers, sender(ctx));

        transfer::share_object(TreasuryChest {
            id: object::new(ctx),
            funds: balance::zero(),
            approvers: initial_approvers,
            min_approvals_required: 1, // Sensible default if only 1 approver initially
            max_approvers: 5,         // Default max approvers
            withdrawal_proposals: table::new(ctx),
            next_withdrawal_proposal_id: 0,
        });

        // Create the access capability for governance-controlled withdrawals.
        transfer::transfer(
            TreasuryAccessCap { id: object::new(ctx) },
            sender(ctx) // Deployer gets the cap initially
        );
    }

    // === Public Entry Functions ===

    /// Deposits SUI into the TreasuryChest. Anyone can call this.
    public entry fun deposit_funds(
        treasury_chest: &mut TreasuryChest,
        coins_to_deposit: Coin<SUI>,
        _ctx: &mut TxContext // Context not needed for logic but required for entry fun
    ) {
        let amount = coin::value(&coins_to_deposit);
        assert!(amount > 0, E_AMOUNT_MUST_BE_POSITIVE);
        balance::join(&mut treasury_chest.funds, coin::into_balance(coins_to_deposit));

        event::emit(FundsDeposited {
            depositor: sender(_ctx), // Use context here to get sender
            amount,
            new_balance: balance::value(&treasury_chest.funds),
        });
    }

    /// Called by the `proposal_handler` (via `governance`) after a funding proposal is approved.
    /// This requires the `TreasuryAccessCap` passed by the authorized module.
    public entry fun process_approved_funding_by_governance(
        treasury_chest: &mut TreasuryChest,
        _access_cap: &TreasuryAccessCap, // Proof of authorization from governance
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
            recipient,
            amount: amount_to_withdraw,
            remaining_balance: balance::value(&treasury_chest.funds),
        });
    }

    // --- On-Chain Multi-Sig Withdrawal Functions ---

    /// Propose a withdrawal from the treasury. Must be called by a current approver.
    public entry fun propose_withdrawal(
        treasury_chest: &mut TreasuryChest,
        recipient: address,
        amount: u64,
        reason: vector<u8>,
        ctx: &mut TxContext
    ) {
        let proposer = sender(ctx);
        assert!(vector::contains(&treasury_chest.approvers, &proposer), E_PROPOSER_MUST_BE_APPROVER);
        assert!(amount > 0, E_AMOUNT_MUST_BE_POSITIVE);
        // Optional: Check if amount exceeds treasury balance here, or defer to execution
        // assert!(balance::value(&treasury_chest.funds) >= amount, E_INSUFFICIENT_FUNDS_IN_TREASURY);

        let proposal_internal_id = treasury_chest.next_withdrawal_proposal_id;
        treasury_chest.next_withdrawal_proposal_id = proposal_internal_id + 1;

        let withdrawal_proposal = WithdrawalProposal {
            id: object::new(ctx), // Each proposal is a distinct object
            proposal_internal_id,
            proposer,
            recipient,
            amount,
            reason,
            approvals_received: vector::singleton(proposer), // Proposer automatically approves
            executed: false,
            // created_epoch: epoch(ctx),
        };

        table::add(&mut treasury_chest.withdrawal_proposals, proposal_internal_id, withdrawal_proposal);

        event::emit(WithdrawalProposed {
            proposal_id: proposal_internal_id,
            proposer,
            recipient,
            amount,
        });
        // Also emit an approval event for the proposer's automatic approval
        event::emit(WithdrawalApproved {
            proposal_id: proposal_internal_id,
            approver: proposer,
            current_approvals: 1,
            required_approvals: treasury_chest.min_approvals_required,
        });
    }

    /// Approve a pending withdrawal proposal. Must be called by a current approver who hasn't approved yet.
    public entry fun approve_withdrawal(
        treasury_chest: &mut TreasuryChest,
        proposal_id: u64,
        ctx: &mut TxContext
    ) {
        let approver = sender(ctx);
        assert!(vector::contains(&treasury_chest.approvers, &approver), E_NOT_AN_APPROVER);

        let proposal = table::borrow_mut(&mut treasury_chest.withdrawal_proposals, proposal_id);
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        assert!(!vector::contains(&proposal.approvals_received, &approver), E_ALREADY_APPROVED);

        vector::push_back(&mut proposal.approvals_received, approver);
        let current_approvals_count = vector::length(&proposal.approvals_received);

        event::emit(WithdrawalApproved {
            proposal_id,
            approver,
            current_approvals: current_approvals_count,
            required_approvals: treasury_chest.min_approvals_required,
        });
    }

    /// Execute a withdrawal proposal that has received sufficient approvals. Can be called by anyone.
    public entry fun execute_withdrawal(
        treasury_chest: &mut TreasuryChest,
        proposal_id: u64,
        ctx: &mut TxContext
    ) {
        assert!(table::contains(&treasury_chest.withdrawal_proposals, proposal_id), E_WITHDRAWAL_PROPOSAL_NOT_FOUND);
        // Borrow immutably first to check conditions without holding mutable borrow for long
        let proposal_ref = table::borrow(&treasury_chest.withdrawal_proposals, proposal_id);

        assert!(!proposal_ref.executed, E_PROPOSAL_ALREADY_EXECUTED);
        let approvals_count = vector::length(&proposal_ref.approvals_received);
        assert!(approvals_count >= treasury_chest.min_approvals_required, E_NOT_ENOUGH_APPROVALS);
        let amount_to_withdraw = proposal_ref.amount;
        let recipient = proposal_ref.recipient;
        assert!(balance::value(&treasury_chest.funds) >= amount_to_withdraw, E_INSUFFICIENT_FUNDS_IN_TREASURY);

        // Now borrow mutably to execute
        let proposal = table::borrow_mut(&mut treasury_chest.withdrawal_proposals, proposal_id);
        proposal.executed = true; // Mark as executed first

        let withdrawn_balance = balance::split(&mut treasury_chest.funds, amount_to_withdraw);
        let withdrawn_coins = coin::from_balance(withdrawn_balance, ctx);
        transfer::public_transfer(withdrawn_coins, recipient);

        event::emit(WithdrawalExecuted {
            proposal_id,
            executor: sender(ctx),
            recipient,
            amount: amount_to_withdraw,
            remaining_balance: balance::value(&treasury_chest.funds),
        });

        // Optional: Remove the executed proposal from the table to save space,
        // but keeping it allows for historical queries.
        // let executed_proposal = table::remove(&mut treasury_chest.withdrawal_proposals, proposal_id);
        // object::delete(executed_proposal.id); // Delete the object itself
    }


    // --- Multi-Sig Approver Management Functions (Example - requires proper auth) ---
    // These functions should ideally be controlled by governance or a secure mechanism.
    // For simplicity, let's assume they require the sender to be an existing approver.
    // A more robust system might require a multi-sig proposal itself to change approvers.

    public entry fun add_approver(
        treasury_chest: &mut TreasuryChest,
        new_approver: address,
        ctx: &mut TxContext
    ) {
        let sender = sender(ctx);
        // Simple Auth: Sender must be an existing approver. Needs improvement for security.
        assert!(vector::contains(&treasury_chest.approvers, &sender), E_NOT_AN_APPROVER);
        // TODO: Implement stronger auth (e.g., require M/N approval via a specific proposal type)

        assert!(vector::length(&treasury_chest.approvers) < treasury_chest.max_approvers, E_APPROVER_LIST_FULL);
        assert!(!vector::contains(&treasury_chest.approvers, &new_approver), E_APPROVER_ALREADY_EXISTS);

        vector::push_back(&mut treasury_chest.approvers, new_approver);

        event::emit(ApproverAdded {
            new_approver,
            added_by: sender,
            current_approver_count: vector::length(&treasury_chest.approvers),
        });
    }

    public entry fun remove_approver(
        treasury_chest: &mut TreasuryChest,
        approver_to_remove: address,
        ctx: &mut TxContext
    ) {
        let sender = sender(ctx);
        // Simple Auth: Sender must be an existing approver. Needs improvement.
        assert!(vector::contains(&treasury_chest.approvers, &sender), E_NOT_AN_APPROVER);
        // TODO: Implement stronger auth. Ensure not removing the last approver if min_approvals > 0.

        let mut i = 0;
        let mut found = false;
        let approvers_len = vector::length(&treasury_chest.approvers);
        while (i < approvers_len) {
            if (*vector::borrow(&treasury_chest.approvers, i) == approver_to_remove) {
                // Check if removing this approver would make it impossible to reach min_approvals
                assert!((approvers_len - 1) >= treasury_chest.min_approvals_required || treasury_chest.min_approvals_required == 0, E_INVALID_CONFIG_VALUE);
                vector::remove(&mut treasury_chest.approvers, i);
                found = true;
                break
            };
            i = i + 1;
        };
        assert!(found, E_CANNOT_REMOVE_NON_EXISTENT_APPROVER);

        event::emit(ApproverRemoved {
            removed_approver: approver_to_remove,
            removed_by: sender,
            current_approver_count: vector::length(&treasury_chest.approvers),
        });
    }

    // --- Configuration Management (Example - requires proper auth) ---
    public entry fun update_treasury_config(
        treasury_chest: &mut TreasuryChest,
        new_min_approvals: u64,
        new_max_approvers: u64,
        ctx: &mut TxContext
    ) {
        let sender = sender(ctx);
        // Auth: Only allow specific admin role or governance action
        // assert!(is_authorized_admin(sender), E_SENDER_NOT_AUTHORIZED_FOR_CONFIG);
        // TODO: Implement proper authorization check (e.g., via governance proposal)

        // Basic validation
        assert!(new_min_approvals <= vector::length(&treasury_chest.approvers), E_INVALID_CONFIG_VALUE);
        assert!(new_min_approvals <= new_max_approvers, E_INVALID_CONFIG_VALUE);
        assert!(vector::length(&treasury_chest.approvers) <= new_max_approvers, E_INVALID_CONFIG_VALUE);

        treasury_chest.min_approvals_required = new_min_approvals;
        treasury_chest.max_approvers = new_max_approvers;

        event::emit(ConfigUpdated {
            setter: sender,
            new_min_approvals,
            new_max_approvers,
        });
    }

    // === Getter Functions ===

    public fun get_treasury_balance(treasury_chest: &TreasuryChest): u64 {
        balance::value(&treasury_chest.funds)
    }

    public fun get_approvers(treasury_chest: &TreasuryChest): vector<address> {
        *&treasury_chest.approvers // Return a copy
    }

    public fun get_min_approvals_required(treasury_chest: &TreasuryChest): u64 {
        treasury_chest.min_approvals_required
    }

    public fun get_max_approvers(treasury_chest: &TreasuryChest): u64 {
        treasury_chest.max_approvers
    }

    public fun get_withdrawal_proposal(treasury_chest: &TreasuryChest, proposal_id: u64): &WithdrawalProposal {
        assert!(table::contains(&treasury_chest.withdrawal_proposals, proposal_id), E_WITHDRAWAL_PROPOSAL_NOT_FOUND);
        table::borrow(&treasury_chest.withdrawal_proposals, proposal_id)
    }

    public fun get_next_proposal_id(treasury_chest: &TreasuryChest): u64 {
        treasury_chest.next_withdrawal_proposal_id
    }

}
