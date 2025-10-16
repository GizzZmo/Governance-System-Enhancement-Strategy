// File: sources/governance_analytics.move
// Analytics and monitoring module for governance system
// Enhanced with EbA (Ecosystem-based Adaptation) governance metrics
module hybrid_governance_pkg::governance_analytics {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};

    // === Structs ===
    
    /// Analytics data for the governance system
    /// Enhanced with EbA governance quality metrics
    struct GovernanceAnalytics has key {
        id: UID,
        total_proposals_created: u64,
        total_votes_cast: u64,
        total_proposals_executed: u64,
        total_proposals_failed: u64,
        proposals_by_type: Table<u8, u64>, // proposal_type -> count
        voter_participation: Table<address, u64>, // address -> vote count
        proposal_success_rate: u64, // percentage * 100
        
        // EbA Governance Metrics
        unique_voters: u64, // Track distinct participants (inclusiveness)
        delegations_active: u64, // Track delegation usage (participation accessibility)
        stakeholder_diversity_score: u64, // Track diversity across stakeholder groups
        equity_score: u64, // Track vote distribution fairness (Gini-like metric)
        transparency_score: u64, // Track information accessibility
        last_participation_rate: u64, // Recent participation for adaptive quorum
    }

    /// Voter activity tracking with EbA metrics
    struct VoterActivity has store {
        total_votes: u64,
        proposals_created: u64,
        last_vote_timestamp: u64,
        reputation_score: u64,
        stakeholder_category: u8, // 0=token_holder, 1=contributor, 2=validator, 3=community, 4=partner
        is_delegate: bool, // Track if acting as delegate
    }

    /// Proposal metrics enhanced with equity tracking
    struct ProposalMetrics has copy, drop {
        proposal_type: u8,
        total_votes_for: u128,
        total_votes_against: u128,
        total_veto_votes: u128,
        participation_rate: u64, // percentage * 100
        execution_time_ms: u64,
        vote_concentration: u64, // Measure of vote distribution (0-100, 0=perfectly equal)
        stakeholder_diversity: u8, // Number of different stakeholder categories that voted
    }

    // EbA Governance Quality Assessment
    struct GovernanceQualityMetrics has copy, drop {
        inclusiveness_score: u64, // Based on participation breadth
        equity_score: u64, // Based on vote distribution fairness
        transparency_score: u64, // Based on information accessibility
        effectiveness_score: u64, // Based on execution success
        accountability_score: u64, // Based on role clarity and compliance
        overall_quality_score: u64, // Weighted average of above
    }

    // === Events ===
    
    struct AnalyticsUpdated has copy, drop {
        total_proposals: u64,
        total_votes: u64,
        success_rate: u64,
        participation_rate: u64,
        equity_score: u64,
    }

    struct VoterActivityRecorded has copy, drop {
        voter: address,
        total_votes: u64,
        reputation: u64,
        stakeholder_category: u8,
    }

    struct GovernanceQualityAssessed has copy, drop {
        timestamp: u64,
        inclusiveness: u64,
        equity: u64,
        transparency: u64,
        effectiveness: u64,
        overall_quality: u64,
    }

    // === Error Codes ===
    const E_NOT_INITIALIZED: u64 = 300;

    // Stakeholder category constants
    const STAKEHOLDER_TOKEN_HOLDER: u8 = 0;
    const STAKEHOLDER_CONTRIBUTOR: u8 = 1;
    const STAKEHOLDER_VALIDATOR: u8 = 2;
    const STAKEHOLDER_COMMUNITY: u8 = 3;
    const STAKEHOLDER_PARTNER: u8 = 4;

    // === Init Function ===
    
    /// Initialize the analytics module with EbA metrics
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
            
            // Initialize EbA metrics
            unique_voters: 0,
            delegations_active: 0,
            stakeholder_diversity_score: 0,
            equity_score: 10000, // Start at perfect equity (100.00%)
            transparency_score: 10000, // Start at full transparency
            last_participation_rate: 0,
        };
        
        transfer::share_object(analytics);
    }

    // === Public Functions ===

    /// Record a new proposal creation with stakeholder tracking
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
            analytics.unique_voters = analytics.unique_voters + 1; // New unique participant
        };
    }

    /// Record a vote cast with equity tracking
    public fun record_vote_cast(
        analytics: &mut GovernanceAnalytics,
        voter: address,
        _timestamp: u64
    ) {
        analytics.total_votes_cast = analytics.total_votes_cast + 1;

        // Update voter participation and track unique voters
        if (table::contains(&analytics.voter_participation, voter)) {
            let count = table::borrow_mut(&mut analytics.voter_participation, voter);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.voter_participation, voter, 1);
            analytics.unique_voters = analytics.unique_voters + 1;
        };

        event::emit(VoterActivityRecorded {
            voter,
            total_votes: *table::borrow(&analytics.voter_participation, voter),
            reputation: 100, // Simplified - would calculate based on activity
            stakeholder_category: STAKEHOLDER_TOKEN_HOLDER, // Default, would be determined
        });
    }

    /// Record delegation activity (EbA: participation accessibility)
    public fun record_delegation(
        analytics: &mut GovernanceAnalytics,
        _delegator: address,
        _delegatee: address
    ) {
        analytics.delegations_active = analytics.delegations_active + 1;
        // Delegation increases accessibility, improving inclusiveness score
    }

    /// Record delegation removal
    public fun record_delegation_removed(
        analytics: &mut GovernanceAnalytics,
        _delegator: address
    ) {
        if (analytics.delegations_active > 0) {
            analytics.delegations_active = analytics.delegations_active - 1;
        };
    }

    /// Calculate and update equity score based on vote distribution
    /// Lower score = more concentrated voting power (less equitable)
    public fun update_equity_score(
        analytics: &mut GovernanceAnalytics,
        vote_concentration: u64 // 0-10000, where 10000 = one voter has all power
    ) {
        // Invert concentration to get equity (10000 - concentration)
        analytics.equity_score = 10000 - vote_concentration;
    }

    /// Calculate participation rate for adaptive quorum
    public fun calculate_participation_rate(
        analytics: &mut GovernanceAnalytics,
        votes_cast: u64,
        eligible_voters: u64
    ): u64 {
        if (eligible_voters == 0) {
            return 0
        };
        
        let rate = (votes_cast * 10000) / eligible_voters;
        analytics.last_participation_rate = rate;
        rate
    }

    /// Assess overall governance quality using EbA framework
    public fun assess_governance_quality(
        analytics: &GovernanceAnalytics,
        total_eligible_voters: u64,
        timestamp: u64
    ): GovernanceQualityMetrics {
        // 1. Inclusiveness: Based on participation breadth
        let inclusiveness = if (total_eligible_voters > 0) {
            (analytics.unique_voters * 10000) / total_eligible_voters
        } else {
            0
        };

        // 2. Equity: Based on vote distribution (already tracked)
        let equity = analytics.equity_score;

        // 3. Transparency: Based on documentation and event coverage (100% in smart contract)
        let transparency = analytics.transparency_score;

        // 4. Effectiveness: Based on execution success rate
        let effectiveness = analytics.proposal_success_rate;

        // 5. Accountability: Based on role compliance (tracked separately, default high)
        let accountability = 9000; // 90% - would be calculated from role compliance

        // Overall quality: weighted average
        // Inclusiveness: 25%, Equity: 25%, Transparency: 20%, Effectiveness: 20%, Accountability: 10%
        let overall_quality = (inclusiveness * 25 + equity * 25 + transparency * 20 + 
                              effectiveness * 20 + accountability * 10) / 100;

        let metrics = GovernanceQualityMetrics {
            inclusiveness_score: inclusiveness,
            equity_score: equity,
            transparency_score: transparency,
            effectiveness_score: effectiveness,
            accountability_score: accountability,
            overall_quality_score: overall_quality,
        };

        event::emit(GovernanceQualityAssessed {
            timestamp,
            inclusiveness,
            equity,
            transparency,
            effectiveness,
            overall_quality,
        });

        metrics
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

    /// Get unique voters count (inclusiveness metric)
    public fun get_unique_voters(analytics: &GovernanceAnalytics): u64 {
        analytics.unique_voters
    }

    /// Get active delegations count (accessibility metric)
    public fun get_active_delegations(analytics: &GovernanceAnalytics): u64 {
        analytics.delegations_active
    }

    /// Get equity score
    public fun get_equity_score(analytics: &GovernanceAnalytics): u64 {
        analytics.equity_score
    }

    /// Get last participation rate (for adaptive quorum)
    public fun get_last_participation_rate(analytics: &GovernanceAnalytics): u64 {
        analytics.last_participation_rate
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

    /// Update the success rate calculation with enhanced metrics
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
            participation_rate: analytics.last_participation_rate,
            equity_score: analytics.equity_score,
        });
    }
}
