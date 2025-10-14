# Quick Start Guide

## Get Started in 5 Minutes

This guide will help you get up and running with the Decentralized Governance System quickly.

## Prerequisites

- Sui CLI installed
- SUI tokens in your wallet
- Basic understanding of blockchain concepts

## Step 1: Clone and Build

```bash
# Clone the repository
git clone https://github.com/GizzZmo/Governance-System-Enhancement-Strategy.git
cd Governance-System-Enhancement-Strategy

# Build the project
sui move build
```

## Step 2: Run Tests

```bash
# Run all tests
sui move test

# Run specific test module
sui move test governance_tests
```

## Step 3: Deploy (Testnet)

```bash
# Deploy to testnet
sui client publish --gas-budget 300000000

# Save the package ID from the output
export PACKAGE_ID=<your-package-id>
```

## Step 4: Initialize System

After deployment, you'll receive several capability objects. Save these IDs:

```bash
export SYSTEM_STATE_ID=<GovernanceSystemState-object-id>
export TREASURY_ID=<TreasuryChest-object-id>
export TREASURY_ACCESS_CAP=<TreasuryAccessCap-object-id>
export TREASURY_ADMIN_CAP=<TreasuryAdminCap-object-id>
export STAKING_ADMIN_CAP=<StakingAdminCap-object-id>
```

## Step 5: Stake SUI

```bash
# Stake 100 SUI to get voting power
sui client call \
  --package $PACKAGE_ID \
  --module delegation_staking \
  --function stake_sui \
  --gas-budget 10000000 \
  --args $SYSTEM_STATE_ID 100000000000
```

You'll receive a `StakedSui` object. Save its ID:
```bash
export STAKED_SUI_ID=<your-staked-sui-id>
```

## Step 6: Create Your First Proposal

### General Proposal
```bash
sui client call \
  --package $PACKAGE_ID \
  --module governance \
  --function submit_proposal \
  --gas-budget 20000000 \
  --args \
    "Should we organize a community hackathon?" \
    0
```

### Funding Proposal
```bash
sui client call \
  --package $PACKAGE_ID \
  --module governance \
  --function submit_proposal \
  --gas-budget 20000000 \
  --args \
    "Fund developer program" \
    3 \
    5000000000 \
    <recipient-address>
```

Save the proposal ID from the output:
```bash
export PROPOSAL_ID=<your-proposal-id>
```

## Step 7: Vote on a Proposal

```bash
sui client call \
  --package $PACKAGE_ID \
  --module governance \
  --function hybrid_vote \
  --gas-budget 10000000 \
  --args \
    $PROPOSAL_ID \
    $STAKED_SUI_ID \
    true \
    false \
    $SYSTEM_STATE_ID
```

## Step 8: Execute Approved Proposal

Wait for voting period to end, then execute:

```bash
sui client call \
  --package $PACKAGE_ID \
  --module governance \
  --function execute_proposal \
  --gas-budget 30000000 \
  --args $PROPOSAL_ID
```

## Interactive CLI (Recommended)

For easier interaction, use our interactive script:

```bash
# Set your package ID
export PACKAGE_ID=<your-package-id>

# Run interactive CLI
./scripts/interact.sh
```

The interactive CLI provides a menu-driven interface for:
- Staking SUI
- Creating proposals
- Voting
- Viewing status
- Treasury operations
- Delegation

## Common Operations

### Check Proposal Status

```bash
sui client object $PROPOSAL_ID
```

### View Treasury Balance

```bash
sui client object $TREASURY_ID
```

### Deposit to Treasury

```bash
sui client call \
  --package $PACKAGE_ID \
  --module treasury \
  --function deposit_funds \
  --gas-budget 10000000 \
  --args $TREASURY_ID 1000000000
```

### Delegate Voting Power

```bash
sui client call \
  --package $PACKAGE_ID \
  --module delegation_staking \
  --function delegate_voting_power \
  --gas-budget 10000000 \
  --args $STAKED_SUI_ID <delegate-address>
```

### Undelegate Voting Power

```bash
sui client call \
  --package $PACKAGE_ID \
  --module delegation_staking \
  --function undelegate_voting_power \
  --gas-budget 10000000 \
  --args $STAKED_SUI_ID
```

## Understanding Voting Power

Your voting power is calculated as:

1. **Base Votes**: √(stake amount)
2. **Time Bonus**: Up to 5x for long-term staking
3. **Reputation**: Additional weight for active participation

Example:
- Stake: 100 SUI
- Duration: 6 months
- Base votes: 10 (√100)
- Time bonus: 3x
- Final votes: 30

## Proposal Types

| Type | Name | Quorum | Duration | Veto |
|------|------|--------|----------|------|
| 0 | General | 20% | 7 days | No |
| 1 | Minor Param | 25% | 7 days | No |
| 2 | Critical Param | 30% | 14 days | Yes |
| 3 | Funding | 25% | 7 days | No |
| 4 | Emergency | 30% | 24 hours | Yes |

## Gas Budget Guidelines

| Operation | Recommended Gas Budget |
|-----------|----------------------|
| Stake | 10,000,000 |
| Create Proposal | 20,000,000 |
| Vote | 10,000,000 |
| Execute | 30,000,000 |
| Treasury Ops | 10,000,000 |

## Troubleshooting

### "Insufficient Stake for Vote"
- Ensure you have staked SUI
- Check minimum stake requirement

### "Voting Period Already Ended"
- Proposal voting has closed
- Check proposal status with `sui client object`

### "Not an Approver"
- Multi-sig operations require approver status
- Use governance proposals instead

### Gas Errors
- Increase gas budget
- Check your SUI balance

## Next Steps

1. **Read the Full Documentation**
   - [USER_GUIDE.md](USER_GUIDE.md) - Comprehensive user guide
   - [API_DOCUMENTATION.md](API_DOCUMENTATION.md) - API reference
   - [SECURITY.md](SECURITY.md) - Security best practices

2. **Join the Community**
   - GitHub Discussions
   - Discord: https://discord.gg/Dy5Epsyc
   - Twitter: @Jon_Arve

3. **Contribute**
   - Report bugs
   - Suggest features
   - Submit PRs
   - Improve docs

## Example Workflow

Here's a complete governance workflow:

```bash
# 1. Setup
export PACKAGE_ID=<package-id>
export SYSTEM_STATE_ID=<system-state-id>

# 2. Stake
sui client call --package $PACKAGE_ID --module delegation_staking \
  --function stake_sui --gas-budget 10000000 \
  --args $SYSTEM_STATE_ID 100000000000

# 3. Create proposal
sui client call --package $PACKAGE_ID --module governance \
  --function submit_proposal --gas-budget 20000000 \
  --args "Fund community event" 3 5000000000 <recipient>

# 4. Vote
sui client call --package $PACKAGE_ID --module governance \
  --function hybrid_vote --gas-budget 10000000 \
  --args <proposal-id> <staked-sui-id> true false $SYSTEM_STATE_ID

# 5. Wait for voting period

# 6. Execute
sui client call --package $PACKAGE_ID --module governance \
  --function execute_proposal --gas-budget 30000000 \
  --args <proposal-id> ...
```

## Resources

- **Documentation**: See `/docs` folder
- **Examples**: See `/examples` folder (if available)
- **Tests**: See test files for usage examples
- **Scripts**: See `/scripts` folder for utilities

## Getting Help

- **Documentation**: Start with [README.md](README.md)
- **Issues**: [GitHub Issues](https://github.com/GizzZmo/Governance-System-Enhancement-Strategy/issues)
- **Security**: jonovesen@gmail.com
- **Community**: Discord and Twitter

---

**Ready to govern? Let's build the decentralized future together! 🚀**
