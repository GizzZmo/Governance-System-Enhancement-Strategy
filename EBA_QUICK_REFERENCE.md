# EbA Implementation Quick Reference
## Fast Look-Up Guide for Developers

*Quick reference for EBA_IMPLEMENTATION_ROADMAP.md code implementations*

---

## 📦 Module Overview

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| **adaptive_quorum** | Dynamic quorum calculation | `calculate_adaptive_quorum()`, `record_participation()` |
| **equity_voting** | Quadratic voting + reputation | `calculate_equitable_vote_weight()`, `update_reputation()` |
| **governance_metrics** | Real-time monitoring | `update_metrics()`, `assess_governance_quality()` |
| **unified_proposal_handler** | Centralized execution | `register_proposal()`, `execute_proposal()` |

---

## 🚀 Quick Start

### 1. Deploy System
```bash
sui client publish --gas-budget 100000000
export PACKAGE_ID=<your-package-id>
```

### 2. Vote Simplified
```bash
./scripts/vote.sh <proposal-id> support
./scripts/vote.sh <proposal-id> against
```

---

## 📊 Adaptive Quorum

### Calculate Adaptive Quorum
```move
use hybrid_governance_pkg::adaptive_quorum;

// Get adaptive quorum for proposal type
let quorum = adaptive_quorum::get_adaptive_quorum(history, proposal_type);

// Record participation after vote
adaptive_quorum::record_participation(
    history,
    proposal_type,
    votes_cast,
    eligible_voters,
    ctx
);
```

### Base Quorum Levels
- General (0): 10%
- Minor Changes (1): 20%
- Critical (2): 33%
- Funding (3): 15%
- Emergency (4): 40%

### Adaptive Logic
- **High participation (>50%)**: Reduce quorum up to 20%
- **Low participation (<20%)**: Increase quorum up to 20%
- **Moderate (20-50%)**: Keep base level

---

## ⚖️ Equity Voting

### Calculate Vote Weight
```move
use hybrid_governance_pkg::equity_voting;

let vote_weight = equity_voting::calculate_equitable_vote_weight(
    stake_amount,    // e.g., 10000
    reputation,      // e.g., 500
    voter_address,
    ctx
);
```

### Reputation Updates
```move
// Increase reputation (+10 for voting)
equity_voting::update_reputation(
    reputation_state,
    voter,
    10,      // delta
    true,    // is_increase
    timestamp
);

// Decrease reputation (-50 for violations)
equity_voting::update_reputation(
    reputation_state,
    voter,
    50,      // delta
    false,   // is_increase
    timestamp
);
```

### Vote Weight Formula
```
base_votes = √(stake_amount)
reputation_factor = 100 + (reputation / 10)
final_votes = (base_votes × reputation_factor) / 100
```

### Example Calculations
| Stake | Reputation | Final Votes |
|-------|-----------|-------------|
| 10,000 | 0 | 100 |
| 10,000 | 500 | 150 |
| 10,000 | 1,000 | 200 |
| 100,000 | 0 | 316 |
| 100,000 | 1,000 | 632 |

---

## 📈 Governance Metrics

### Update Metrics
```move
use hybrid_governance_pkg::governance_metrics;

governance_metrics::update_metrics(
    metrics,
    total_proposals,
    active_proposals,
    total_votes_cast,
    unique_voters,
    delegation_rate,
    treasury_balance,
    timestamp
);
```

### Check Alerts
```move
governance_metrics::check_and_trigger_alerts(
    metrics,
    alerts,
    participation_rate,  // basis points (3000 = 30%)
    quality_score,       // basis points (7000 = 70%)
    timestamp
);
```

### Assess Quality
```move
let quality_score = governance_metrics::assess_governance_quality(
    metrics,
    eligible_voters,
    equity_score,
    transparency_score,
    timestamp
);
// Returns: 0-10000 (basis points, 100% = 10000)
```

### Alert Thresholds
- Participation < 30% → ⚠️ Warning
- Quality < 60% → ⚠️ Warning
- Treasury anomaly → 🔴 Critical
- System error → 🔴 Critical

### KPIs
```move
let (participation, success, activity, delegation) = 
    governance_metrics::calculate_kpis(metrics, eligible_voters);
```

---

## 🎯 Unified Proposal Handler

### Register Proposal
```move
use hybrid_governance_pkg::unified_proposal_handler;

unified_proposal_handler::register_proposal(
    registry,
    proposal_id,
    proposal_type,  // 0-4
    description_hash,
    ctx
);
```

### Approve & Execute
```move
// After voting passes
unified_proposal_handler::approve_proposal(registry, proposal_id, ctx);

// Execute
let success = unified_proposal_handler::execute_proposal(
    registry,
    capability,
    proposal_id,
    ctx
);
```

### Batch Processing
```move
// Process up to 10 proposals from queue
unified_proposal_handler::process_execution_queue(
    registry,
    capability,
    10,  // max_to_process
    ctx
);
```

### Proposal Types
0. General
1. Parameter Change
2. Critical System Change
3. Funding Request
4. Emergency

---

## 🔧 Common Patterns

### Complete Voting Flow
```move
// 1. Calculate equitable vote weight
let vote_weight = equity_voting::calculate_equitable_vote_weight(
    stake_amount, reputation, voter, ctx
);

// 2. Cast vote (your existing logic)
// governance::cast_vote(proposal, vote_weight, for_vote);

// 3. Record for equity tracking
let category = equity_voting::categorize_stake(stake_amount);
equity_voting::record_vote_for_equity(metrics, voter, vote_weight, category);

// 4. Update reputation
equity_voting::update_reputation(reputation_state, voter, 10, true, timestamp);

// 5. Record participation
adaptive_quorum::record_participation(
    history, proposal_type, votes_cast, eligible_voters, ctx
);

// 6. Update metrics
governance_metrics::update_metrics(
    metrics, total_proposals, active_proposals, 
    total_votes, unique_voters, delegation_rate, 
    treasury_balance, timestamp
);
```

### Proposal Lifecycle
```move
// 1. Register in unified system
unified_proposal_handler::register_proposal(
    registry, proposal_id, type, hash, ctx
);

// 2. After vote passes
unified_proposal_handler::approve_proposal(registry, proposal_id, ctx);

// 3. Execute
let success = unified_proposal_handler::execute_proposal(
    registry, capability, proposal_id, ctx
);

// 4. Record result
governance_metrics::record_execution_result(metrics, success);

// 5. Update adaptive quorum
adaptive_quorum::update_adaptive_quorum(history, proposal_type, ctx);
```

---

## 📋 Cheat Sheet

### Value Ranges
- Quorum: 0-100 (percentage)
- Reputation: 0-10000
- Participation rate: 0-10000 (basis points, 100% = 10000)
- Quality scores: 0-10000 (basis points, 100% = 10000)
- Gini coefficient: 0-10000 (0 = perfect equality)

### Proposal Types
```move
const PROPOSAL_TYPE_GENERAL: u8 = 0;
const PROPOSAL_TYPE_PARAMETER: u8 = 1;
const PROPOSAL_TYPE_CRITICAL: u8 = 2;
const PROPOSAL_TYPE_FUNDING: u8 = 3;
const PROPOSAL_TYPE_EMERGENCY: u8 = 4;
```

### Stake Categories
```move
0 = Small (<1,000)
1 = Medium (1,000-10,000)
2 = Large (>10,000)
```

### Alert Types
```move
0 = Low participation
1 = Low quality
2 = Treasury anomaly
3 = System error
```

---

## 🎓 Best Practices

### Adaptive Quorum
- ✅ Update after every proposal
- ✅ Recalculate monthly
- ✅ Maintain min 5 data points
- ✅ Monitor trends

### Equity Voting
- ✅ Update reputation consistently
- ✅ Review Gini coefficient monthly
- ✅ Target <0.6 Gini for healthy equity
- ✅ Balance reputation rewards

### Governance Metrics
- ✅ Update after every action
- ✅ Monitor alerts daily
- ✅ Review quality assessments monthly
- ✅ Use KPIs for dashboards

### Unified Handler
- ✅ Route all proposals through system
- ✅ Secure execution capability
- ✅ Process queue regularly
- ✅ Monitor success rates

---

## 🐛 Troubleshooting

### Issue: Adaptive quorum not calculating
**Fix**: Need minimum 5 historical data points
```move
let count = adaptive_quorum::get_data_point_count(history, proposal_type);
assert!(count >= 5, E_INSUFFICIENT_DATA);
```

### Issue: Vote weight is 0
**Fix**: Check stake > 0 and reputation ≤ 10000
```move
assert!(stake_amount > 0, E_ZERO_STAKE);
assert!(reputation <= 10000, E_INVALID_REPUTATION);
```

### Issue: Alerts not triggering
**Fix**: Verify threshold values
```move
// Participation rate in basis points (3000 = 30%)
if (participation_rate < 3000) {
    // Alert triggered
}
```

### Issue: Execution fails
**Fix**: Check approval and authorization
```move
assert!(proposal_info.approved, E_NOT_APPROVED);
assert!(is_authorized_executor(capability, executor), E_UNAUTHORIZED);
```

---

## 📚 Related Documentation

- **Full Guide**: [EBA_IMPLEMENTATION_GUIDE.md](EBA_IMPLEMENTATION_GUIDE.md)
- **Roadmap**: [EBA_IMPLEMENTATION_ROADMAP.md](EBA_IMPLEMENTATION_ROADMAP.md)
- **Framework**: [EBA_GOVERNANCE_FRAMEWORK.md](EBA_GOVERNANCE_FRAMEWORK.md)
- **User Guide**: [USER_GUIDE.md](USER_GUIDE.md)
- **API Docs**: [API_DOCUMENTATION.md](API_DOCUMENTATION.md)

---

## 🔗 Quick Links

### Scripts
```bash
# Vote
./scripts/vote.sh <proposal-id> support

# Interactive CLI
./scripts/interact.sh
```

### Environment
```bash
export PACKAGE_ID=<your-package-id>
export ADAPTIVE_QUORUM_HISTORY_ID=<object-id>
export EQUITY_METRICS_ID=<object-id>
export GOVERNANCE_METRICS_ID=<object-id>
export PROPOSAL_REGISTRY_ID=<object-id>
```

---

**Version**: 1.0  
**Last Updated**: October 2025  
**Quick Ref for**: EbA Implementation Modules

*Keep this handy while developing! 📌*
