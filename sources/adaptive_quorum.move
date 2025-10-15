// File: sources/adaptive_quorum.move
// Adaptive quorum calculation module based on historical participation data
// Implements EbA (Ecosystem-based Adaptation) principle of adaptive governance
// 
// This module analyzes historical participation patterns to dynamically adjust
// quorum requirements, ensuring governance remains both accessible and legitimate.

module hybrid_governance_pkg::adaptive_quorum {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;

    // === Error Codes ===
    
    /// Insufficient historical data to calculate adaptive quorum
    const E_INSUFFICIENT_DATA: u64 = 1;
    
    /// Invalid proposal type provided
    const E_INVALID_PROPOSAL_TYPE: u64 = 2;
    
    /// Invalid participation rate (must be 0-10000)
    const E_INVALID_PARTICIPATION_RATE: u64 = 3;

    // === Constants ===
    
    /// Minimum number of historical data points needed
    const MIN_HISTORICAL_DATA_POINTS: u64 = 5;
    
    /// Maximum number of historical data points to consider
    const MAX_HISTORICAL_DATA_POINTS: u64 = 50;
    
    /// Base quorum percentages for different proposal types (in basis points: 1% = 100)
    const BASE_QUORUM_GENERAL: u8 = 10;      // 10% for general proposals
    const BASE_QUORUM_MINOR: u8 = 20;        // 20% for minor changes
    const BASE_QUORUM_CRITICAL: u8 = 33;     // 33% for critical changes
    const BASE_QUORUM_FUNDING: u8 = 15;      // 15% for funding requests
    const BASE_QUORUM_EMERGENCY: u8 = 40;    // 40% for emergency proposals

    // === Structs ===

    /// Historical participation data for adaptive quorum calculation
    struct ParticipationHistory has key {
        id: UID,
        /// Historical participation rates by proposal type (rate in basis points: 1% = 100)
        history_by_type: Table<u8, vector<u64>>,
        /// Total number of proposals processed
        total_proposals_processed: u64,
        /// Last calculated adaptive quorum percentages by type
        adaptive_quorums: Table<u8, u8>,
    }

    /// Event emitted when adaptive quorum is recalculated
    struct QuorumRecalculated has copy, drop {
        proposal_type: u8,
        old_quorum_percentage: u8,
        new_quorum_percentage: u8,
        avg_participation_rate: u64,
        timestamp: u64,
    }

    /// Event emitted when participation data is recorded
    struct ParticipationRecorded has copy, drop {
        proposal_type: u8,
        participation_rate: u64,
        total_data_points: u64,
    }

    // === Init Function ===

    /// Initialize the adaptive quorum system
    fun init(ctx: &mut TxContext) {
        let history = ParticipationHistory {
            id: object::new(ctx),
            history_by_type: table::new(ctx),
            total_proposals_processed: 0,
            adaptive_quorums: table::new(ctx),
        };
        
        transfer::share_object(history);
    }

    // === Public Functions ===

    /// Calculate adaptive quorum based on historical participation patterns
    /// 
    /// This function analyzes past participation rates for a given proposal type
    /// and adjusts the quorum to optimize for both accessibility (not too high)
    /// and legitimacy (not too low).
    /// 
    /// # Arguments
    /// * `history` - The participation history object
    /// * `proposal_type` - Type of proposal (0=general, 1=minor, 2=critical, 3=funding, 4=emergency)
    /// 
    /// # Returns
    /// * `u8` - Calculated adaptive quorum percentage (0-100)
    /// 
    /// # Algorithm
    /// 1. Retrieve historical participation rates for the proposal type
    /// 2. Calculate average participation rate
    /// 3. Apply adaptive adjustment based on trends
    /// 4. Ensure result stays within safe bounds
    public fun calculate_adaptive_quorum(
        history: &ParticipationHistory,
        proposal_type: u8
    ): u8 {
        // Validate proposal type
        assert!(proposal_type <= 4, E_INVALID_PROPOSAL_TYPE);
        
        // Get base quorum for this proposal type
        let base_quorum = get_base_quorum(proposal_type);
        
        // If no historical data exists, return base quorum
        if (!table::contains(&history.history_by_type, proposal_type)) {
            return base_quorum
        };
        
        let historical_rates = table::borrow(&history.history_by_type, proposal_type);
        let data_points = vector::length(historical_rates);
        
        // Need minimum data points for adaptive calculation
        if (data_points < MIN_HISTORICAL_DATA_POINTS) {
            return base_quorum
        };
        
        // Calculate average participation rate
        let avg_rate = calculate_average_participation(historical_rates);
        
        // Calculate adaptive quorum using sophisticated algorithm
        // If participation is consistently high, we can lower quorum slightly
        // If participation is low, we keep quorum at base level
        let adaptive_quorum = if (avg_rate > 5000) {
            // High participation (>50%): can reduce quorum by up to 20%
            let reduction = ((avg_rate - 5000) * (base_quorum as u64) / 10000);
            let min_quorum = (base_quorum as u64) * 80 / 100; // Never go below 80% of base
            if ((base_quorum as u64) > reduction && (base_quorum as u64) - reduction >= min_quorum) {
                ((base_quorum as u64) - reduction) as u8
            } else {
                (min_quorum as u8)
            }
        } else if (avg_rate < 2000) {
            // Low participation (<20%): increase quorum to ensure legitimacy
            let increase = ((2000 - avg_rate) * (base_quorum as u64) / 5000);
            let max_quorum = (base_quorum as u64) * 120 / 100; // Never go above 120% of base
            if ((base_quorum as u64) + increase <= max_quorum) {
                ((base_quorum as u64) + increase) as u8
            } else {
                (max_quorum as u8)
            }
        } else {
            // Moderate participation (20-50%): keep at base level
            base_quorum
        };
        
        adaptive_quorum
    }

    /// Record participation data for a completed proposal
    /// 
    /// # Arguments
    /// * `history` - The participation history object
    /// * `proposal_type` - Type of proposal
    /// * `votes_cast` - Number of votes cast
    /// * `eligible_voters` - Total number of eligible voters
    /// * `ctx` - Transaction context
    public fun record_participation(
        history: &mut ParticipationHistory,
        proposal_type: u8,
        votes_cast: u64,
        eligible_voters: u64,
        ctx: &mut TxContext
    ) {
        assert!(proposal_type <= 4, E_INVALID_PROPOSAL_TYPE);
        
        // Calculate participation rate in basis points (1% = 100)
        let participation_rate = if (eligible_voters > 0) {
            (votes_cast * 10000) / eligible_voters
        } else {
            0
        };
        
        assert!(participation_rate <= 10000, E_INVALID_PARTICIPATION_RATE);
        
        // Get or create history vector for this proposal type
        if (!table::contains(&history.history_by_type, proposal_type)) {
            table::add(&mut history.history_by_type, proposal_type, vector::empty());
        };
        
        let type_history = table::borrow_mut(&mut history.history_by_type, proposal_type);
        
        // Add new data point
        vector::push_back(type_history, participation_rate);
        
        // Keep only the most recent data points (sliding window)
        while (vector::length(type_history) > MAX_HISTORICAL_DATA_POINTS) {
            vector::remove(type_history, 0);
        };
        
        history.total_proposals_processed = history.total_proposals_processed + 1;
        
        // Emit event
        event::emit(ParticipationRecorded {
            proposal_type,
            participation_rate,
            total_data_points: vector::length(type_history),
        });
    }

    /// Update the stored adaptive quorum for a proposal type
    /// 
    /// Should be called periodically to refresh adaptive quorum values
    public fun update_adaptive_quorum(
        history: &mut ParticipationHistory,
        proposal_type: u8,
        ctx: &mut TxContext
    ) {
        let old_quorum = if (table::contains(&history.adaptive_quorums, proposal_type)) {
            *table::borrow(&history.adaptive_quorums, proposal_type)
        } else {
            get_base_quorum(proposal_type)
        };
        
        let new_quorum = calculate_adaptive_quorum(history, proposal_type);
        
        if (table::contains(&history.adaptive_quorums, proposal_type)) {
            *table::borrow_mut(&mut history.adaptive_quorums, proposal_type) = new_quorum;
        } else {
            table::add(&mut history.adaptive_quorums, proposal_type, new_quorum);
        };
        
        // Calculate average participation for event
        let avg_rate = if (table::contains(&history.history_by_type, proposal_type)) {
            let historical_rates = table::borrow(&history.history_by_type, proposal_type);
            calculate_average_participation(historical_rates)
        } else {
            0
        };
        
        event::emit(QuorumRecalculated {
            proposal_type,
            old_quorum_percentage: old_quorum,
            new_quorum_percentage: new_quorum,
            avg_participation_rate: avg_rate,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Get the current adaptive quorum for a proposal type
    /// Falls back to base quorum if no adaptive quorum has been calculated
    public fun get_adaptive_quorum(
        history: &ParticipationHistory,
        proposal_type: u8
    ): u8 {
        if (table::contains(&history.adaptive_quorums, proposal_type)) {
            *table::borrow(&history.adaptive_quorums, proposal_type)
        } else {
            get_base_quorum(proposal_type)
        }
    }

    // === Helper Functions ===

    /// Get base quorum percentage for a proposal type
    fun get_base_quorum(proposal_type: u8): u8 {
        if (proposal_type == 0) { 
            BASE_QUORUM_GENERAL 
        } else if (proposal_type == 1) { 
            BASE_QUORUM_MINOR 
        } else if (proposal_type == 2) { 
            BASE_QUORUM_CRITICAL 
        } else if (proposal_type == 3) { 
            BASE_QUORUM_FUNDING 
        } else { 
            BASE_QUORUM_EMERGENCY 
        }
    }

    /// Calculate average participation rate from historical data
    /// Returns rate in basis points (1% = 100)
    fun calculate_average_participation(historical_rates: &vector<u64>): u64 {
        let len = vector::length(historical_rates);
        if (len == 0) {
            return 0
        };
        
        let sum: u64 = 0;
        let i = 0;
        while (i < len) {
            sum = sum + *vector::borrow(historical_rates, i);
            i = i + 1;
        };
        
        sum / len
    }

    // === View Functions ===

    /// Get total number of proposals processed
    public fun get_total_proposals_processed(history: &ParticipationHistory): u64 {
        history.total_proposals_processed
    }

    /// Get number of historical data points for a proposal type
    public fun get_data_point_count(
        history: &ParticipationHistory,
        proposal_type: u8
    ): u64 {
        if (!table::contains(&history.history_by_type, proposal_type)) {
            0
        } else {
            vector::length(table::borrow(&history.history_by_type, proposal_type))
        }
    }

    /// Get average historical participation rate for a proposal type
    /// Returns rate in basis points (1% = 100)
    public fun get_average_participation_rate(
        history: &ParticipationHistory,
        proposal_type: u8
    ): u64 {
        if (!table::contains(&history.history_by_type, proposal_type)) {
            0
        } else {
            let historical_rates = table::borrow(&history.history_by_type, proposal_type);
            calculate_average_participation(historical_rates)
        }
    }

    // === Test-only Functions ===

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
