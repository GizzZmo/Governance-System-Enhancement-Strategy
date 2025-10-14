# User Guide - Decentralized Governance System

## Introduction

Welcome to the Decentralized Governance System User Guide! This document will help you understand how to use the governance system effectively, whether you're a token holder, proposal creator, or community member.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Staking and Voting Power](#staking-and-voting-power)
3. [Creating Proposals](#creating-proposals)
4. [Voting on Proposals](#voting-on-proposals)
5. [Treasury Management](#treasury-management)
6. [Delegation](#delegation)
7. [Best Practices](#best-practices)
8. [FAQ](#faq)
9. [Troubleshooting](#troubleshooting)

---

## Getting Started

### Prerequisites

Before you can participate in governance, you'll need:

1. **Sui Wallet**: Install a compatible Sui wallet (e.g., Sui Wallet browser extension)
2. **SUI Tokens**: Acquire SUI tokens for staking and gas fees
3. **System Access**: Connect to the governance system through a supported interface

### Initial Setup

1. **Connect Your Wallet**
   ```
   - Open your Sui wallet
   - Navigate to the governance dApp
   - Click "Connect Wallet"
   - Approve the connection
   ```

2. **Verify Your Balance**
   - Ensure you have enough SUI for:
     - Staking (to gain voting power)
     - Gas fees for transactions

3. **Understand Gas Costs**
   - Staking: ~0.001 SUI
   - Voting: ~0.001 SUI
   - Creating Proposal: ~0.002 SUI
   - Treasury Operations: ~0.002 SUI

---

## Staking and Voting Power

### Why Stake?

Staking SUI tokens gives you:
- **Voting Power**: Participate in governance decisions
- **Time Bonuses**: Additional voting weight for long-term commitment
- **Reputation**: Build reputation through active participation

### How to Stake

1. **Minimum Requirements**
   - Check the minimum stake amount (set by system parameters)
   - Ensure you have SUI tokens + gas fees

2. **Staking Process**
   ```
   Step 1: Navigate to "Stake" section
   Step 2: Enter amount to stake
   Step 3: Review transaction details
   Step 4: Confirm and sign transaction
   Step 5: Receive StakedSui NFT object
   ```

3. **What Happens When You Stake**
   - Your SUI is locked in the staking contract
   - You receive a StakedSui object (proof of stake)
   - Your voting power is calculated
   - Timestamp is recorded for time-weighting

### Voting Power Calculation

Your voting power is calculated using a hybrid mechanism:

**Base Votes (Quadratic)**
```
Base Votes = √(Stake Amount)
```
This prevents whale dominance - doubling your stake doesn't double your votes.

**Time Bonus (Up to 5x)**
```
Time Multiplier = min(1 + (stake_duration / reference_period), 5)
```
Rewards long-term commitment with up to 5x bonus.

**Reputation Weight**
```
Total Votes = (Base Votes × Time Multiplier) × Reputation Factor
```
Active participation increases your reputation score.

### Example Voting Power

| Stake Amount | Duration | Reputation | Base Votes | Time Bonus | Final Votes |
|--------------|----------|------------|------------|------------|-------------|
| 100 SUI      | 1 month  | 1.0x       | 10         | 1.5x       | 15          |
| 100 SUI      | 6 months | 1.2x       | 10         | 3.0x       | 36          |
| 400 SUI      | 1 month  | 1.0x       | 20         | 1.5x       | 30          |
| 400 SUI      | 6 months | 1.2x       | 20         | 3.0x       | 72          |

### Unstaking

1. **How to Unstake**
   ```
   Step 1: Navigate to "Unstake" section
   Step 2: Select your StakedSui object
   Step 3: Confirm unstaking
   Step 4: Wait for cooldown period (if any)
   Step 5: Receive your SUI tokens back
   ```

2. **Important Notes**
   - You may lose time bonuses upon unstaking
   - Some systems have a cooldown period
   - Ensure no active votes before unstaking

---

## Creating Proposals

### Proposal Types

The system supports five types of proposals:

#### 1. General Proposal (Type 0)
- **Use For**: Community initiatives, discussions, decisions
- **Quorum**: 20%
- **Voting Period**: 7 days
- **Veto**: Not available
- **Example**: "Should we organize a community hackathon?"

#### 2. Minor Parameter Change (Type 1)
- **Use For**: Non-critical system adjustments
- **Quorum**: 25%
- **Voting Period**: 7 days
- **Veto**: Not available
- **Example**: "Adjust voting period to 5 days"

#### 3. Critical Parameter Change (Type 2)
- **Use For**: Core system changes
- **Quorum**: 30%
- **Voting Period**: 14 days
- **Veto**: Available
- **Example**: "Change minimum stake requirement"

#### 4. Funding Request (Type 3)
- **Use For**: Treasury fund allocation
- **Quorum**: 25%
- **Voting Period**: 7 days
- **Veto**: Not available
- **Example**: "Allocate 1000 SUI for development"

#### 5. Emergency Action (Type 4)
- **Use For**: Urgent matters
- **Quorum**: 30%
- **Voting Period**: 24 hours
- **Veto**: Available
- **Example**: "Emergency security patch"

### Creating a Proposal

#### Step 1: Choose Proposal Type

Select the appropriate type based on your needs:
- General matters → Type 0
- Minor changes → Type 1
- Critical changes → Type 2
- Funding → Type 3
- Emergency → Type 4

#### Step 2: Prepare Your Proposal

**Description Requirements:**
- Minimum: 10 characters
- Maximum: 10,000 characters
- Should be clear and comprehensive

**Description Template:**
```
Title: [Clear, concise title]

Summary: [1-2 sentence summary]

Background: [Why is this needed?]

Proposal Details: [What exactly is being proposed?]

Expected Outcomes: [What will happen if approved?]

Budget (if applicable): [Amount and justification]

Timeline: [Implementation timeline]

References: [Any supporting links or documents]
```

#### Step 3: Fill Required Fields

**For Funding Proposals (Type 3):**
- Funding Amount (must be > 0)
- Recipient Address

**For Parameter Changes (Types 1, 2):**
- Target Module Name
- Parameter Name
- New Value (BCS encoded)

#### Step 4: Submit Proposal

```
1. Navigate to "Create Proposal"
2. Select proposal type
3. Enter description
4. Fill required fields
5. Review all details
6. Submit and sign transaction
7. Share proposal ID with community
```

#### Step 5: Promote Your Proposal

- Share on community channels
- Provide context and reasoning
- Answer questions from voters
- Update based on feedback (if needed)

---

## Voting on Proposals

### Before You Vote

1. **Review the Proposal**
   - Read the full description
   - Understand the implications
   - Check the proposal type and parameters
   - Review community discussion

2. **Check Your Voting Power**
   - Ensure you have staked SUI
   - Verify your current voting power
   - Consider time bonuses

3. **Understand Voting Options**
   - **Support (Yes)**: Vote in favor
   - **Against (No)**: Vote against
   - **Veto**: Special rejection for critical proposals

### How to Vote

#### Standard Vote

```
Step 1: Navigate to active proposals
Step 2: Select a proposal to review
Step 3: Click "Vote"
Step 4: Choose: Support or Against
Step 5: Select your StakedSui object
Step 6: Confirm and sign transaction
```

#### Veto Vote (Critical Proposals Only)

```
Step 1: Navigate to critical proposal
Step 2: Review veto implications
Step 3: Click "Veto"
Step 4: Select your StakedSui object
Step 5: Confirm veto and sign
```

**Veto Rules:**
- Only available for Type 2 (Critical) and Type 4 (Emergency) proposals
- Requires significant stake
- Provides extra protection for critical changes

### Voting Strategy Tips

1. **Vote Early**: Get maximum time bonus if implemented
2. **Research Thoroughly**: Understand the proposal impact
3. **Engage in Discussion**: Ask questions, share concerns
4. **Consider Long-term**: Think about system sustainability
5. **Track Outcomes**: Monitor executed proposals

### Changing Your Vote

⚠️ **Note**: Most governance systems don't allow vote changes. Vote carefully!

---

## Treasury Management

### Understanding the Treasury

The treasury holds community funds managed through:
- **Governance Proposals**: Main funding mechanism
- **Multi-Sig Direct Withdrawals**: Emergency access with multiple approvals

### Depositing to Treasury

Anyone can deposit funds:

```
Step 1: Navigate to "Treasury"
Step 2: Click "Deposit"
Step 3: Enter SUI amount
Step 4: Confirm and sign transaction
```

### Governance-Based Withdrawals

1. **Create Funding Proposal** (Type 3)
   - Submit proposal with amount and recipient
   - Community votes on allocation
   - Automatic execution if approved

2. **Approval Process**
   - Voting period: 7 days
   - Quorum required: 25%
   - Must have more votes for than against

3. **Automatic Execution**
   - Funds transferred to recipient
   - Event emitted for transparency
   - Treasury balance updated

### Multi-Sig Withdrawals (Approvers Only)

If you're an authorized approver:

#### Propose Withdrawal
```
Step 1: Navigate to "Multi-Sig Withdrawals"
Step 2: Click "Propose Withdrawal"
Step 3: Enter:
   - Recipient address
   - Amount
   - Reason (max 256 chars)
Step 4: Submit (auto-approved by you)
```

#### Approve Others' Proposals
```
Step 1: View pending withdrawals
Step 2: Review proposal details
Step 3: Click "Approve"
Step 4: Sign transaction
```

#### Execute When Threshold Met
```
Step 1: Check approval count
Step 2: If threshold met, click "Execute"
Step 3: Funds transferred automatically
```

**Multi-Sig Requirements:**
- Minimum approvals set by admin
- Each approver can approve once
- Proposer auto-approves
- Cannot exceed treasury balance

---

## Delegation

### What is Delegation?

Delegation allows you to:
- Assign your voting power to a trusted delegate
- Maintain token ownership
- Participate passively in governance

### When to Delegate

Consider delegation if you:
- Don't have time to review all proposals
- Trust someone else's judgment
- Want to participate but lack expertise
- Are going on hiatus

### How to Delegate

```
Step 1: Navigate to "Delegate"
Step 2: Select your StakedSui object
Step 3: Enter delegate address
Step 4: Confirm and sign transaction
```

### Important Notes

- **You keep your tokens**: Delegation doesn't transfer ownership
- **Revocable**: You can undelegate anytime
- **No rewards split**: Delegates don't automatically get rewards
- **Trust required**: Choose delegates carefully

### Undelegating

```
Step 1: Navigate to "Delegate"
Step 2: Select delegated StakedSui
Step 3: Click "Undelegate"
Step 4: Confirm and sign
Step 5: Voting power returns to you
```

### Finding Good Delegates

Look for delegates who:
- Have strong track record
- Align with your values
- Are active in governance
- Explain their votes
- Are responsive to community

---

## Best Practices

### Security

1. **Protect Your Keys**
   - Never share private keys
   - Use hardware wallet for large stakes
   - Verify all transactions before signing

2. **Verify Addresses**
   - Double-check recipient addresses
   - Verify contract addresses
   - Be cautious of phishing

3. **Monitor Activity**
   - Track your stakes and votes
   - Watch treasury movements
   - Set up event notifications

### Governance Participation

1. **Stay Informed**
   - Follow community channels
   - Read proposal discussions
   - Understand system updates

2. **Vote Responsibly**
   - Research before voting
   - Consider long-term impact
   - Participate consistently

3. **Engage Constructively**
   - Provide thoughtful feedback
   - Ask clarifying questions
   - Share expertise when relevant

### Treasury Interaction

1. **Funding Proposals**
   - Justify budget clearly
   - Provide implementation plan
   - Include accountability measures

2. **Multi-Sig Operations**
   - Only for authorized approvers
   - Provide clear reasons
   - Act in community interest

---

## FAQ

### General Questions

**Q: How much SUI do I need to participate?**
A: Minimum stake varies by system parameters. Check current requirements in the governance dashboard.

**Q: Can I lose my staked SUI?**
A: No. Staking locks your SUI but doesn't risk loss (barring smart contract bugs - use audited systems).

**Q: How long does voting last?**
A: Varies by proposal type:
- General: 7 days
- Parameters: 7-14 days
- Emergency: 24 hours

**Q: What happens if quorum isn't met?**
A: Proposal fails and cannot be executed.

### Voting Questions

**Q: Can I vote on multiple proposals?**
A: Yes, you can vote on all active proposals.

**Q: Can I use the same stake for multiple votes?**
A: Yes, your staked SUI can vote on multiple proposals.

**Q: What if I disagree with a passed proposal?**
A: You can create a new proposal to reverse it, if appropriate.

**Q: How is voting power calculated?**
A: Quadratic (√stake) × Time Bonus × Reputation

### Treasury Questions

**Q: Who controls the treasury?**
A: Governance (via proposals) and multi-sig approvers (for direct withdrawals).

**Q: Can anyone deposit to the treasury?**
A: Yes, anyone can deposit SUI tokens.

**Q: How are funds protected?**
A: Multiple layers: governance voting, multi-sig, capability-based access control.

### Technical Questions

**Q: What blockchain is this on?**
A: Sui blockchain using Move language.

**Q: Are smart contracts audited?**
A: Check SECURITY.md for audit status. Only use audited versions for mainnet.

**Q: Can I integrate this with my dApp?**
A: Yes, see API_DOCUMENTATION.md for integration details.

---

## Troubleshooting

### Common Issues

#### "Insufficient Stake for Vote"
**Cause**: Your stake is below minimum
**Solution**: Stake more SUI or check minimum requirements

#### "Voting Period Already Ended"
**Cause**: Trying to vote after deadline
**Solution**: Wait for next proposal or create a new one

#### "Proposal Already Executed"
**Cause**: Proposal has been executed
**Solution**: Cannot vote on executed proposals

#### "Not an Approver"
**Cause**: Trying multi-sig operation without authorization
**Solution**: Contact admin or use governance proposals

#### "Insufficient Funds in Treasury"
**Cause**: Treasury balance too low
**Solution**: Wait for deposits or adjust proposal amount

### Getting Help

1. **Documentation**
   - Review [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
   - Check [SECURITY.md](SECURITY.md)
   - Read [ABOUT.md](ABOUT.md)

2. **Community Support**
   - GitHub Discussions
   - Discord channel
   - Twitter/X community

3. **Technical Issues**
   - Open GitHub issue
   - Contact via email
   - Check existing issues

### Error Code Reference

See [API_DOCUMENTATION.md#error-codes](API_DOCUMENTATION.md#error-codes) for complete error code reference.

---

## Advanced Topics

### Reputation System

Build reputation by:
- Consistent voting
- Quality proposals
- Community engagement
- Long-term staking

Benefits:
- Increased voting weight
- Community trust
- Potential future rewards

### Quadratic Voting Deep Dive

**Why Quadratic?**
- Prevents plutocracy
- Encourages broad participation
- Balances large and small holders

**How It Works:**
- Linear cost: 100 SUI = 10 votes
- Not linear benefit: Need 400 SUI for 20 votes
- Diminishing returns on large stakes

### Time-Weighting Mechanics

**Formula:**
```
bonus = stake_duration / reference_period
time_multiplier = min(1 + bonus, MAX_BONUS)
```

**Example:**
- Reference period: 180 days
- Your stake: 90 days
- Bonus: 0.5 (90/180)
- Multiplier: 1.5x

---

## Conclusion

The Decentralized Governance System empowers communities to make collective decisions fairly and transparently. By understanding staking, voting, and treasury management, you can effectively participate in shaping the future of your DAO or protocol.

### Next Steps

1. **Stake Your SUI**: Get voting power
2. **Review Proposals**: Understand current votes
3. **Cast Your Vote**: Participate in governance
4. **Create Proposals**: Shape the future
5. **Stay Engaged**: Monitor and contribute

### Resources

- **Quick Start**: [README.md](README.md)
- **API Reference**: [API_DOCUMENTATION.md](API_DOCUMENTATION.md)
- **Security**: [SECURITY.md](SECURITY.md)
- **About**: [ABOUT.md](ABOUT.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)

---

**Happy Governing! 🗳️**

*Last Updated: October 2025*
