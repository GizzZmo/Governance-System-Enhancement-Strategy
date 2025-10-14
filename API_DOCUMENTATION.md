# API Documentation - Decentralized Governance System

## Overview

This document provides comprehensive API documentation for the Decentralized Governance System built on Sui blockchain using Move language.

## Table of Contents

1. [Governance Module](#governance-module)
2. [Treasury Module](#treasury-module)
3. [Delegation & Staking Module](#delegation--staking-module)
4. [Proposal Handler Module](#proposal-handler-module)
5. [Common Types and Structures](#common-types-and-structures)
6. [Error Codes](#error-codes)
7. [Events](#events)

---

## Governance Module

### Module: `hybrid_governance_pkg::governance`

The governance module manages proposal submission, voting, and execution coordination.

#### Public Functions

##### `submit_proposal`

Submits a new governance proposal to the system.

**Signature:**
```move
public entry fun submit_proposal(
    description_vec: vector<u8>,
    proposal_type: u8,
    funding_amount_opt: Option<u64>,
    funding_recipient_opt: Option<address>,
    param_target_module_opt: Option<vector<u8>>,
    param_name_opt: Option<vector<u8>>,
    param_new_value_bcs_opt: Option<vector<u8>>,
    system_state: &GovernanceSystemState,
    clock: &Clock,
    ctx: &TxContext
)
```

**Parameters:**
- `description_vec`: UTF-8 encoded description (10-10000 bytes)
- `proposal_type`: Type of proposal
  - `0` = General Proposal
  - `1` = Minor Parameter Change
  - `2` = Critical Parameter Change (with veto capability)
  - `3` = Funding Request
  - `4` = Emergency Action
- `funding_amount_opt`: Required for type 3 (must be > 0)
- `funding_recipient_opt`: Required for type 3
- `param_target_module_opt`: Required for types 1, 2
- `param_name_opt`: Required for types 1, 2
- `param_new_value_bcs_opt`: Required for types 1, 2 (BCS encoded value)
- `system_state`: Reference to governance system state
- `clock`: Reference to Sui clock
- `ctx`: Transaction context

**Requirements:**
- Description must be 10-10000 bytes
- System must have non-zero total stake
- Funding amount must be positive for funding proposals
- All required fields must be provided based on proposal type

**Emits:**
- `ProposalCreated` event

**Example Usage:**
```move
// Submit a funding proposal
governance::submit_proposal(
    b"Fund community developer grant",
    3, // Funding request
    option::some(1000000000), // 1000 SUI
    option::some(@0x123),
    option::none(),
    option::none(),
    option::none(),
    &system_state,
    &clock,
    ctx
);
```

##### `hybrid_vote`

Cast a vote on a proposal using hybrid voting mechanism.

**Signature:**
```move
public entry fun hybrid_vote(
    proposal: &mut Proposal,
    staked_sui: &StakedSui,
    support: bool,
    is_veto: bool,
    system_state: &GovernanceSystemState,
    clock: &Clock,
    ctx: &TxContext
)
```

**Parameters:**
- `proposal`: Mutable reference to the proposal
- `staked_sui`: Reference to voter's staked SUI
- `support`: `true` to vote for, `false` to vote against
- `is_veto`: `true` to cast a veto vote (only for critical proposals)
- `system_state`: Reference to governance system state
- `clock`: Reference to Sui clock
- `ctx`: Transaction context

**Voting Mechanism:**
1. **Quadratic Voting**: Base votes = sqrt(stake)
2. **Time Weighting**: Bonus based on staking duration (up to 5x)
3. **Reputation**: Additional weight for active participants

**Requirements:**
- Voting period must be active
- Voter must have sufficient stake
- Veto only allowed for critical proposals (type 2)

**Emits:**
- `VoteCast` event

**Example Usage:**
```move
// Vote in favor of a proposal
governance::hybrid_vote(
    &mut proposal,
    &staked_sui,
    true,  // support
    false, // not a veto
    &system_state,
    &clock,
    ctx
);
```

##### `execute_proposal`

Executes an approved proposal.

**Signature:**
```move
public entry fun execute_proposal(
    proposal: &mut Proposal,
    exec_cap: &ProposalExecutionCap,
    treasury_chest: &mut TreasuryChest,
    staking_system_state: &mut GovernanceSystemState,
    treasury_access_cap: &TreasuryAccessCap,
    treasury_admin_cap: &TreasuryAdminCap,
    staking_admin_cap: &StakingAdminCap,
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Parameters:**
- `proposal`: Mutable reference to proposal
- `exec_cap`: Proposal execution capability
- `treasury_chest`: Mutable reference to treasury
- `staking_system_state`: Mutable reference to staking state
- `treasury_access_cap`: Treasury access capability
- `treasury_admin_cap`: Treasury admin capability
- `staking_admin_cap`: Staking admin capability
- `clock`: Reference to clock
- `ctx`: Transaction context

**Requirements:**
- Voting period must be over
- Proposal must meet quorum
- Proposal must not be vetoed or rejected
- Proposal must not be already executed

**Emits:**
- `ProposalExecuted` event

---

## Treasury Module

### Module: `hybrid_governance_pkg::treasury`

Manages community treasury, funding proposals, and multi-signature controls.

#### Capability Objects

##### `TreasuryAccessCap`

Grants permission to execute governance-approved funding withdrawals.

##### `TreasuryAdminCap`

Grants permission to modify treasury configuration and manage approvers.

#### Public Functions

##### `deposit_funds`

Deposits SUI tokens into the treasury.

**Signature:**
```move
public entry fun deposit_funds(
    treasury_chest: &mut TreasuryChest,
    payment: Coin<SUI>,
    ctx: &mut TxContext
)
```

**Parameters:**
- `treasury_chest`: Mutable reference to treasury
- `payment`: SUI coin to deposit
- `ctx`: Transaction context

**Emits:**
- `FundsDeposited` event

##### `propose_direct_withdrawal`

Proposes a direct withdrawal (multi-sig process).

**Signature:**
```move
public entry fun propose_direct_withdrawal(
    treasury_chest: &mut TreasuryChest,
    recipient: address,
    amount: u64,
    reason: vector<u8>,
    ctx: &mut TxContext
)
```

**Parameters:**
- `treasury_chest`: Mutable reference to treasury
- `recipient`: Address to receive funds
- `amount`: Amount to withdraw (must be > 0 and <= balance)
- `reason`: UTF-8 encoded reason (max 256 bytes)
- `ctx`: Transaction context

**Requirements:**
- Caller must be an authorized approver
- Amount must be positive and not exceed balance
- Reason must be <= 256 bytes

**Emits:**
- `DirectWithdrawalProposed` event
- `DirectWithdrawalApproved` event (auto-approval from proposer)

##### `approve_direct_withdrawal`

Approves a pending direct withdrawal proposal.

**Signature:**
```move
public entry fun approve_direct_withdrawal(
    treasury_chest: &mut TreasuryChest,
    withdrawal_proposal_id: u64,
    ctx: &mut TxContext
)
```

**Requirements:**
- Caller must be an authorized approver
- Proposal must exist and not be executed
- Approver must not have already approved

**Emits:**
- `DirectWithdrawalApproved` event

##### `execute_direct_withdrawal`

Executes an approved direct withdrawal.

**Signature:**
```move
public entry fun execute_direct_withdrawal(
    treasury_chest: &mut TreasuryChest,
    withdrawal_proposal_id: u64,
    ctx: &mut TxContext
)
```

**Requirements:**
- Proposal must have minimum required approvals
- Proposal must not be already executed
- Treasury must have sufficient funds

**Emits:**
- `DirectWithdrawalExecuted` event

##### `add_approver`

Adds a new approver to the multi-sig list (admin only).

**Signature:**
```move
public entry fun add_approver(
    _admin_cap: &TreasuryAdminCap,
    treasury_chest: &mut TreasuryChest,
    new_approver: address,
    ctx: &mut TxContext
)
```

**Requirements:**
- Caller must have TreasuryAdminCap
- Approver list must not be full
- Approver must not already exist

**Emits:**
- `ApproverAdded` event

##### `remove_approver`

Removes an approver from the multi-sig list (admin only).

**Signature:**
```move
public entry fun remove_approver(
    _admin_cap: &TreasuryAdminCap,
    treasury_chest: &mut TreasuryChest,
    approver_to_remove: address,
    ctx: &mut TxContext
)
```

**Requirements:**
- Caller must have TreasuryAdminCap
- Approver must exist in the list

**Emits:**
- `ApproverRemoved` event

---

## Delegation & Staking Module

### Module: `hybrid_governance_pkg::delegation_staking`

Manages token staking, delegation, and reputation tracking.

#### Public Functions

##### `stake_sui`

Stakes SUI tokens to gain voting power.

**Signature:**
```move
public entry fun stake_sui(
    system_state: &mut GovernanceSystemState,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Returns:**
- Creates a `StakedSui` object transferred to the staker

**Requirements:**
- Payment amount must meet minimum stake requirement

##### `unstake_sui`

Unstakes SUI tokens and returns them to the owner.

**Signature:**
```move
public entry fun unstake_sui(
    system_state: &mut GovernanceSystemState,
    staked_sui: StakedSui,
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Requirements:**
- Unstaking may have a cooldown period

##### `delegate_voting_power`

Delegates voting power to another address.

**Signature:**
```move
public entry fun delegate_voting_power(
    staked_sui: &mut StakedSui,
    delegate_to: address,
    ctx: &TxContext
)
```

**Requirements:**
- Caller must own the StakedSui object

##### `undelegate_voting_power`

Removes delegation and returns voting power to owner.

**Signature:**
```move
public entry fun undelegate_voting_power(
    staked_sui: &mut StakedSui,
    ctx: &TxContext
)
```

---

## Proposal Handler Module

### Module: `hybrid_governance_pkg::proposal_handler`

Executes different types of approved governance proposals.

#### Public Functions

##### `execute_approved_proposal`

Main entry point for executing approved proposals.

**Signature:**
```move
public entry fun execute_approved_proposal(
    _exec_cap: &ProposalExecutionCap,
    proposal: &Proposal,
    treasury_chest: &mut TreasuryChest,
    staking_system_state: &mut GovernanceSystemState,
    treasury_access_cap: &TreasuryAccessCap,
    treasury_admin_cap: &TreasuryAdminCap,
    staking_admin_cap: &StakingAdminCap,
    ctx: &mut TxContext
)
```

**Executes based on proposal type:**
- Type 0: General action (event only)
- Type 1/2: Parameter changes
- Type 3: Funding requests
- Type 4: Emergency actions

---

## Common Types and Structures

### Proposal

```move
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
```

### StakedSui

```move
struct StakedSui has key, store {
    id: UID,
    stake_amount: u64,
    stake_timestamp_ms: u64,
    delegated_to: Option<address>,
    reputation_score: u64,
}
```

### TreasuryChest

```move
struct TreasuryChest has key {
    id: UID,
    funds: Balance<SUI>,
    approvers: vector<address>,
    min_approvals_required: u64,
    max_approvers: u64,
    withdrawal_proposals: Table<u64, WithdrawalProposal>,
    next_withdrawal_proposal_id: u64,
}
```

---

## Error Codes

### Governance Module Errors

| Code | Name | Description |
|------|------|-------------|
| 1 | E_INSUFFICIENT_STAKE_FOR_VOTE | Voter has insufficient stake |
| 2 | E_QUORUM_NOT_MET | Proposal did not meet quorum |
| 3 | E_PROPOSAL_REJECTED | Proposal was rejected by voters |
| 4 | E_PROPOSAL_ALREADY_EXECUTED | Proposal has already been executed |
| 5 | E_INVALID_PROPOSAL_TYPE_FOR_VETO | Veto not allowed for this proposal type |
| 6 | E_VOTING_PERIOD_NOT_OVER | Voting period is still active |
| 7 | E_INVALID_PROPOSAL_TYPE | Invalid proposal type specified |
| 8 | E_VOTING_PERIOD_ALREADY_ENDED | Voting period has ended |
| 9 | E_VOTING_PERIOD_NOT_STARTED | Voting period has not started |
| 10 | E_INVALID_VOTING_DURATION | Invalid voting duration |
| 11 | E_ARITHMETIC_OVERFLOW | Arithmetic overflow occurred |
| 12 | E_MISSING_REQUIRED_DATA_FOR_PROPOSAL_TYPE | Missing required data for proposal type |
| 13 | E_DESCRIPTION_TOO_SHORT | Description is too short (< 10 bytes) |
| 14 | E_DESCRIPTION_TOO_LONG | Description is too long (> 10000 bytes) |
| 15 | E_INVALID_FUNDING_AMOUNT | Funding amount must be positive |
| 16 | E_INVALID_RECIPIENT_ADDRESS | Invalid recipient address |
| 17 | E_ZERO_TOTAL_STAKE | No stake in the system |

### Treasury Module Errors

| Code | Name | Description |
|------|------|-------------|
| 201 | E_INSUFFICIENT_FUNDS_IN_TREASURY | Treasury has insufficient funds |
| 202 | E_NOT_AN_APPROVER | Caller is not an authorized approver |
| 203 | E_ALREADY_APPROVED | Already approved this proposal |
| 204 | E_WITHDRAWAL_PROPOSAL_NOT_FOUND | Withdrawal proposal not found |
| 205 | E_NOT_ENOUGH_APPROVALS | Not enough approvals to execute |
| 206 | E_PROPOSAL_ALREADY_EXECUTED | Proposal already executed |
| 208 | E_AMOUNT_MUST_BE_POSITIVE | Amount must be positive |
| 209 | E_APPROVER_LIST_FULL | Approver list is full |
| 210 | E_APPROVER_ALREADY_EXISTS | Approver already exists |
| 211 | E_CANNOT_REMOVE_NON_EXISTENT_APPROVER | Cannot remove non-existent approver |
| 212 | E_UNAUTHORIZED_ADMIN_ACTION | Unauthorized admin action |
| 213 | E_INVALID_CONFIG_VALUE | Invalid configuration value |
| 214 | E_PROPOSER_MUST_BE_APPROVER | Proposer must be an approver |
| 215 | E_REASON_TOO_LONG | Reason exceeds 256 bytes |
| 216 | E_INVALID_MIN_APPROVALS | Invalid minimum approvals |
| 217 | E_ZERO_RECIPIENT_ADDRESS | Cannot send to zero address |
| 218 | E_AMOUNT_EXCEEDS_BALANCE | Amount exceeds treasury balance |

---

## Events

### Governance Events

#### ProposalCreated

```move
struct ProposalCreated has copy, drop {
    proposal_id: ID,
    creator: address,
    proposal_type: u8,
    description: String,
    quorum_percentage: u8,
    total_stake_at_creation: u128,
    end_time_ms: u64,
}
```

#### VoteCast

```move
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
```

#### ProposalExecuted

```move
struct ProposalExecuted has copy, drop {
    proposal_id: ID,
    executed_by: address,
}
```

### Treasury Events

#### FundsDeposited

```move
struct FundsDeposited has copy, drop {
    depositor: address,
    amount: u64,
    new_balance: u64,
}
```

#### DirectWithdrawalProposed

```move
struct DirectWithdrawalProposed has copy, drop {
    withdrawal_proposal_id: u64,
    proposer: address,
    recipient: address,
    amount: u64,
    reason: vector<u8>,
}
```

#### DirectWithdrawalExecuted

```move
struct DirectWithdrawalExecuted has copy, drop {
    withdrawal_proposal_id: u64,
    executor: address,
    recipient: address,
    amount: u64,
    remaining_balance: u64,
}
```

---

## Usage Examples

### Complete Governance Flow

```move
// 1. Stake SUI to get voting power
delegation_staking::stake_sui(&mut system_state, payment, &clock, ctx);

// 2. Submit a funding proposal
governance::submit_proposal(
    b"Fund developer program",
    3,
    option::some(5000000000),
    option::some(@recipient),
    option::none(),
    option::none(),
    option::none(),
    &system_state,
    &clock,
    ctx
);

// 3. Vote on the proposal
governance::hybrid_vote(
    &mut proposal,
    &staked_sui,
    true,
    false,
    &system_state,
    &clock,
    ctx
);

// 4. Execute approved proposal
governance::execute_proposal(
    &mut proposal,
    &exec_cap,
    &mut treasury_chest,
    &mut staking_system_state,
    &treasury_access_cap,
    &treasury_admin_cap,
    &staking_admin_cap,
    &clock,
    ctx
);
```

### Treasury Multi-Sig Flow

```move
// 1. Propose withdrawal
treasury::propose_direct_withdrawal(
    &mut treasury_chest,
    @recipient,
    1000000000,
    b"Emergency funds",
    ctx
);

// 2. Other approvers approve
treasury::approve_direct_withdrawal(
    &mut treasury_chest,
    proposal_id,
    ctx
);

// 3. Execute when threshold met
treasury::execute_direct_withdrawal(
    &mut treasury_chest,
    proposal_id,
    ctx
);
```

---

## Best Practices

### For Developers

1. **Always validate inputs** before calling functions
2. **Check capabilities** before attempting restricted operations
3. **Monitor events** for tracking system state
4. **Use proper error handling** for all edge cases
5. **Test thoroughly** with different scenarios

### For Users

1. **Review proposals carefully** before voting
2. **Verify transaction details** before signing
3. **Keep track of your stakes** and delegations
4. **Monitor treasury movements** for transparency
5. **Participate actively** to maintain reputation

### Security Considerations

1. **Protect capability objects** - they grant admin access
2. **Validate all addresses** before transactions
3. **Use multi-sig** for high-value operations
4. **Monitor for unusual activity** in governance
5. **Keep private keys secure** at all times

---

## Support and Resources

- **Documentation**: [README.md](README.md)
- **Security Policy**: [SECURITY.md](SECURITY.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **About**: [ABOUT.md](ABOUT.md)
- **GitHub Issues**: [Report bugs or request features](https://github.com/GizzZmo/Governance-System-Enhancement-Strategy/issues)

---

*Last Updated: October 2025*
