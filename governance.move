// File: sources/governance.move
// Manages proposal submission, voting, and basic execution checks.
// Updated with time-weighted voting bonus.

// Placeholder for the actual package name, will be defined in Move.toml
module hybrid_governance::governance {
    use std::signer;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::clock::{Self, Clock}; // Import Clock for time-based calculations
    use sui::object::{Self, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;

    // Import necessary types from other modules (assuming they exist)
    // These imports need the correct package ID after deployment
    use hybrid_governance::delegation_staking::{Self, StakedSui, GovernanceSystemState};

    // === Constants ===
    const MAX_TIME_BONUS: u128 = 5; // Maximum bonus points for voting early
    const DEFAULT_VOTING_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

    // === Structs ===

    /// Represents a governance proposal.
    struct Proposal has key, store {
        id: ID, // Use the object's ID as the unique identifier
        // proposal_internal_id: u64, // Optional internal counter if needed
        creator: address,
        description: String,
        proposal_type: u8, // 0: General, 1: Minor Param, 2: Critical Param/Vetoable, 3: Funding, 4: Emergency
        // --- Voting State ---
        votes_for: u128,
        votes_against: u128,
        veto_votes: u128, // Only applicable for proposal_type == 2
        // --- Quorum ---
        quorum_threshold_percentage: u8, // e.g., 10 for 10%, 30 for 30%
        total_stake_at_creation: u128, // Total stake when proposal was created, for quorum calculation
        // --- Timing ---
        start_time_ms: u64, // Timestamp (milliseconds) when voting begins
        end_time_ms: u64, // Timestamp (milliseconds) when voting ends
        voting_duration_ms: u64, // Store the duration used for time bonus calculation
        // --- Execution ---
        executed: bool,
        // --- Proposal Specific Data (Example for Funding) ---
        // These could be stored directly or parsed from description/metadata
        funding_amount: Option<u64>,
        funding_recipient: Option<address>,
        // Add fields for parameter changes if needed, or parse from description
        // param_name: Option<String>,
        // param_new_value: Option<vector<u8>>,
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
    const E_ARITHMETIC_OVERFLOW: u64 = 11;

    // === Events ===
    struct ProposalCreated has copy, drop {
        proposal_id: ID,
        creator: address,
        proposal_type: u8,
        quorum_percentage: u8,
        total_stake_at_creation: u128,
        end_time_ms: u64,
    }

    struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
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
    }


    // === Public Functions ===

    public entry fun submit_proposal(
        // --- Proposal Details ---
        description: vector<u8>,
        proposal_type: u8,
        // Optional fields based on type
        funding_amount: Option<u64>,
        funding_recipient: Option<address>,
        // --- Context & Dependencies ---
        system_state: &GovernanceSystemState, // To get total stake for quorum
        clock: &Clock, // To get current time
        ctx: &TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let current_time_ms = clock::timestamp_ms(clock);
        let voting_duration_ms = determine_voting_duration(proposal_type);
        let end_time_ms = current_time_ms + voting_duration_ms;

        let quorum_percentage = determine_quorum_percentage(proposal_type);
        let total_stake = delegation_staking::get_total_system_stake(system_state) as u128; // Fetch total stake

        let proposal_id = object::new(ctx); // Use the new object's UID/ID

        let new_proposal = Proposal {
            id: object::uid_to_inner(&proposal_id), // Get the actual ID
            creator,
            description: string::utf8(description),
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
            funding_amount,
            funding_recipient,
        };

        event::emit(ProposalCreated {
            proposal_id: object::uid_to_inner(&proposal_id),
            creator,
            proposal_type,
            quorum_percentage,
            total_stake_at_creation: total_stake,
            end_time_ms,
        });

        // Make the proposal a shared object so anyone can vote on it
        transfer::share_object(new_proposal);
    }

    public entry fun hybrid_vote(
        proposal: &mut Proposal, // Pass the shared Proposal object
        staked_sui_obj: &StakedSui, // The voter's StakedSui object (proves ownership and gives stake/rep)
        clock: &Clock, // To get current time for bonus and checks
        ctx: &TxContext
    ) {
        let voter_address = tx_context::sender(ctx);
        let current_time_ms = clock::timestamp_ms(clock);

        // --- Time Checks ---
        assert!(current_time_ms >= proposal.start_time_ms, E_VOTING_PERIOD_NOT_STARTED);
        assert!(current_time_ms < proposal.end_time_ms, E_VOTING_PERIOD_ALREADY_ENDED);

        // --- Fetch voter's stake and reputation ---
        // Stake amount comes directly from the StakedSui object passed in.
        // The amount used for voting is the full amount staked in that object.
        let stake_amount = delegation_staking::get_staked_sui_amount(staked_sui_obj) as u128;
        let reputation = delegation_staking::get_staked_sui_reputation(staked_sui_obj);
        // In Sui, passing &StakedSui implicitly checks ownership by the sender.

        assert!(stake_amount > 0, E_INSUFFICIENT_STAKE_FOR_VOTE);

        // --- Calculate Vote Weights ---
        // 1. Quadratic voting base
        let base_quadratic_votes = sqrt(stake_amount);

        // 2. Time-weighted bonus (linear decay)
        let elapsed_ms = current_time_ms - proposal.start_time_ms;
        let time_bonus = calculate_time_bonus(elapsed_ms, proposal.voting_duration_ms);

        // 3. Reputation weight factor
        let reputation_weight_factor = 100 + (reputation / 10); // Example scaling (100 = 100%, 110 = 110%)

        // --- Combine Weights ---
        // Add time bonus to base, then apply reputation multiplier
        let votes_with_bonus = base_quadratic_votes + time_bonus;
        let final_weighted_votes = (votes_with_bonus * reputation_weight_factor) / 100; // Need safe math here potentially

        // --- Determine Vote Direction (Example: based on sender address modulo 2 for simplicity) ---
        // In a real UI, the user would specify support/against/veto.
        // This needs to be passed as an argument. Let's add arguments:
        // support: bool, is_veto_vote: bool
        // For now, placeholder logic:
        let support = (voter_address.least_significant_byte() % 2) == 0; // Placeholder
        let is_veto_vote = false; // Placeholder - should be an argument

        // --- Apply Vote ---
        if is_veto_vote {
            assert!(proposal.proposal_type == 2, E_INVALID_PROPOSAL_TYPE_FOR_VETO);
            proposal.veto_votes = proposal.veto_votes + final_weighted_votes;
        } else if support {
            proposal.votes_for = proposal.votes_for + final_weighted_votes;
        } else {
            proposal.votes_against = proposal.votes_against + final_weighted_votes;
        }

        event::emit(VoteCast {
            proposal_id: proposal.id,
            voter: voter_address,
            stake_used: stake_amount,
            base_quadratic_votes,
            time_bonus,
            reputation_weight_factor,
            final_weighted_votes,
            support,
            is_veto: is_veto_vote,
        });

        // --- Discussion: Partial Refund ---
        // The monolithic example included a partial refund: `move_to(voting_address, voter.stake - votes + refund);`
        // Implementing this in Sui is complex and potentially undesirable:
        // 1. State Management: `StakedSui` objects represent *staked* tokens. Directly transferring
        //    part of this balance out as liquid SUI breaks the staking abstraction.
        // 2. Mechanism: A refund would likely involve minting a new `Coin<SUI>` from a designated
        //    refund pool or requiring the voter to claim their refund separately. It cannot be
        //    done by simply adjusting the `StakedSui` balance and using `move_to`.
        // 3. Incentive Alignment: Does refunding staked tokens align with the goal of encouraging
        //    long-term participation and commitment represented by staking? It might incentivize
        //    short-term voting over sustained staking.
        // Conclusion: Due to complexity and potential misalignment with Sui's model and staking
        // incentives, the partial refund mechanism is NOT implemented here. Alternative rewards
        // (like reputation boosts or periodic airdrops based on voting history) might be better.
    }

    public entry fun execute_proposal(
        proposal: &mut Proposal, // The shared Proposal object
        system_state: &GovernanceSystemState, // To get current total stake if needed for veto checks
        clock: &Clock, // To check end time
        // --- Capabilities & Objects needed for proposal_handler ---
        exec_cap: &proposal_handler::ProposalExecutionCap, // Capability to call handler
        treasury_chest: &mut treasury::TreasuryChest,
        treasury_access_cap: &treasury::TreasuryAccessCap,
        // Pass other necessary mutable objects like system_state if handler needs them
        ctx: &TxContext
    ) {
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        let current_time_ms = clock::timestamp_ms(clock);
        assert!(current_time_ms >= proposal.end_time_ms, E_VOTING_PERIOD_NOT_OVER);

        // --- Quorum Check ---
        let total_votes_cast = proposal.votes_for + proposal.votes_against;
        // Quorum is based on total stake *at proposal creation*
        let quorum_value = (proposal.total_stake_at_creation * (proposal.quorum_threshold_percentage as u128)) / 100;
        assert!(total_votes_cast >= quorum_value, E_QUORUM_NOT_MET);

        // --- Vote Threshold Check ---
        assert!(proposal.votes_for > proposal.votes_against, E_PROPOSAL_REJECTED);

        // --- Veto Check (if applicable) ---
        if (proposal.proposal_type == 2) {
            // Define veto_threshold, e.g., 10% of total stake at creation, or 33% of votes_for
            let veto_threshold = (proposal.total_stake_at_creation * 10) / 100; // Example: 10% of total stake
            assert!(proposal.veto_votes < veto_threshold, E_PROPOSAL_REJECTED); // Using same error code for simplicity
        }

        // --- Mark as Executed (Important: Do this *before* calling handler) ---
        // If handler fails, the state change here persists, preventing re-execution attempts.
        // This is safer than marking after the handler call.
        proposal.executed = true;

        // --- Call the Proposal Handler ---
        // The handler performs the actual actions based on proposal type and data.
        proposal_handler::handle_proposal_execution(
            exec_cap,
            proposal, // Pass proposal data (can be immutable borrow now)
            treasury_chest,
            treasury_access_cap,
            system_state, // Pass mutable system_state if handler needs to change params
            ctx
        ); // If handler aborts, the proposal remains marked executed, but actions didn't complete. Needs careful consideration.

        event::emit(ProposalExecuted { proposal_id: proposal.id });
    }

    // === Helper Functions ===

    // Determines the required quorum percentage based on proposal type.
    fun determine_quorum_percentage(proposal_type: u8): u8 {
        if (proposal_type == 0) { 10 } // General: 10%
        else if (proposal_type == 1) { 20 } // Minor Param: 20%
        else if (proposal_type == 2) { 33 } // Critical Param: 33%
        else if (proposal_type == 3) { 15 } // Funding: 15%
        else if (proposal_type == 4) { 40 } // Emergency: 40%
        else { abort(E_INVALID_PROPOSAL_TYPE) }
    }

    // Determines voting duration based on type
    fun determine_voting_duration(proposal_type: u8): u64 {
        if (proposal_type == 4) { // Emergency
            1 * 24 * 60 * 60 * 1000 // 1 day in ms
        } else {
            DEFAULT_VOTING_DURATION_MS // Default duration for others
        }
    }

    // Calculates time bonus (linear decay)
    // Returns bonus points (0 to MAX_TIME_BONUS)
    fun calculate_time_bonus(elapsed_ms: u64, total_duration_ms: u64): u128 {
        if (total_duration_ms == 0) { return 0 }; // Avoid division by zero

        // Calculate decay factor: (elapsed / total_duration) * MAX_TIME_BONUS
        // Use u128 for intermediate calculations to prevent overflow
        let elapsed_u128 = elapsed_ms as u128;
        let total_duration_u128 = total_duration_ms as u128;
        let max_bonus_u128 = MAX_TIME_BONUS;

        // Check for potential overflow before multiplication
        let numerator = elapsed_u128 * max_bonus_u128;

        let decay = numerator / total_duration_u128;

        // Bonus decreases over time: MAX_TIME_BONUS - decay
        if (max_bonus_u128 >= decay) {
            max_bonus_u128 - decay
        } else {
            0 // Bonus cannot be negative
        }
    }

    // Integer square root (Babylonian method - simplified)
    fun sqrt(x: u128): u128 {
        if (x == 0) { return 0 };
        let mut guess = x;
        let mut delta = 1; // Start with a large delta
        // Iterate until convergence or max iterations
        loop {
            let next_guess = (guess + x / guess) / 2;
            if (next_guess >= guess) { // Converged or oscillating
                // Check if guess+1 is better (needed for integer sqrt)
                if ((guess + 1) * (guess + 1) <= x) { return guess + 1 };
                return guess
            };
             // Optimization: check if delta is small enough
            if (guess - next_guess < delta) {
                // Check if guess+1 is better
                if ((next_guess + 1) * (next_guess + 1) <= x) { return next_guess + 1 };
                return next_guess;
            };
            guess = next_guess;
        };
        guess // Should be unreachable due to loop condition
    }
}
