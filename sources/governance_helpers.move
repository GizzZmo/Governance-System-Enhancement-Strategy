// File: sources/governance_helpers.move
// Helper functions for common governance operations
module hybrid_governance_pkg::governance_helpers {
    use std::string::{Self, String};
    use std::option::{Self, Option, some, none};
    use sui::clock::{Self, Clock};
    use sui::object::ID;
    
    use crate::governance::{Self, Proposal};
    use crate::delegation_staking::{StakedSui, GovernanceSystemState};

    // === Constants for Helper Functions ===
    const SECONDS_PER_DAY: u64 = 86400000; // milliseconds

    // === Error Codes ===
    const E_INVALID_DURATION_DAYS: u64 = 100;

    /// Helper to check if a proposal is active (can be voted on)
    public fun is_proposal_active(proposal: &Proposal, clock: &Clock): bool {
        let now = clock::timestamp_ms(clock);
        governance::is_voting_period_active(proposal, now)
    }

    /// Helper to check if voting has ended
    public fun has_voting_ended(proposal: &Proposal, clock: &Clock): bool {
        let now = clock::timestamp_ms(clock);
        now > governance::get_end_time_ms(proposal)
    }

    /// Helper to get remaining voting time in days
    public fun get_remaining_voting_days(proposal: &Proposal, clock: &Clock): u64 {
        let now = clock::timestamp_ms(clock);
        let end_time = governance::get_end_time_ms(proposal);
        
        if (now >= end_time) {
            return 0
        };
        
        let remaining_ms = end_time - now;
        remaining_ms / SECONDS_PER_DAY
    }

    /// Helper to calculate voting power preview (without voting)
    public fun preview_voting_power(
        staked_sui: &StakedSui,
        system_state: &GovernanceSystemState,
        clock: &Clock
    ): (u128, u128, u128, u128) {
        governance::calculate_voting_power(
            staked_sui,
            system_state,
            clock
        )
    }

    /// Helper to check if proposal will meet quorum
    public fun will_meet_quorum(proposal: &Proposal): bool {
        governance::check_quorum(proposal)
    }

    /// Helper to get proposal status as string
    public fun get_proposal_status(proposal: &Proposal, clock: &Clock): String {
        let now = clock::timestamp_ms(clock);
        let start_time = governance::get_start_time_ms(proposal);
        let end_time = governance::get_end_time_ms(proposal);
        
        if (now < start_time) {
            string::utf8(b"Pending")
        } else if (now <= end_time) {
            string::utf8(b"Active")
        } else if (governance::is_executed(proposal)) {
            string::utf8(b"Executed")
        } else if (governance::check_quorum(proposal)) {
            if (governance::get_votes_for(proposal) > governance::get_votes_against(proposal)) {
                string::utf8(b"Succeeded")
            } else {
                string::utf8(b"Defeated")
            }
        } else {
            string::utf8(b"Failed - Quorum Not Met")
        }
    }

    /// Helper to validate proposal before submission
    public fun validate_proposal_params(
        description: &vector<u8>,
        proposal_type: u8,
        funding_amount_opt: &Option<u64>,
        funding_recipient_opt: &Option<address>,
        param_target_opt: &Option<vector<u8>>,
        param_name_opt: &Option<vector<u8>>,
        param_value_opt: &Option<vector<u8>>
    ): bool {
        use std::vector;
        use std::option::is_some;

        // Check description length
        let desc_len = vector::length(description);
        if (desc_len < 10 || desc_len > 10000) {
            return false
        };

        // Check proposal type
        if (proposal_type > 4) {
            return false
        };

        // Check required fields for funding proposals
        if (proposal_type == 3) {
            if (!is_some(funding_amount_opt) || !is_some(funding_recipient_opt)) {
                return false
            };
        };

        // Check required fields for parameter changes
        if (proposal_type == 1 || proposal_type == 2) {
            if (!is_some(param_target_opt) || !is_some(param_name_opt) || !is_some(param_value_opt)) {
                return false
            };
        };

        true
    }

    /// Helper to format voting power info as string
    public fun format_voting_power(
        base_votes: u128,
        time_bonus: u128,
        reputation_factor: u128,
        final_votes: u128
    ): String {
        // Format as: "Base: X, Time: Yx, Rep: Zx, Final: W"
        // This is a simplified version - in production, use proper formatting
        string::utf8(b"Voting power calculated")
    }
}
