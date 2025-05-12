// File: sources/governance.move
// Manages proposal submission, voting, and basic execution checks.
module hybrid_governance_pkg::governance {
    use std::string::{Self, String};
    use std::option::{Self, Option, some, none, is_some, destroy_some};
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID, new, uid_to_inner};
    use sui::tx_context::{Self, TxContext, sender};
    use sui::transfer;
    use sui::event;

    // Import necessary types from other modules within the same package
    // The `hybrid_governance_pkg` named address from Move.toml will resolve to the package's ID after deployment.
    use hybrid_governance_pkg::delegation_staking::{Self, StakedSui, GovernanceSystemState, AdminCap as StakingAdminCap};
    use hybrid_governance_pkg::treasury::{Self, TreasuryChest, TreasuryAccessCap, TreasuryAdminCap};
    use hybrid_governance_pkg::proposal_handler; // Import the module itself for its types like ProposalExecutionCap

    // === Constants ===
    const MAX_TIME_BONUS: u128 = 5; // Maximum bonus points for voting early
    const DEFAULT_VOTING_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

    // === Structs ===

    /// Represents a governance proposal. This object is shared after creation.
    struct Proposal has key, store {
        id: ID, // The unique ID of this Proposal object
        creator: address,
        description: String,
        proposal_type: u8, // 0: General, 1: Minor Param, 2: Critical Param/Vetoable, 3: Funding, 4: Emergency
        // --- Voting State ---
        votes_for: u128,
        votes_against: u128,
        veto_votes: u128,
        // --- Quorum ---
        quorum_threshold_percentage: u8,
        total_stake_at_creation: u128, // Total system stake when proposal was created
        // --- Timing ---
        start_time_ms: u64,
        end_time_ms: u64,
        voting_duration_ms: u64,
        // --- Execution ---
        executed: bool,
        // --- Proposal Specific Data ---
        funding_amount: Option<u64>,
        funding_recipient: Option<address>,
        param_target_module: Option<String>, // e.g., "staking", "treasury"
        param_name: Option<String>,          // e.g., "min_validator_stake"
        param_new_value_bcs: Option<vector<u8>>, // BCS serialized new value
    }

    // === Errors ===
    const E_INSUFFICIENT_STAKE_FOR_VOTE: u64 = 1;
    const E_QUORUM_NOT_MET: u64 = 2;
    const E_PROPOSAL_REJECTED: u64 = 3;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 4;
    const E_INVALID_PROPOSAL_TYPE_FOR_VETO: u64 = 5;
    const E_VOTING_PERIOD_NOT_OVER: u64 = 6;
    const E_INVALID_PROPOSAL_TYPE: u64 = 7;
    const E_VOTING_PERIOD_ALREADY_ENDED: u64 = 8;
    const E_VOTING_PERIOD_NOT_STARTED: u64 = 9;
    const E_INVALID_VOTING_DURATION: u64 = 10;
    const E_ARITHMETIC_OVERFLOW: u64 = 11; // For math operations
    const E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE: u64 = 12;

    // === Events ===
    struct ProposalCreated has copy, drop {
        proposal_id: ID,
        creator: address,
        proposal_type: u8,
        description: String, // Include description in event
        quorum_percentage: u8,
        total_stake_at_creation: u128,
        end_time_ms: u64,
    }

    struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
        staked_sui_object_id: ID, // ID of the StakedSui object used
        stake_used: u128,
        base_quadratic_votes: u128,
        time_bonus: u128,
        reputation_weight_factor: u128, // e.g., 105 for 105%
        final_weighted_votes: u128,
        support: bool,
        is_veto: bool,
    }

    struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        executed_by: address, // Address that called execute_proposal
    }

    // === Public Entry Functions ===

    /// Submits a new governance proposal.
    public entry fun submit_proposal(
        description_vec: vector<u8>,
        proposal_type: u8,
        // Optional fields for specific proposal types
        funding_amount_opt: Option<u64>,
        funding_recipient_opt: Option<address>,
        param_target_module_opt: Option<vector<u8>>, // String as vector<u8>
        param_name_opt: Option<vector<u8>>,          // String as vector<u8>
        param_new_value_bcs_opt: Option<vector<u8>>,
        // System objects
        system_state: &GovernanceSystemState,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let creator_addr = sender(ctx);
        let current_time_ms = clock::timestamp_ms(clock);
        let voting_duration_ms = determine_voting_duration(proposal_type);
        let end_time_ms = current_time_ms + voting_duration_ms; // Potential overflow if duration is massive; assume reasonable.

        let quorum_percentage = determine_quorum_percentage(proposal_type);
        let total_stake = delegation_staking::get_total_system_stake(system_state) as u128;

        // Validate required fields based on proposal_type
        if (proposal_type == 3) { // Funding
            assert!(is_some(&funding_amount_opt) && is_some(&funding_recipient_opt), E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE);
        } else if (proposal_type == 1 || proposal_type == 2) { // Parameter Change
            assert!(is_some(&param_target_module_opt) && is_some(&param_name_opt) && is_some(&param_new_value_bcs_opt), E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE);
        };

        let proposal_obj_uid = new(ctx); // UID for the new Proposal object
        let proposal_id_val = uid_to_inner(&proposal_obj_uid); // Get the actual ID
        let proposal_description = string::utf8(description_vec);

        let new_proposal = Proposal {
            id: proposal_id_val,
            creator: creator_addr,
            description: proposal_description, // Store the converted String
            proposal_type,
            votes_for: 0,
            votes_against: 0,
            veto_votes: 0,
            quorum_threshold_percentage: quorum_percentage,
            total_stake_at_creation: total_stake,
            start_time_ms: current_time_ms,
            end_time_ms: end_time_ms,
            voting_duration_ms: voting_duration_ms,
            executed: false,
            funding_amount: funding_amount_opt,
            funding_recipient: funding_recipient_opt,
            // Convert vector<u8> to String for storage if present
            param_target_module: if (is_some(&param_target_module_opt)) { some(string::utf8(destroy_some(param_target_module_opt))) } else { none() },
            param_name: if (is_some(&param_name_opt)) { some(string::utf8(destroy_some(param_name_opt))) } else { none() },
            param_new_value_bcs: param_new_value_bcs_opt,
        };

        event::emit(ProposalCreated {
            proposal_id: proposal_id_val,
            creator: creator_addr,
            proposal_type,
            description: new_proposal.description, // Emit the string description
            quorum_percentage,
            total_stake_at_creation: total_stake,
            end_time_ms,
        });

        // Share the proposal object so it can be accessed for voting
        transfer::share_object(new_proposal);
    }

    /// Allows a user to cast a vote on an active proposal using their StakedSui.
    public entry fun hybrid_vote(
        proposal: &mut Proposal,         // The shared Proposal object to vote on
        staked_sui_obj: &StakedSui,    // The voter's StakedSui object
        support_vote: bool,            // True for 'yes', false for 'no'
        is_veto_flag: bool,            // True if this is a veto vote (for specific proposal types)
        clock: &Clock,
        ctx: &TxContext
    ) {
        let voter_address = sender(ctx);
        let current_time_ms = clock::timestamp_ms(clock);

        assert!(current_time_ms >= proposal.start_time_ms, E_VOTING_PERIOD_NOT_STARTED);
        assert!(current_time_ms < proposal.end_time_ms, E_VOTING_PERIOD_ALREADY_ENDED);

        let stake_amount = delegation_staking::get_staked_sui_amount(staked_sui_obj) as u128;
        let reputation = delegation_staking::get_staked_sui_reputation(staked_sui_obj);
        assert!(stake_amount > 0, E_INSUFFICIENT_STAKE_FOR_VOTE);

        let base_quadratic_votes = sqrt(stake_amount);
        let elapsed_ms = current_time_ms - proposal.start_time_ms;
        let time_bonus = calculate_time_bonus(elapsed_ms, proposal.voting_duration_ms);
        // Example: reputation of 100 -> 10% bonus, 200 -> 20% bonus. Max 1000 rep for 100% bonus (factor of 2).
        let reputation_weight_factor = 100 + (reputation / 10); // Results in a percentage factor (e.g., 110 for 110%)

        let votes_with_bonus = base_quadratic_votes + time_bonus;
        // Apply reputation factor: (base * factor) / 100
        let final_weighted_votes = (votes_with_bonus * reputation_weight_factor) / 100;

        if (is_veto_flag) {
            assert!(proposal.proposal_type == 2, E_INVALID_PROPOSAL_TYPE_FOR_VETO); // Type 2 is Critical/Vetoable
            proposal.veto_votes = proposal.veto_votes + final_weighted_votes;
        } else if (support_vote) {
            proposal.votes_for = proposal.votes_for + final_weighted_votes;
        } else {
            proposal.votes_against = proposal.votes_against + final_weighted_votes;
        }

        event::emit(VoteCast {
            proposal_id: proposal.id,
            voter: voter_address,
            staked_sui_object_id: object::id(staked_sui_obj),
            stake_used: stake_amount,
            base_quadratic_votes,
            time_bonus,
            reputation_weight_factor,
            final_weighted_votes,
            support: support_vote,
            is_veto: is_veto_flag,
        });
    }

    /// Executes a passed proposal. Can be called by anyone after the voting period ends.
    public entry fun execute_proposal(
        proposal: &mut Proposal,
        system_state: &mut GovernanceSystemState, // Mutable if handler might change it (e.g., staking params)
        clock: &Clock,
        // --- Capabilities needed by proposal_handler ---
        exec_cap: &proposal_handler::ProposalExecutionCap,
        treasury_chest: &mut TreasuryChest,
        treasury_access_cap: &TreasuryAccessCap,
        treasury_admin_cap: &TreasuryAdminCap,
        staking_admin_cap: &StakingAdminCap,
        ctx: &TxContext
    ) {
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        let current_time_ms = clock::timestamp_ms(clock);
        assert!(current_time_ms >= proposal.end_time_ms, E_VOTING_PERIOD_NOT_OVER);

        let total_votes_cast = proposal.votes_for + proposal.votes_against;
        let quorum_value = (proposal.total_stake_at_creation * (proposal.quorum_threshold_percentage as u128)) / 100;
        assert!(total_votes_cast >= quorum_value, E_QUORUM_NOT_MET);
        assert!(proposal.votes_for > proposal.votes_against, E_PROPOSAL_REJECTED);

        if (proposal.proposal_type == 2) { // Critical/Vetoable
            // Example veto threshold: 10% of total stake at proposal creation
            let veto_threshold = (proposal.total_stake_at_creation * 10) / 100;
            assert!(proposal.veto_votes < veto_threshold, E_PROPOSAL_REJECTED); // Vetoed
        }

        // Mark as executed BEFORE calling the handler to prevent re-entrancy or re-execution on handler failure.
        proposal.executed = true;

        // Call the proposal handler to perform specific actions
        proposal_handler::handle_proposal_execution(
            exec_cap,
            proposal, // Pass immutable reference now, as its 'executed' state is set
            treasury_chest,
            staking_system_state, // Pass mutable system_state
            treasury_access_cap,
            treasury_admin_cap,
            staking_admin_cap,
            ctx
        );

        event::emit(ProposalExecuted {
            proposal_id: proposal.id,
            executed_by: sender(ctx),
        });
    }

    // === Helper Functions ===

    /// Determines the required quorum percentage based on proposal type.
    fun determine_quorum_percentage(proposal_type: u8): u8 {
        if (proposal_type == 0) { 10 } // General
        else if (proposal_type == 1) { 20 } // Minor Parameter Change
        else if (proposal_type == 2) { 33 } // Critical Parameter Change (Vetoable)
        else if (proposal_type == 3) { 15 } // Funding Request
        else if (proposal_type == 4) { 40 } // Emergency
        else { abort(E_INVALID_PROPOSAL_TYPE) }
    }

    /// Determines voting duration in milliseconds based on proposal type.
    fun determine_voting_duration(proposal_type: u8): u64 {
        if (proposal_type == 4) { // Emergency
            1 * 24 * 60 * 60 * 1000 // 1 day in ms
        } else {
            DEFAULT_VOTING_DURATION_MS // Default duration for others
        }
    }

    /// Calculates time bonus (linear decay).
    fun calculate_time_bonus(elapsed_ms: u64, total_duration_ms: u64): u128 {
        if (total_duration_ms == 0) { return 0 }; // Avoid division by zero
        let elapsed_u128 = elapsed_ms as u128;
        let total_duration_u128 = total_duration_ms as u128;
        let max_bonus_u128 = MAX_TIME_BONUS;

        // Ensure elapsed time does not exceed total duration for calculation
        if (elapsed_u128 >= total_duration_u128) { return 0 }; // No bonus if voted at/after end

        // decay = (elapsed / total_duration) * MAX_TIME_BONUS
        // To prevent precision loss with integer division, multiply first:
        let decay_numerator = elapsed_u128 * max_bonus_u128;
        let decay = decay_numerator / total_duration_u128;

        // Bonus decreases over time: MAX_TIME_BONUS - decay
        if (max_bonus_u128 >= decay) {
            max_bonus_u128 - decay
        } else {
            0 // Bonus cannot be negative
        }
    }

    /// Integer square root function (Babylonian method).
    fun sqrt(x: u128): u128 {
        if (x == 0) { return 0 };
        let mut guess = x; // Start with x or x/2 for faster convergence
        let mut prev_guess = 0;
        // Iterate until guess converges or a max number of iterations for safety
        // Sui's compute budget is a consideration.
        // A loop that checks for convergence is generally fine.
        loop {
            if (guess == 0) { return 0 }; // Avoid division by zero if guess becomes 0
            prev_guess = guess;
            guess = (guess + x / guess) / 2;
            // Check for convergence: if guess is no longer changing or starts increasing
            if (guess >= prev_guess) {
                // If (prev_guess)^2 was closer than (guess)^2, use prev_guess
                // This handles cases where integer division causes oscillation around the true root.
                // For quadratic voting, exactness is less critical than a good approximation.
                // The check (guess+1)^2 <= x is for finding the floor of the true sqrt.
                if (prev_guess * prev_guess <= x) { return prev_guess } else { return guess };
            };
        };
        // Fallback, should be unreachable if loop logic is correct
        // return guess;
    }
}
