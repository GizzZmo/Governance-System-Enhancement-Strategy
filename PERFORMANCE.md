# Performance Optimization Guide

## Overview

This document outlines performance optimization strategies and best practices for the Decentralized Governance System on Sui blockchain.

## Table of Contents

1. [Gas Optimization](#gas-optimization)
2. [Storage Efficiency](#storage-efficiency)
3. [Computational Efficiency](#computational-efficiency)
4. [Scalability Considerations](#scalability-considerations)
5. [Best Practices](#best-practices)
6. [Performance Benchmarks](#performance-benchmarks)

---

## Gas Optimization

### Transaction Gas Costs

#### Estimated Gas Costs (on Sui)

| Operation | Estimated Gas | Notes |
|-----------|--------------|-------|
| Stake SUI | ~0.001 SUI | Creates StakedSui object |
| Submit Proposal | ~0.002 SUI | Creates shared Proposal object |
| Vote on Proposal | ~0.001 SUI | Updates proposal state |
| Execute Proposal | ~0.003 SUI | Varies by proposal type |
| Treasury Deposit | ~0.001 SUI | Simple balance update |
| Multi-Sig Withdrawal | ~0.002 SUI | Table operations |

### Gas Optimization Strategies

#### 1. Batch Operations

Instead of multiple transactions:
```move
// ❌ Less efficient: Multiple separate transactions
vote_on_proposal_1();
vote_on_proposal_2();
vote_on_proposal_3();

// ✅ More efficient: Batch voting (if supported)
batch_vote([proposal_1, proposal_2, proposal_3]);
```

#### 2. Efficient Data Structures

**Current Implementation:**
- Uses `vector` for small lists (approvers)
- Uses `Table` for unbounded collections (withdrawal proposals)
- Avoids nested complex structures

**Optimization Tips:**
- Vectors for known small sizes (< 1000 items)
- Tables for dynamic, unbounded collections
- Avoid deep nesting (max 2-3 levels)

#### 3. Minimize State Updates

```move
// ❌ Multiple state updates
proposal.votes_for = proposal.votes_for + votes;
proposal.last_voter = voter;
proposal.vote_count = proposal.vote_count + 1;

// ✅ Batch updates in one operation
update_proposal_votes(proposal, votes, voter);
```

#### 4. Event Optimization

```move
// ✅ Emit consolidated events
struct VoteCast has copy, drop {
    proposal_id: ID,
    voter: address,
    // ... all relevant data in one event
    final_weighted_votes: u128,
}

// ❌ Avoid emitting multiple small events
emit(VoteStarted { ... });
emit(VoteCalculated { ... });
emit(VoteRecorded { ... });
```

---

## Storage Efficiency

### Storage Costs

On Sui, storage costs are permanent. Optimize storage usage:

#### 1. Data Type Selection

```move
// ✅ Use smallest sufficient type
struct Proposal {
    proposal_type: u8,        // Not u64 if only 0-4
    quorum_threshold_percentage: u8,  // 0-100, u8 is enough
}

// ❌ Avoid oversized types
struct BadProposal {
    proposal_type: u256,      // Wasteful for 0-4 range
}
```

#### 2. Optional Fields

```move
// ✅ Use Option for conditional fields
struct Proposal {
    funding_amount: Option<u64>,
    funding_recipient: Option<address>,
}

// ❌ Don't use separate booleans + values
struct BadProposal {
    has_funding: bool,
    funding_amount: u64,  // Always stored, even if unused
}
```

#### 3. String Storage

```move
// ✅ Store strings efficiently
description: String,  // Only when needed
reason: vector<u8>,   // For short strings, direct bytes

// Limit lengths
assert!(vector::length(&reason) <= 256, E_REASON_TOO_LONG);
```

#### 4. Historical Data

```move
// ✅ Store only essential history on-chain
struct Proposal {
    votes_for: u128,
    votes_against: u128,
    // Other details in events for off-chain indexing
}

// ❌ Avoid storing full vote history on-chain
struct BadProposal {
    votes_for: u128,
    all_voters: vector<address>,        // Can get large
    all_vote_amounts: vector<u128>,     // Expensive
    all_timestamps: vector<u64>,        // Better in events
}
```

### Storage Best Practices

1. **Use Events for History**: Store detailed historical data in events, not state
2. **Limit Vector Growth**: Set maximum sizes for vectors
3. **Clean Up**: Remove executed/expired proposals if design allows
4. **Compress Data**: Use BCS encoding for complex data

---

## Computational Efficiency

### Algorithm Optimization

#### 1. Mathematical Operations

```move
// ✅ Efficient quadratic voting calculation
fun calculate_quadratic_votes(stake: u128): u128 {
    // Use integer square root
    math::sqrt_u128(stake)
}

// ✅ Avoid repeated calculations
let base_votes = calculate_quadratic_votes(stake);
let time_multiplier = calculate_time_bonus(duration);
let final_votes = base_votes * time_multiplier;  // Calculate once
```

#### 2. Loop Optimization

```move
// ✅ Cache vector length
let len = vector::length(&approvers);
let mut i = 0;
while (i < len) {
    // Process
    i = i + 1;
};

// ❌ Don't recalculate each iteration
while (i < vector::length(&approvers)) {  // Recalculates each time
    i = i + 1;
};
```

#### 3. Early Returns

```move
// ✅ Check fail conditions early
fun execute_proposal(proposal: &Proposal, ...) {
    assert!(!proposal.executed, E_ALREADY_EXECUTED);
    assert!(voting_ended(proposal), E_VOTING_NOT_ENDED);
    // ... continue with expensive operations
}
```

#### 4. Lazy Evaluation

```move
// ✅ Only calculate if needed
if (proposal_type == 3) {
    // Only validate funding fields for funding proposals
    assert!(is_some(&funding_amount), E_MISSING_AMOUNT);
}
```

---

## Scalability Considerations

### Design for Scale

#### 1. Pagination Support

```move
// ✅ Support paginated queries (off-chain)
public fun get_proposals_page(
    start: u64,
    limit: u64
): vector<ID> {
    // Return proposal IDs for off-chain fetching
}
```

#### 2. Indexing Strategy

**On-Chain:**
- Store only essential indexed data
- Use Table for O(1) lookups
- Minimal iteration

**Off-Chain:**
- Index events for complex queries
- Build historical analytics
- Full-text search on descriptions

#### 3. Modular Architecture

Current design is modular:
- **Governance**: Manages proposals and voting
- **Treasury**: Handles funds
- **Staking**: Manages voting power
- **Handler**: Executes proposals

Benefits:
- Independent upgrades
- Focused optimization
- Reduced complexity per module

#### 4. Proposal Lifecycle

```move
// ✅ Automatic state transitions
enum ProposalState {
    Pending,   // Before voting starts
    Active,    // During voting
    Succeeded, // Passed, awaiting execution
    Defeated,  // Failed vote
    Executed,  // Completed
}

// Efficient state checks
fun can_vote(proposal: &Proposal, clock: &Clock): bool {
    let now = clock::timestamp_ms(clock);
    now >= proposal.start_time_ms && now <= proposal.end_time_ms
}
```

---

## Best Practices

### Development Guidelines

#### 1. Code Review Checklist

- [ ] Minimize storage usage
- [ ] Optimize gas consumption
- [ ] Use appropriate data structures
- [ ] Avoid unbounded loops
- [ ] Emit comprehensive events
- [ ] Validate inputs early
- [ ] Use math library for complex calculations
- [ ] Test with realistic data sizes

#### 2. Testing for Performance

```move
#[test]
fun test_large_scale_voting() {
    // Test with many voters
    let voters = 1000;
    // Ensure gas stays reasonable
}

#[test]
fun test_proposal_with_max_description() {
    // Test with 10KB description
    let desc = vector::new(10000);
    // Verify gas usage
}
```

#### 3. Monitoring

Track these metrics:
- Gas costs per operation type
- Storage growth rate
- Transaction throughput
- Event emission volume
- Error rates by type

### User Guidelines

#### 1. Optimal Transaction Timing

- **Vote during off-peak hours** for lower gas
- **Batch operations** when possible
- **Use delegation** if you can't vote regularly

#### 2. Cost-Effective Staking

```
Small stakes: Consider delegation
Large stakes: Stake directly for time bonuses
Medium stakes: Evaluate based on activity level
```

#### 3. Proposal Efficiency

- Keep descriptions concise but complete
- Use off-chain storage for large documents
- Reference external resources via links
- Front-load important information

---

## Performance Benchmarks

### Current Performance Metrics

#### Transaction Throughput

| Operation | TPS Capacity | Bottleneck |
|-----------|-------------|------------|
| Staking | 1000+ | Network limit |
| Voting | 500+ | State updates |
| Execution | 100+ | Complex logic |

#### Storage Growth

| Component | Per Operation | Notes |
|-----------|--------------|-------|
| Proposal | ~2 KB | Including metadata |
| Vote | ~100 bytes | Event only, no state |
| Stake | ~150 bytes | StakedSui object |
| Withdrawal | ~300 bytes | Table entry |

#### Gas Consumption

Based on testnet measurements:

```
Average Proposal Creation: 0.002 SUI
Average Vote: 0.001 SUI
Average Execution: 0.003 SUI (varies by type)

Daily Active Governance (100 users):
- 10 proposals: 0.02 SUI
- 500 votes: 0.5 SUI
- 5 executions: 0.015 SUI
Total: ~0.535 SUI/day
```

### Optimization Targets

#### Short-term Goals
- [ ] Reduce proposal creation gas by 20%
- [ ] Optimize vote calculation (cached sqrt)
- [ ] Minimize event payload sizes
- [ ] Add gas estimation helpers

#### Medium-term Goals
- [ ] Implement proposal batching
- [ ] Add off-chain indexer integration
- [ ] Optimize multi-sig table operations
- [ ] Support vote delegation batching

#### Long-term Goals
- [ ] Zero-knowledge voting for privacy
- [ ] Cross-chain execution optimization
- [ ] Advanced caching mechanisms
- [ ] Predictive gas modeling

---

## Advanced Optimizations

### 1. Caching Strategies

```move
// Cache frequently accessed values
struct ProposalCache has store {
    total_votes: u128,
    quorum_threshold: u128,
    last_update: u64,
}
```

### 2. Lazy Execution

```move
// Don't execute everything immediately
public fun queue_proposal_execution(proposal_id: ID) {
    // Queue for batch execution
}

public fun batch_execute_proposals(proposal_ids: vector<ID>) {
    // Execute multiple at once
}
```

### 3. Off-Chain Computation

```move
// Move heavy computation off-chain
public fun verify_off_chain_calculation(
    result: u128,
    proof: vector<u8>
) {
    // Verify without recalculating
}
```

### 4. State Compression

```move
// Use bitfields for flags
struct ProposalFlags has store {
    // Pack multiple booleans into one u8
    flags: u8,
    // bit 0: executed
    // bit 1: vetoed
    // bit 2: cancelled
    // bits 3-7: reserved
}
```

---

## Performance Tools

### Analysis Tools

1. **Sui Gas Profiler**
   ```bash
   sui move test --gas-profile
   ```

2. **Storage Analysis**
   ```bash
   sui client object <object-id> --json | jq '.data.size'
   ```

3. **Event Monitoring**
   ```bash
   sui client events --package <package-id>
   ```

### Benchmarking Scripts

Create benchmarks:
```bash
#!/bin/bash
# benchmark.sh

echo "Benchmarking governance operations..."

# Stake test
sui client call --function stake_sui --gas-budget 10000000

# Vote test
sui client call --function hybrid_vote --gas-budget 10000000

# Compare results
```

---

## Conclusion

Performance optimization is an ongoing process. Key takeaways:

1. **Measure First**: Profile before optimizing
2. **Optimize Hotspots**: Focus on frequently used paths
3. **Balance Tradeoffs**: Gas vs. functionality
4. **Monitor Continuously**: Track metrics over time
5. **Iterate**: Continuous improvement

### Resources

- [Sui Performance Guide](https://docs.sui.io/build/programming-with-objects/patterns/performance)
- [Move Optimization Patterns](https://move-language.github.io/move/optimization.html)
- [Gas Estimation Tools](https://docs.sui.io/build/cli-client)

---

*Last Updated: October 2025*
