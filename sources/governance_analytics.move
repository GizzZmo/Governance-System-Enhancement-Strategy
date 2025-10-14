// File: sources/governance_analytics.move
// Analytics and monitoring module for governance system
module hybrid_governance_pkg::governance_analytics {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};

    // === Structs ===
    
    /// Analytics data for the governance system
    struct GovernanceAnalytics has key {
        id: UID,
        total_proposals_created: u64,
        total_votes_cast: u64,
        total_proposals_executed: u64,
        total_proposals_failed: u64,
        proposals_by_type: Table<u8, u64>, // proposal_type -> count
        voter_participation: Table<address, u64>, // address -> vote count
        proposal_success_rate: u64, // percentage * 100
    }

    /// Voter activity tracking
    struct VoterActivity has store {
        total_votes: u64,
        proposals_created: u64,
        last_vote_timestamp: u64,
        reputation_score: u64,
    }

    /// Proposal metrics
    struct ProposalMetrics has copy, drop {
        proposal_type: u8,
        total_votes_for: u128,
        total_votes_against: u128,
        total_veto_votes: u128,
        participation_rate: u64, // percentage * 100
        execution_time_ms: u64,
    }

    // === Events ===
    
    struct AnalyticsUpdated has copy, drop {
        total_proposals: u64,
        total_votes: u64,
        success_rate: u64,
    }

    struct VoterActivityRecorded has copy, drop {
        voter: address,
        total_votes: u64,
        reputation: u64,
    }

    // === Error Codes ===
    const E_NOT_INITIALIZED: u64 = 300;

    // === Init Function ===
    
    /// Initialize the analytics module
    fun init(ctx: &mut TxContext) {
        let analytics = GovernanceAnalytics {
            id: object::new(ctx),
            total_proposals_created: 0,
            total_votes_cast: 0,
            total_proposals_executed: 0,
            total_proposals_failed: 0,
            proposals_by_type: table::new(ctx),
            voter_participation: table::new(ctx),
            proposal_success_rate: 0,
        };
        
        transfer::share_object(analytics);
    }

    // === Public Functions ===

    /// Record a new proposal creation
    public fun record_proposal_created(
        analytics: &mut GovernanceAnalytics,
        proposal_type: u8,
        creator: address
    ) {
        analytics.total_proposals_created = analytics.total_proposals_created + 1;
        
        // Update proposals by type
        if (table::contains(&analytics.proposals_by_type, proposal_type)) {
            let count = table::borrow_mut(&mut analytics.proposals_by_type, proposal_type);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.proposals_by_type, proposal_type, 1);
        };

        // Update creator participation
        if (table::contains(&analytics.voter_participation, creator)) {
            let count = table::borrow_mut(&mut analytics.voter_participation, creator);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.voter_participation, creator, 1);
        };
    }

    /// Record a vote cast
    public fun record_vote_cast(
        analytics: &mut GovernanceAnalytics,
        voter: address,
        timestamp: u64
    ) {
        analytics.total_votes_cast = analytics.total_votes_cast + 1;

        // Update voter participation
        if (table::contains(&analytics.voter_participation, voter)) {
            let count = table::borrow_mut(&mut analytics.voter_participation, voter);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.voter_participation, voter, 1);
        };

        event::emit(VoterActivityRecorded {
            voter,
            total_votes: *table::borrow(&analytics.voter_participation, voter),
            reputation: 100, // Simplified - would calculate based on activity
        });
    }

    /// Record proposal execution
    public fun record_proposal_executed(
        analytics: &mut GovernanceAnalytics,
        _proposal_id: address
    ) {
        analytics.total_proposals_executed = analytics.total_proposals_executed + 1;
        update_success_rate(analytics);
    }

    /// Record proposal failure
    public fun record_proposal_failed(
        analytics: &mut GovernanceAnalytics,
        _proposal_id: address
    ) {
        analytics.total_proposals_failed = analytics.total_proposals_failed + 1;
        update_success_rate(analytics);
    }

    /// Get total proposals created
    public fun get_total_proposals(analytics: &GovernanceAnalytics): u64 {
        analytics.total_proposals_created
    }

    /// Get total votes cast
    public fun get_total_votes(analytics: &GovernanceAnalytics): u64 {
        analytics.total_votes_cast
    }

    /// Get success rate
    public fun get_success_rate(analytics: &GovernanceAnalytics): u64 {
        analytics.proposal_success_rate
    }

    /// Get voter participation count
    public fun get_voter_participation(analytics: &GovernanceAnalytics, voter: address): u64 {
        if (table::contains(&analytics.voter_participation, voter)) {
            *table::borrow(&analytics.voter_participation, voter)
        } else {
            0
        }
    }

    /// Get proposals by type count
    public fun get_proposals_by_type(analytics: &GovernanceAnalytics, proposal_type: u8): u64 {
        if (table::contains(&analytics.proposals_by_type, proposal_type)) {
            *table::borrow(&analytics.proposals_by_type, proposal_type)
        } else {
            0
        }
    }

    // === Internal Functions ===

    /// Update the success rate calculation
    fun update_success_rate(analytics: &mut GovernanceAnalytics) {
        let total_completed = analytics.total_proposals_executed + analytics.total_proposals_failed;
        
        if (total_completed > 0) {
            // Success rate as percentage * 100
            analytics.proposal_success_rate = (analytics.total_proposals_executed * 10000) / total_completed;
        };

        event::emit(AnalyticsUpdated {
            total_proposals: analytics.total_proposals_created,
            total_votes: analytics.total_votes_cast,
            success_rate: analytics.proposal_success_rate,
        });
    }
}
