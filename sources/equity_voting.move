// File: sources/equity_voting.move
// Equity-based voting calculation module implementing quadratic voting with reputation
// Implements EbA (Ecosystem-based Adaptation) principle of equitable governance
//
// This module ensures fair power distribution by combining quadratic voting
// (which reduces the influence of large stake holders) with reputation-based
// weighting (which rewards active, constructive participation).

module hybrid_governance_pkg::equity_voting {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;
    use sui::math;

    // === Error Codes ===
    
    /// Stake amount is zero
    const E_ZERO_STAKE: u64 = 1;
    
    /// Invalid reputation score
    const E_INVALID_REPUTATION: u64 = 2;
    
    /// Invalid vote weight calculated
    const E_INVALID_VOTE_WEIGHT: u64 = 3;

    // === Constants ===
    
    /// Maximum reputation score
    const MAX_REPUTATION: u64 = 10000;
    
    /// Base reputation factor (100 = 1.0x multiplier)
    const BASE_REPUTATION_FACTOR: u64 = 100;
    
    /// Maximum reputation bonus (200 = 2.0x multiplier)
    const MAX_REPUTATION_BONUS: u64 = 200;
    
    /// Reputation divisor for calculating weight factor
    const REPUTATION_DIVISOR: u64 = 10;

    // === Structs ===

    /// Equity metrics tracking for governance quality
    struct EquityMetrics has key {
        id: UID,
        /// Gini coefficient tracking (0-10000, where 10000 = perfect inequality)
        gini_coefficient: u64,
        /// Vote distribution by stake size (small, medium, large holders)
        vote_distribution: Table<u8, u64>, // category -> total votes
        /// Total votes cast across all categories
        total_votes_cast: u128,
        /// Number of unique voters
        unique_voters: u64,
    }

    /// Voter reputation tracking
    struct VoterReputation has key {
        id: UID,
        /// Reputation scores by voter address
        reputation_scores: Table<address, u64>,
        /// Participation count by voter
        participation_count: Table<address, u64>,
        /// Last activity timestamp by voter
        last_activity: Table<address, u64>,
    }

    /// Event emitted when vote weight is calculated
    struct VoteWeightCalculated has copy, drop {
        voter: address,
        stake_amount: u64,
        reputation_score: u64,
        quadratic_votes: u64,
        reputation_factor: u64,
        final_weighted_votes: u64,
    }

    /// Event emitted when equity metrics are updated
    struct EquityMetricsUpdated has copy, drop {
        gini_coefficient: u64,
        total_votes_cast: u128,
        unique_voters: u64,
    }

    // === Init Function ===

    /// Initialize the equity voting system
    fun init(ctx: &mut TxContext) {
        let metrics = EquityMetrics {
            id: object::new(ctx),
            gini_coefficient: 0,
            vote_distribution: table::new(ctx),
            total_votes_cast: 0,
            unique_voters: 0,
        };
        
        let reputation = VoterReputation {
            id: object::new(ctx),
            reputation_scores: table::new(ctx),
            participation_count: table::new(ctx),
            last_activity: table::new(ctx),
        };
        
        transfer::share_object(metrics);
        transfer::share_object(reputation);
    }

    // === Public Functions ===

    /// Calculate equitable vote weight using quadratic voting and reputation
    /// 
    /// This implements the core equity formula:
    /// 1. Base quadratic votes = √(stake_amount)
    /// 2. Reputation weight factor = 100 + (reputation / 10)
    /// 3. Final weighted votes = (base_quadratic_votes * reputation_weight_factor) / 100
    /// 
    /// # Arguments
    /// * `stake_amount` - Amount of tokens staked by the voter
    /// * `reputation` - Voter's reputation score (0-10000)
    /// * `voter` - Address of the voter
    /// * `ctx` - Transaction context
    /// 
    /// # Returns
    /// * `u64` - Final weighted vote count
    /// 
    /// # Example
    /// - Stake: 10,000 tokens → Quadratic votes: 100
    /// - Reputation: 500 → Weight factor: 150 (1.5x)
    /// - Final votes: (100 * 150) / 100 = 150
    public fun calculate_equitable_vote_weight(
        stake_amount: u64,
        reputation: u64,
        voter: address,
        ctx: &mut TxContext
    ): u64 {
        // Validate inputs
        assert!(stake_amount > 0, E_ZERO_STAKE);
        assert!(reputation <= MAX_REPUTATION, E_INVALID_REPUTATION);
        
        // Step 1: Calculate quadratic votes from stake
        // Using integer square root approximation
        let base_quadratic_votes = integer_sqrt(stake_amount);
        
        // Step 2: Calculate reputation weight factor
        // Formula: 100 + (reputation / 10)
        // This gives 1.0x to 2.0x multiplier based on reputation
        let reputation_weight_factor = BASE_REPUTATION_FACTOR + (reputation / REPUTATION_DIVISOR);
        
        // Cap reputation factor at maximum
        let reputation_weight_factor = if (reputation_weight_factor > MAX_REPUTATION_BONUS) {
            MAX_REPUTATION_BONUS
        } else {
            reputation_weight_factor
        };
        
        // Step 3: Calculate final weighted votes
        let final_weighted_votes = (base_quadratic_votes * reputation_weight_factor) / 100;
        
        // Ensure result is valid
        assert!(final_weighted_votes > 0, E_INVALID_VOTE_WEIGHT);
        
        // Emit event for transparency
        event::emit(VoteWeightCalculated {
            voter,
            stake_amount,
            reputation_score: reputation,
            quadratic_votes: base_quadratic_votes,
            reputation_factor: reputation_weight_factor,
            final_weighted_votes,
        });
        
        final_weighted_votes
    }

    /// Update voter reputation based on participation quality
    /// 
    /// Reputation increases with:
    /// - Consistent participation
    /// - Quality proposals
    /// - Constructive voting
    /// - Time commitment
    /// 
    /// # Arguments
    /// * `reputation_state` - The voter reputation object
    /// * `voter` - Address of the voter
    /// * `reputation_delta` - Change in reputation (can be negative for penalties)
    /// * `timestamp` - Current timestamp
    public fun update_reputation(
        reputation_state: &mut VoterReputation,
        voter: address,
        reputation_delta: u64,
        is_increase: bool,
        timestamp: u64,
    ) {
        // Get current reputation (default to 0 if new voter)
        let current_reputation = if (table::contains(&reputation_state.reputation_scores, voter)) {
            *table::borrow(&reputation_state.reputation_scores, voter)
        } else {
            0
        };
        
        // Calculate new reputation
        let new_reputation = if (is_increase) {
            let proposed_new = current_reputation + reputation_delta;
            if (proposed_new > MAX_REPUTATION) {
                MAX_REPUTATION
            } else {
                proposed_new
            }
        } else {
            if (current_reputation > reputation_delta) {
                current_reputation - reputation_delta
            } else {
                0
            }
        };
        
        // Update reputation score
        if (table::contains(&reputation_state.reputation_scores, voter)) {
            *table::borrow_mut(&mut reputation_state.reputation_scores, voter) = new_reputation;
        } else {
            table::add(&mut reputation_state.reputation_scores, voter, new_reputation);
        };
        
        // Update participation count
        let participation = if (table::contains(&reputation_state.participation_count, voter)) {
            *table::borrow(&reputation_state.participation_count, voter) + 1
        } else {
            1
        };
        
        if (table::contains(&reputation_state.participation_count, voter)) {
            *table::borrow_mut(&mut reputation_state.participation_count, voter) = participation;
        } else {
            table::add(&mut reputation_state.participation_count, voter, participation);
        };
        
        // Update last activity
        if (table::contains(&reputation_state.last_activity, voter)) {
            *table::borrow_mut(&mut reputation_state.last_activity, voter) = timestamp;
        } else {
            table::add(&mut reputation_state.last_activity, voter, timestamp);
        };
    }

    /// Record vote for equity metrics tracking
    /// 
    /// Updates vote distribution and Gini coefficient calculation
    public fun record_vote_for_equity(
        metrics: &mut EquityMetrics,
        voter: address,
        vote_weight: u64,
        stake_category: u8, // 0=small (<1000), 1=medium (1000-10000), 2=large (>10000)
    ) {
        // Update vote distribution by category
        if (!table::contains(&metrics.vote_distribution, stake_category)) {
            table::add(&mut metrics.vote_distribution, stake_category, 0);
        };
        let category_votes = table::borrow_mut(&mut metrics.vote_distribution, stake_category);
        *category_votes = *category_votes + vote_weight;
        
        // Update total votes
        metrics.total_votes_cast = metrics.total_votes_cast + (vote_weight as u128);
        metrics.unique_voters = metrics.unique_voters + 1;
        
        // Recalculate Gini coefficient (simplified version)
        let gini = calculate_gini_coefficient(metrics);
        metrics.gini_coefficient = gini;
        
        event::emit(EquityMetricsUpdated {
            gini_coefficient: gini,
            total_votes_cast: metrics.total_votes_cast,
            unique_voters: metrics.unique_voters,
        });
    }

    /// Calculate Gini coefficient for vote distribution
    /// 
    /// Gini coefficient measures inequality:
    /// - 0 = perfect equality (everyone has equal votes)
    /// - 10000 = perfect inequality (one person has all votes)
    /// 
    /// Returns value in basis points (0-10000)
    fun calculate_gini_coefficient(metrics: &EquityMetrics): u64 {
        // Simplified Gini calculation based on category distribution
        // In production, this would analyze individual vote distributions
        
        let small_votes = if (table::contains(&metrics.vote_distribution, 0)) {
            *table::borrow(&metrics.vote_distribution, 0)
        } else { 0 };
        
        let medium_votes = if (table::contains(&metrics.vote_distribution, 1)) {
            *table::borrow(&metrics.vote_distribution, 1)
        } else { 0 };
        
        let large_votes = if (table::contains(&metrics.vote_distribution, 2)) {
            *table::borrow(&metrics.vote_distribution, 2)
        } else { 0 };
        
        let total = small_votes + medium_votes + large_votes;
        
        if (total == 0) {
            return 0
        };
        
        // Calculate proportions
        let large_proportion = (large_votes * 10000) / total;
        
        // Simplified Gini: if large holders have >50% of votes, inequality is high
        if (large_proportion > 5000) {
            large_proportion - 5000 + 5000 // Scale to reflect inequality
        } else {
            // More even distribution
            (5000 - large_proportion) / 2
        }
    }

    /// Integer square root approximation using Newton's method
    /// 
    /// This is used for quadratic voting calculation
    fun integer_sqrt(n: u64): u64 {
        if (n == 0) {
            return 0
        };
        
        if (n < 4) {
            return 1
        };
        
        // Initial guess
        let x = n / 2;
        let improved = true;
        
        // Newton's method: using a fixed number of iterations for simplicity
        // In production, would iterate until convergence
        let result = newton_iteration(x, n, 0);
        
        result
    }
    
    /// Helper for Newton's method iteration
    fun newton_iteration(x: u64, n: u64, iteration: u64): u64 {
        if (iteration >= 20) {
            return x
        };
        
        let next_x = (x + n / x) / 2;
        if (next_x >= x) {
            return x
        };
        
        newton_iteration(next_x, n, iteration + 1)
    }

    // === View Functions ===

    /// Get voter's current reputation score
    public fun get_reputation(
        reputation_state: &VoterReputation,
        voter: address
    ): u64 {
        if (table::contains(&reputation_state.reputation_scores, voter)) {
            *table::borrow(&reputation_state.reputation_scores, voter)
        } else {
            0
        }
    }

    /// Get voter's participation count
    public fun get_participation_count(
        reputation_state: &VoterReputation,
        voter: address
    ): u64 {
        if (table::contains(&reputation_state.participation_count, voter)) {
            *table::borrow(&reputation_state.participation_count, voter)
        } else {
            0
        }
    }

    /// Get current Gini coefficient
    public fun get_gini_coefficient(metrics: &EquityMetrics): u64 {
        metrics.gini_coefficient
    }

    /// Get total votes cast
    public fun get_total_votes_cast(metrics: &EquityMetrics): u128 {
        metrics.total_votes_cast
    }

    /// Get unique voter count
    public fun get_unique_voters(metrics: &EquityMetrics): u64 {
        metrics.unique_voters
    }

    /// Categorize stake amount for equity tracking
    /// Returns: 0=small (<1000), 1=medium (1000-10000), 2=large (>10000)
    public fun categorize_stake(stake_amount: u64): u8 {
        if (stake_amount < 1000) {
            0
        } else if (stake_amount < 10000) {
            1
        } else {
            2
        }
    }

    // === Test-only Functions ===

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
