// File: sources/governance.move
// Manages proposal submission, voting, and basic execution checks.
// This is based on the structure you provided, adapted for the Sui module system.

// Placeholder for the actual package name, will be defined in Move.toml
module hybrid_governance::governance {
    use std::signer;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;

    // Assuming these will be imported from other modules or defined globally
    // For example, total_stake would come from delegation_staking module
    // use hybrid_governance::delegation_staking::{Self, StakedTokens, Validator, TotalSystemStake};

    // === Structs ===

    /// Represents a governance proposal.
    struct Proposal has key, store {
        id: u64, // Unique ID for the proposal
        // In Sui, objects have their own ID. We might use that or an internal counter.
        // For simplicity, using an internal counter for now.
        creator: address,
        description: String,
        proposal_type: u8, // 0: General, 1: Minor Param, 2: Critical Param/Vetoable, 3: Funding, 4: Emergency
        votes_for: u128,
        votes_against: u128,
        veto_votes: u128, // Only applicable for proposal_type == 2
        quorum_threshold_percentage: u8, // e.g., 10 for 10%, 30 for 30%
        // quorum_calculated: u128, // Actual quorum value based on total_stake at proposal creation
        // start_time: u64, // Timestamp for when voting begins
        // end_time: u64, // Timestamp for when voting ends
        executed: bool,
        // parent_id: Option<u64>, // For proposal versioning
        // version: u64, // For proposal versioning
        // funding_amount: Option<u128>,
        // recipient: Option<address>,
    }

    // This Voter struct is a conceptual representation of data needed for voting.
    // In practice, this data (stake, delegate, reputation) will be fetched from
    // the delegation_staking module based on the voter's address.
    // It won't be stored directly in this module like this.
    struct VoterInfo { // Renamed to VoterInfo to avoid conflict if Voter is a type elsewhere
        address: address,
        stake_amount: u128, // Actual stake amount used for this vote
        delegated_from: Option<address>, // If these votes are from a delegate
        reputation_score: u128,
    }

    // === Errors ===
    const E_INSUFFICIENT_STAKE_FOR_VOTE: u64 = 1;
    const E_QUORUM_NOT_MET: u64 = 2;
    const E_PROPOSAL_REJECTED: u64 = 3;
    const E_PROPOSAL_ALREADY_EXECUTED: u64 = 4;
    const E_INVALID_PROPOSAL_TYPE_FOR_VETO: u64 = 5;
    const E_VOTING_PERIOD_NOT_OVER: u64 = 6; // Placeholder
    const E_INVALID_PROPOSAL_TYPE: u64 = 7;

    // === Global State (Conceptual - In Sui, these would be shared objects) ===
    // For managing proposal IDs
    // struct ProposalCounter has key { id: UID, count: u64 }
    // For total_stake, this would be a reference to an object from delegation_staking
    // let total_stake_ref: &TotalSystemStake;


    // === Public Functions ===

    // In Sui, entry functions require TxContext
    // fun init(ctx: &mut TxContext) {
    //     transfer::share_object(ProposalCounter { id: object::new(ctx), count: 0 });
    // }

    public entry fun submit_proposal(
        // proposal_counter: &mut ProposalCounter, // Pass as mutable reference if using a counter object
        creator_addr: address, // Inferred from signer in entry functions
        description: vector<u8>, // Sui uses vector<u8> for strings often
        proposal_type: u8,
        // quorum_percentage: u8, // Could be set here or determined by type
        // total_system_stake: u128, // Passed in at proposal creation from delegation_staking
        ctx: &mut sui::tx_context::TxContext
    ) { // : u64 { // Returning proposal ID
        let creator = sui::tx_context::sender(ctx);
        // let proposal_id = proposal_counter.count;
        // proposal_counter.count = proposal_counter.count + 1;

        let quorum_percentage = determine_quorum_percentage(proposal_type);
        // let calculated_quorum = (total_system_stake * (quorum_percentage as u128)) / 100;

        let new_proposal = Proposal {
            id: 0, // Placeholder - In Sui, the object ID itself is the unique ID.
                   // Or use a shared counter object.
            creator,
            description: string::utf8(description),
            proposal_type,
            votes_for: 0,
            votes_against: 0,
            veto_votes: 0,
            quorum_threshold_percentage,
            // quorum_calculated,
            executed: false,
        };
        // Transfer the new proposal object to the creator or make it a shared object
        sui::transfer::transfer(new_proposal, creator); // Example: creator owns the proposal object
        // return proposal_id;
    }

    // The `voter_info` would be constructed by fetching data from `delegation_staking` module
    // `proposal` would be a mutable reference to a Proposal object.
    public entry fun hybrid_vote(
        proposal: &mut Proposal, // Pass the Proposal object by mutable reference
        // voter_stake_obj: &StakedTokens, // From delegation_staking, to get stake and reputation
        // delegation_staking_total_stake: &TotalSystemStake, // To calculate quorum dynamically or verify
        votes_to_commit: u128, // Amount of their stake they are committing to this vote
        support: bool,
        is_veto_vote: bool,
        ctx: &mut sui::tx_context::TxContext
    ) {
        let voter_address = sui::tx_context::sender(ctx);

        // --- Fetch voter's actual stake and reputation ---
        // This is conceptual: you'd call functions in delegation_staking module
        // let actual_stake = delegation_staking::get_user_stake_for_voting(voter_address, ...);
        // let reputation = delegation_staking::get_user_reputation(voter_address, ...);
        let actual_stake = 10000; // Placeholder
        let reputation = 120;    // Placeholder

        assert!(actual_stake >= votes_to_commit, E_INSUFFICIENT_STAKE_FOR_VOTE);

        // Quadratic voting part
        let effective_votes = sqrt(votes_to_commit); // Using your sqrt function

        // Reputation weight: e.g., 100 base + (reputation / 100) as percentage modifier
        // Ensure no division by zero if reputation can be 0.
        // Example: reputation of 500 -> 100 + 5 = 105% weight.
        // reputation of 100 -> 100 + 1 = 101% weight.
        // For simplicity, let's assume reputation is scaled appropriately.
        let reputation_weight_factor = 100 + (reputation / 10); // Example scaling
        let final_weighted_votes = (effective_votes * reputation_weight_factor) / 100;

        // In Sui, you'd check if the voter is a delegate for someone else if that's part of the logic.
        // let voting_address = voter_info.delegated_from.unwrap_or(voter_info.address);

        if is_veto_vote {
            assert!(proposal.proposal_type == 2, E_INVALID_PROPOSAL_TYPE_FOR_VETO); // Assuming type 2 is vetoable
            proposal.veto_votes = proposal.veto_votes + final_weighted_votes;
        } else if support {
            proposal.votes_for = proposal.votes_for + final_weighted_votes;
        } else {
            proposal.votes_against = proposal.votes_against + final_weighted_votes;
        }
        // Event: VoteCast { proposal_id: proposal.id, voter: voter_address, weighted_votes: final_weighted_votes, support, is_veto }
    }

    public entry fun execute_proposal(
        proposal: &mut Proposal,
        total_system_stake_at_execution: u128 // Fetched from delegation_staking
        // proposal_handler_cap: &ProposalHandlerCapability // Capability to call proposal_handler
    ) {
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        // assert!(current_time >= proposal.end_time, E_VOTING_PERIOD_NOT_OVER);

        let total_votes_cast = proposal.votes_for + proposal.votes_against;
        let quorum_value = (total_system_stake_at_execution * (proposal.quorum_threshold_percentage as u128)) / 100;

        assert!(total_votes_cast >= quorum_value, E_QUORUM_NOT_MET);
        assert!(proposal.votes_for > proposal.votes_against, E_PROPOSAL_REJECTED);

        // If vetoable, check veto votes (e.g., if veto_votes > threshold_for_veto, proposal fails)
        if (proposal.proposal_type == 2) {
            // Define veto_threshold, e.g., 33% of votes_for or a fixed part of total_stake
            // let veto_power_threshold = proposal.votes_for / 3; // Example
            // assert!(proposal.veto_votes < veto_power_threshold, E_PROPOSAL_VETOED);
        }

        proposal.executed = true;

        // Call the proposal_handler module to perform specific actions
        // proposal_handler::handle_execution(proposal_handler_cap, proposal.proposal_type, ...);

        // Event: ProposalExecuted { proposal_id: proposal.id }
    }

    // Determines the required quorum percentage based on proposal type.
    fun determine_quorum_percentage(proposal_type: u8): u8 {
        // These are percentages of total staked tokens.
        if (proposal_type == 0) { // General
            10 // 10%
        } else if (proposal_type == 1) { // Minor Parameter Change
            20 // 20%
        } else if (proposal_type == 2) { // Critical Parameter Change (Vetoable)
            33 // 33%
        } else if (proposal_type == 3) { // Funding Request
            15 // 15%
        } else if (proposal_type == 4) { // Emergency
            40 // 40% (but shorter duration, handled by proposal timing)
        } else {
            abort(E_INVALID_PROPOSAL_TYPE)
        }
    }

    // Integer square root (Babylonian method)
    fun sqrt(x: u128): u128 {
        if (x == 0) { return 0 };
        let mut guess = x / 2 + 1; // Initial guess, ensure it's not 0 if x/2 is 0.
        let mut prev_guess = 0;
        // Iterate until guess converges
        while (guess != prev_guess) {
            prev_guess = guess;
            guess = (guess + x / guess) / 2;
            // Break if guess increases, which can happen with integer division if x/guess is 0
            if (guess > prev_guess && prev_guess != 0) { // check prev_guess to avoid loop on first iteration if x=1,2,3
                guess = prev_guess; // stick to previous if it increased
                break
            };
        };
        // Check if (guess+1)^2 is closer, for integer sqrt this is sometimes needed.
        // For simplicity, current guess is usually sufficient for weighted voting.
        guess
    }
}

