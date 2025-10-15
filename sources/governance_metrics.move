// File: sources/governance_metrics.move
// Real-time governance monitoring and metrics tracking module
// Implements EbA (Ecosystem-based Adaptation) monitoring and evaluation framework
//
// This module provides comprehensive metrics tracking for governance quality,
// including participation rates, proposal success metrics, and system health indicators.

module hybrid_governance_pkg::governance_metrics {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::event;

    // === Error Codes ===
    
    /// Invalid metric value provided
    const E_INVALID_METRIC_VALUE: u64 = 1;
    
    /// Metric period not found
    const E_PERIOD_NOT_FOUND: u64 = 2;

    // === Constants ===
    
    /// Alert threshold for low participation (30%)
    const ALERT_THRESHOLD_PARTICIPATION: u64 = 3000;
    
    /// Alert threshold for low proposal quality (60%)
    const ALERT_THRESHOLD_QUALITY: u64 = 6000;
    
    /// Success indicator: target participation rate (50%)
    const TARGET_PARTICIPATION_RATE: u64 = 5000;
    
    /// Success indicator: target execution rate (80%)
    const TARGET_EXECUTION_RATE: u64 = 8000;

    // === Structs ===

    /// Real-time governance metrics tracking
    /// Based on the monitoring framework in EBA_IMPLEMENTATION_ROADMAP.md
    struct GovernanceMetrics has key {
        id: UID,
        /// Total proposals submitted
        total_proposals: u64,
        /// Currently active proposals
        active_proposals: u64,
        /// Total votes cast across all proposals
        total_votes_cast: u128,
        /// Number of unique voters
        unique_voters: u64,
        /// Current delegation rate (basis points)
        delegation_rate: u64,
        /// Treasury balance (if tracked)
        treasury_balance: u64,
        /// Proposals executed successfully
        proposals_executed: u64,
        /// Proposals failed to execute
        proposals_failed: u64,
        /// Last updated timestamp
        last_update_timestamp: u64,
    }

    /// Periodic metrics for trend analysis
    struct PeriodicMetrics has key {
        id: UID,
        /// Metrics by time period (epoch or timestamp)
        metrics_by_period: Table<u64, PeriodMetrics>,
        /// Rolling average participation rate
        avg_participation_rate: u64,
        /// Rolling average proposal quality score
        avg_quality_score: u64,
    }

    /// Metrics for a specific time period
    struct PeriodMetrics has store, copy, drop {
        period: u64,
        proposals_submitted: u64,
        votes_cast: u64,
        unique_voters: u64,
        participation_rate: u64,
        quality_score: u64,
        execution_success_rate: u64,
    }

    /// Alert tracking for governance issues
    struct GovernanceAlerts has key {
        id: UID,
        /// Active alerts by type
        active_alerts: Table<u8, AlertInfo>,
        /// Alert history
        alert_history: vector<AlertInfo>,
    }

    /// Alert information
    struct AlertInfo has store, copy, drop {
        alert_type: u8, // 0=low_participation, 1=low_quality, 2=treasury_anomaly, 3=system_error
        severity: u8,   // 0=info, 1=warning, 2=critical
        message: vector<u8>,
        timestamp: u64,
        resolved: bool,
    }

    /// Event emitted when metrics are updated
    struct MetricsUpdated has copy, drop {
        total_proposals: u64,
        active_proposals: u64,
        total_votes_cast: u128,
        unique_voters: u64,
        participation_rate: u64,
        timestamp: u64,
    }

    /// Event emitted when an alert is triggered
    struct AlertTriggered has copy, drop {
        alert_type: u8,
        severity: u8,
        message: vector<u8>,
        timestamp: u64,
    }

    /// Event emitted for quality assessment
    struct QualityAssessment has copy, drop {
        inclusiveness_score: u64,
        transparency_score: u64,
        accountability_score: u64,
        effectiveness_score: u64,
        equity_score: u64,
        overall_quality: u64,
        timestamp: u64,
    }

    // === Init Function ===

    /// Initialize the governance metrics system
    fun init(ctx: &mut TxContext) {
        let metrics = GovernanceMetrics {
            id: object::new(ctx),
            total_proposals: 0,
            active_proposals: 0,
            total_votes_cast: 0,
            unique_voters: 0,
            delegation_rate: 0,
            treasury_balance: 0,
            proposals_executed: 0,
            proposals_failed: 0,
            last_update_timestamp: 0,
        };
        
        let periodic = PeriodicMetrics {
            id: object::new(ctx),
            metrics_by_period: table::new(ctx),
            avg_participation_rate: 0,
            avg_quality_score: 0,
        };
        
        let alerts = GovernanceAlerts {
            id: object::new(ctx),
            active_alerts: table::new(ctx),
            alert_history: vector::empty(),
        };
        
        transfer::share_object(metrics);
        transfer::share_object(periodic);
        transfer::share_object(alerts);
    }

    // === Public Functions ===

    /// Update real-time governance metrics
    /// 
    /// Should be called after each significant governance action
    /// (proposal creation, vote, execution, etc.)
    public fun update_metrics(
        metrics: &mut GovernanceMetrics,
        total_proposals: u64,
        active_proposals: u64,
        total_votes_cast: u128,
        unique_voters: u64,
        delegation_rate: u64,
        treasury_balance: u64,
        timestamp: u64,
    ) {
        metrics.total_proposals = total_proposals;
        metrics.active_proposals = active_proposals;
        metrics.total_votes_cast = total_votes_cast;
        metrics.unique_voters = unique_voters;
        metrics.delegation_rate = delegation_rate;
        metrics.treasury_balance = treasury_balance;
        metrics.last_update_timestamp = timestamp;
        
        // Calculate participation rate
        let participation_rate = if (unique_voters > 0 && total_proposals > 0) {
            ((total_votes_cast as u64) * 10000) / (unique_voters * total_proposals)
        } else {
            0
        };
        
        event::emit(MetricsUpdated {
            total_proposals,
            active_proposals,
            total_votes_cast,
            unique_voters,
            participation_rate,
            timestamp,
        });
    }

    /// Record proposal execution result
    public fun record_execution_result(
        metrics: &mut GovernanceMetrics,
        success: bool,
    ) {
        if (success) {
            metrics.proposals_executed = metrics.proposals_executed + 1;
        } else {
            metrics.proposals_failed = metrics.proposals_failed + 1;
        };
    }

    /// Record metrics for a specific period (e.g., monthly)
    /// 
    /// Used for trend analysis and periodic evaluation
    public fun record_period_metrics(
        periodic: &mut PeriodicMetrics,
        period: u64,
        proposals_submitted: u64,
        votes_cast: u64,
        unique_voters: u64,
        eligible_voters: u64,
        quality_score: u64,
        executions_successful: u64,
        executions_total: u64,
    ) {
        let participation_rate = if (eligible_voters > 0) {
            (unique_voters * 10000) / eligible_voters
        } else {
            0
        };
        
        let execution_rate = if (executions_total > 0) {
            (executions_successful * 10000) / executions_total
        } else {
            0
        };
        
        let period_metrics = PeriodMetrics {
            period,
            proposals_submitted,
            votes_cast,
            unique_voters,
            participation_rate,
            quality_score,
            execution_success_rate: execution_rate,
        };
        
        table::add(&mut periodic.metrics_by_period, period, period_metrics);
        
        // Update rolling averages (simple average of last 3 periods)
        update_rolling_averages(periodic);
    }

    /// Trigger an alert for governance issues
    /// 
    /// Monitors key thresholds and creates alerts when issues are detected
    public fun check_and_trigger_alerts(
        metrics: &GovernanceMetrics,
        alerts: &mut GovernanceAlerts,
        participation_rate: u64,
        quality_score: u64,
        timestamp: u64,
    ) {
        // Check participation threshold
        if (participation_rate < ALERT_THRESHOLD_PARTICIPATION) {
            let alert = AlertInfo {
                alert_type: 0, // low_participation
                severity: 1,   // warning
                message: b"Participation rate below 30% threshold",
                timestamp,
                resolved: false,
            };
            
            if (!table::contains(&alerts.active_alerts, 0)) {
                table::add(&mut alerts.active_alerts, 0, alert);
                vector::push_back(&mut alerts.alert_history, alert);
                
                event::emit(AlertTriggered {
                    alert_type: 0,
                    severity: 1,
                    message: b"Participation rate below 30% threshold",
                    timestamp,
                });
            };
        } else {
            // Resolve alert if it exists
            if (table::contains(&alerts.active_alerts, 0)) {
                let alert = table::borrow_mut(&mut alerts.active_alerts, 0);
                alert.resolved = true;
            };
        };
        
        // Check quality threshold
        if (quality_score < ALERT_THRESHOLD_QUALITY) {
            let alert = AlertInfo {
                alert_type: 1, // low_quality
                severity: 1,   // warning
                message: b"Proposal quality score below 60% threshold",
                timestamp,
                resolved: false,
            };
            
            if (!table::contains(&alerts.active_alerts, 1)) {
                table::add(&mut alerts.active_alerts, 1, alert);
                vector::push_back(&mut alerts.alert_history, alert);
                
                event::emit(AlertTriggered {
                    alert_type: 1,
                    severity: 1,
                    message: b"Proposal quality score below 60% threshold",
                    timestamp,
                });
            };
        } else {
            if (table::contains(&alerts.active_alerts, 1)) {
                let alert = table::borrow_mut(&mut alerts.active_alerts, 1);
                alert.resolved = true;
            };
        };
    }

    /// Assess overall governance quality using EbA framework
    /// 
    /// Evaluates five key dimensions:
    /// 1. Inclusiveness - breadth of participation
    /// 2. Transparency - information accessibility
    /// 3. Accountability - responsibility tracking
    /// 4. Effectiveness - achieving outcomes
    /// 5. Equity - fair power distribution
    public fun assess_governance_quality(
        metrics: &GovernanceMetrics,
        eligible_voters: u64,
        equity_score: u64,
        transparency_score: u64,
        timestamp: u64,
    ): u64 {
        // 1. Inclusiveness: Based on participation breadth
        let inclusiveness = if (eligible_voters > 0) {
            (metrics.unique_voters * 10000) / eligible_voters
        } else {
            0
        };
        
        // 2. Transparency: Provided as parameter (from event coverage, documentation)
        let transparency = transparency_score;
        
        // 3. Accountability: Based on execution success rate
        let total_completed = metrics.proposals_executed + metrics.proposals_failed;
        let accountability = if (total_completed > 0) {
            (metrics.proposals_executed * 10000) / total_completed
        } else {
            10000 // Perfect score if no failures yet
        };
        
        // 4. Effectiveness: Based on proposal execution rate
        let effectiveness = if (metrics.total_proposals > 0) {
            (metrics.proposals_executed * 10000) / metrics.total_proposals
        } else {
            0
        };
        
        // 5. Equity: Provided as parameter (from vote distribution analysis)
        let equity = equity_score;
        
        // Calculate overall quality (weighted average)
        let overall_quality = (
            inclusiveness * 20 +      // 20% weight
            transparency * 20 +       // 20% weight
            accountability * 20 +     // 20% weight
            effectiveness * 20 +      // 20% weight
            equity * 20              // 20% weight
        ) / 100;
        
        event::emit(QualityAssessment {
            inclusiveness_score: inclusiveness,
            transparency_score: transparency,
            accountability_score: accountability,
            effectiveness_score: effectiveness,
            equity_score: equity,
            overall_quality,
            timestamp,
        });
        
        overall_quality
    }

    /// Calculate key performance indicators (KPIs)
    /// 
    /// Returns a tuple of critical metrics for dashboard display
    public fun calculate_kpis(
        metrics: &GovernanceMetrics,
        eligible_voters: u64,
    ): (u64, u64, u64, u64) {
        // 1. Participation Rate (% of eligible voters who voted)
        let participation_rate = if (eligible_voters > 0) {
            (metrics.unique_voters * 10000) / eligible_voters
        } else {
            0
        };
        
        // 2. Proposal Success Rate (% of approved proposals executed)
        let total_completed = metrics.proposals_executed + metrics.proposals_failed;
        let success_rate = if (total_completed > 0) {
            (metrics.proposals_executed * 10000) / total_completed
        } else {
            10000
        };
        
        // 3. Activity Rate (proposals per period)
        let activity_rate = metrics.total_proposals; // Simplified - would be per-period in production
        
        // 4. Delegation Rate
        let delegation_rate = metrics.delegation_rate;
        
        (participation_rate, success_rate, activity_rate, delegation_rate)
    }

    // === Helper Functions ===

    /// Update rolling averages for trend analysis
    fun update_rolling_averages(periodic: &mut PeriodicMetrics) {
        // This would calculate rolling averages from recent periods
        // Simplified implementation for now
        periodic.avg_participation_rate = 5000; // Placeholder
        periodic.avg_quality_score = 7500; // Placeholder
    }

    // === View Functions ===

    /// Get current metrics snapshot
    public fun get_current_metrics(metrics: &GovernanceMetrics): (
        u64, // total_proposals
        u64, // active_proposals
        u128, // total_votes_cast
        u64, // unique_voters
        u64, // delegation_rate
        u64  // treasury_balance
    ) {
        (
            metrics.total_proposals,
            metrics.active_proposals,
            metrics.total_votes_cast,
            metrics.unique_voters,
            metrics.delegation_rate,
            metrics.treasury_balance
        )
    }

    /// Get execution statistics
    public fun get_execution_stats(metrics: &GovernanceMetrics): (u64, u64) {
        (metrics.proposals_executed, metrics.proposals_failed)
    }

    /// Check if participation is meeting targets
    public fun is_meeting_participation_target(
        metrics: &GovernanceMetrics,
        eligible_voters: u64
    ): bool {
        let participation_rate = if (eligible_voters > 0) {
            (metrics.unique_voters * 10000) / eligible_voters
        } else {
            0
        };
        
        participation_rate >= TARGET_PARTICIPATION_RATE
    }

    /// Check if execution is meeting targets
    public fun is_meeting_execution_target(metrics: &GovernanceMetrics): bool {
        let total_completed = metrics.proposals_executed + metrics.proposals_failed;
        let execution_rate = if (total_completed > 0) {
            (metrics.proposals_executed * 10000) / total_completed
        } else {
            10000
        };
        
        execution_rate >= TARGET_EXECUTION_RATE
    }

    /// Get number of active alerts
    public fun get_active_alert_count(alerts: &GovernanceAlerts): u64 {
        count_active_alerts_recursive(alerts, 0, 0)
    }
    
    /// Helper to count active alerts recursively
    fun count_active_alerts_recursive(alerts: &GovernanceAlerts, i: u64, count: u64): u64 {
        if (i >= 4) { // 4 alert types
            return count
        };
        
        let new_count = if (table::contains(&alerts.active_alerts, (i as u8))) {
            let alert = table::borrow(&alerts.active_alerts, (i as u8));
            if (!alert.resolved) {
                count + 1
            } else {
                count
            }
        } else {
            count
        };
        
        count_active_alerts_recursive(alerts, i + 1, new_count)
    }

    // === Test-only Functions ===

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
