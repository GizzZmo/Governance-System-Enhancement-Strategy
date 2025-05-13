// File: sources/governance.move
// Manages proposal submission, voting, and basic execution checks.
// Updated intra-package imports to use 'crate::'.
module hybrid_governance_pkg::governance { // Package name remains for module declaration
    use std::string::{Self, String};
    use std::option::{Self, Option, some, none, is_some, destroy_some};
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID, new, uid_to_inner};
    use sui::tx_context::{Self, TxContext, sender};
    use sui::transfer;
    use sui::event;

    // Use 'crate::' for importing modules from the same package
    use crate::delegation_staking::{Self, StakedSui, GovernanceSystemState, AdminCap as StakingAdminCap};
    use crate::treasury::{Self, TreasuryChest, TreasuryAccessCap, TreasuryAdminCap};
    use crate::proposal_handler; // Import the module itself for its types like ProposalExecutionCap

    // === Constants ===
    const MAX_TIME_BONUS: u128 = 5;
    const DEFAULT_VOTING_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000;

    // === Structs ===
    struct Proposal has key, store {
        id: ID,
        creator: address,
        description: String,
        proposal_type: u8,
        votes_for: u128,
        votes_against: u128,
        veto_votes: u128,
        quorum_threshold_percentage: u8,
        total_stake_at_creation: u128,
        start_time_ms: u64,
        end_time_ms: u64,
        voting_duration_ms: u64,
        executed: bool,
        funding_amount: Option<u64>,
        funding_recipient: Option<address>,
        param_target_module: Option<String>,
        param_name: Option<String>,
        param_new_value_bcs: Option<vector<u8>>,
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
    const E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE: u64 = 12;

    // === Events ===
    struct ProposalCreated has copy, drop {
        proposal_id: ID,
        creator: address,
        proposal_type: u8,
        description: String,
        quorum_percentage: u8,
        total_stake_at_creation: u128,
        end_time_ms: u64,
    }

    struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
        staked_sui_object_id: ID,
        stake_used: u128,
        base_quadratic_votes: u128,
        time_bonus: u128,
        reputation_weight_factor: u128,
        final_weighted_votes: u128,
        support: bool,
        is_veto: bool,
    }

    struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        executed_by: address,
    }

    // === Public Entry Functions ===
    public entry fun submit_proposal(
        description_vec: vector<u8>,
        proposal_type: u8,
        funding_amount_opt: Option<u64>,
        funding_recipient_opt: Option<address>,
        param_target_module_opt: Option<vector<u8>>,
        param_name_opt: Option<vector<u8>>,
        param_new_value_bcs_opt: Option<vector<u8>>,
        system_state: &GovernanceSystemState, // From crate::delegation_staking
        clock: &Clock,
        ctx: &TxContext
    ) {
        let creator_addr = sender(ctx);
        let current_time_ms = clock::timestamp_ms(clock);
        let voting_duration_ms = determine_voting_duration(proposal_type);
        let end_time_ms = current_time_ms + voting_duration_ms;

        let quorum_percentage = determine_quorum_percentage(proposal_type);
        // Call using the imported module name directly or with 'crate::'
        let total_stake = delegation_staking::get_total_system_stake(system_state) as u128;

        if (proposal_type == 3) {
            assert!(is_some(&funding_amount_opt) && is_some(&funding_recipient_opt), E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE);
        } else if (proposal_type == 1 || proposal_type == 2) {
            assert!(is_some(&param_target_module_opt) && is_some(&param_name_opt) && is_some(&param_new_value_bcs_opt), E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE);
        };

        let proposal_obj_uid = new(ctx);
        let proposal_id_val = uid_to_inner(&proposal_obj_uid);
        let proposal_description = string::utf8(description_vec);

        let new_proposal = Proposal {
            id: proposal_id_val,
            creator: creator_addr,
            description: proposal_description,
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
            param_target_module: if (is_some(&param_target_module_opt)) { some(string::utf8(destroy_some(param_target_module_opt))) } else { none() },
            param_name: if (is_some(&param_name_opt)) { some(string::utf8(destroy_some(param_name_opt))) } else { none() },
            param_new_value_bcs: param_new_value_bcs_opt,
        };

        event::emit(ProposalCreated {
            proposal_id: proposal_id_val,
            creator: creator_addr,
            proposal_type,
            description: new_proposal.description,
            quorum_percentage,
            total_stake_at_creation: total_stake,
            end_time_ms,
        });
        transfer::share_object(new_proposal);
    }

    public entry fun hybrid_vote(
        proposal: &mut Proposal,
        staked_sui_obj: &StakedSui, // From crate::delegation_staking
        support_vote: bool,
        is_veto_flag: bool,
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
        let reputation_weight_factor = 100 + (reputation / 10);
        let votes_with_bonus = base_quadratic_votes + time_bonus;
        let final_weighted_votes = (votes_with_bonus * reputation_weight_factor) / 100;

        if (is_veto_flag) {
            assert!(proposal.proposal_type == 2, E_INVALID_PROPOSAL_TYPE_FOR_VETO);
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

    public entry fun execute_proposal(
        proposal: &mut Proposal,
        system_state: &mut GovernanceSystemState, // From crate::delegation_staking
        clock: &Clock,
        exec_cap: &proposal_handler::ProposalExecutionCap, // From crate::proposal_handler
        treasury_chest: &mut TreasuryChest, // From crate::treasury
        treasury_access_cap: &TreasuryAccessCap, // From crate::treasury
        treasury_admin_cap: &TreasuryAdminCap,   // From crate::treasury
        staking_admin_cap: &StakingAdminCap,     // From crate::delegation_staking
        ctx: &TxContext
    ) {
        assert!(!proposal.executed, E_PROPOSAL_ALREADY_EXECUTED);
        let current_time_ms = clock::timestamp_ms(clock);
        assert!(current_time_ms >= proposal.end_time_ms, E_VOTING_PERIOD_NOT_OVER);

        let total_votes_cast = proposal.votes_for + proposal.votes_against;
        let quorum_value = (proposal.total_stake_at_creation * (proposal.quorum_threshold_percentage as u128)) / 100;
        assert!(total_votes_cast >= quorum_value, E_QUORUM_NOT_MET);
        assert!(proposal.votes_for > proposal.votes_against, E_PROPOSAL_REJECTED);

        if (proposal.proposal_type == 2) {
            let veto_threshold = (proposal.total_stake_at_creation * 10) / 100;
            assert!(proposal.veto_votes < veto_threshold, E_PROPOSAL_REJECTED);
        }
        proposal.executed = true;

        proposal_handler::handle_proposal_execution(
            exec_cap,
            proposal,
            treasury_chest,
            staking_system_state,
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

    fun determine_quorum_percentage(proposal_type: u8): u8 {
        if (proposal_type == 0) { 10 }
        else if (proposal_type == 1) { 20 }
        else if (proposal_type == 2) { 33 }
        else if (proposal_type == 3) { 15 }
        else if (proposal_type == 4) { 40 }
        else { abort(E_INVALID_PROPOSAL_TYPE) }
    }

    fun determine_voting_duration(proposal_type: u8): u64 {
        if (proposal_type == 4) { 1 * 24 * 60 * 60 * 1000 }
        else { DEFAULT_VOTING_DURATION_MS }
    }

    fun calculate_time_bonus(elapsed_ms: u64, total_duration_ms: u64): u128 {
        if (total_duration_ms == 0) { return 0 };
        let elapsed_u128 = elapsed_ms as u128;
        let total_duration_u128 = total_duration_ms as u128;
        let max_bonus_u128 = MAX_TIME_BONUS;
        if (elapsed_u128 >= total_duration_u128) { return 0 };
        let decay_numerator = elapsed_u128 * max_bonus_u128;
        let decay = decay_numerator / total_duration_u128;
        if (max_bonus_u128 >= decay) { max_bonus_u128 - decay } else { 0 }
    }

    fun sqrt(x: u128): u128 {
        if (x == 0) { return 0 };
        let mut guess = x;
        let mut prev_guess = 0;
        loop {
            if (guess == 0) { return 0 };
            prev_guess = guess;
            guess = (guess + x / guess) / 2;
            if (guess >= prev_guess) {
                if (prev_guess * prev_guess <= x) { return prev_guess } else { return guess };
            };
        };
    }
}
