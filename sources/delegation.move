// File: sources/delegation.move
// Enhanced with EbA governance principles: participation accessibility tracking
module hybrid_governance_pkg::delegation {
    use sui::tx_context::{Self, TxContext, sender};
    use sui::object::{Self, ID, UID, new, uid_to_inner};
    use sui::event;
    use std::option::{Self, Option, some, none, is_some, destroy_some};
    use std::vector;

    /// Each delegator can delegate to one delegatee.
    struct Delegation has key, store {
        id: ID,
        delegator: address,
        delegatee: address,
    }

    /// Global book of all delegations
    struct DelegationBook has key, store {
        id: ID,
        delegations: vector<Delegation>,
    }

    // === Events for EbA Governance Tracking ===
    
    /// Emitted when a delegation is created or updated
    struct DelegationCreated has copy, drop {
        delegator: address,
        delegatee: address,
        timestamp: u64,
    }

    /// Emitted when a delegation is removed
    struct DelegationRemoved has copy, drop {
        delegator: address,
        former_delegatee: address,
        timestamp: u64,
    }

    /// Emitted to track participation accessibility
    struct ParticipationAccessibilityEvent has copy, drop {
        total_delegations: u64,
        event_type: u8, // 0=created, 1=removed
    }

    // === Error Codes ===
    const E_SELF_DELEGATION: u64 = 100;
    const E_DELEGATION_CYCLE: u64 = 101;

    /// Initialize the delegation book (should only be called once, by admin)
    public entry fun init_delegation_book(ctx: &TxContext): DelegationBook {
        let book_id = uid_to_inner(&new(ctx));
        DelegationBook { id: book_id, delegations: vector::empty<Delegation>() }
    }

    /// Set or update a delegation.
    /// Prevents self-delegation and cycles.
    /// Enhanced with event emissions for EbA tracking
    public entry fun set_delegate(
        book: &mut DelegationBook,
        delegatee: address,
        ctx: &TxContext
    ) {
        let delegator = sender(ctx);
        assert!(delegator != delegatee, E_SELF_DELEGATION);
        
        // Prevent cycles by resolving the chain
        let mut current = delegatee;
        let mut steps = 0u8;
        while (steps < 16) { // Arbitrary max depth
            match find_delegate_raw(book, current) {
                some(d) => {
                    if (d.delegatee == delegator) {
                        abort E_DELEGATION_CYCLE; // Cycle found
                    };
                    current = d.delegatee;
                },
                none => break,
            };
            steps = steps + 1;
        };

        // Check if updating existing delegation
        let mut was_update = false;
        let mut former_delegatee = delegatee; // Default to same if new

        // Remove any existing delegation by delegator
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            if (vector::borrow(&book.delegations, i).delegator == delegator) {
                former_delegatee = vector::borrow(&book.delegations, i).delegatee;
                vector::remove(&mut book.delegations, i);
                was_update = true;
                break;
            };
            i = i + 1;
        };

        let id = uid_to_inner(&new(ctx));
        let new_del = Delegation { id, delegator, delegatee };
        vector::push_back(&mut book.delegations, new_del);

        // Emit events for tracking
        event::emit(DelegationCreated {
            delegator,
            delegatee,
            timestamp: 0, // Would use clock in production
        });

        // Track participation accessibility (delegation enables participation)
        event::emit(ParticipationAccessibilityEvent {
            total_delegations: vector::length(&book.delegations),
            event_type: 0, // Created
        });
    }

    /// Remove delegation (undelegate)
    /// Enhanced with event emissions for EbA tracking
    public entry fun clear_delegate(
        book: &mut DelegationBook,
        ctx: &TxContext
    ) {
        let delegator = sender(ctx);
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            if (vector::borrow(&book.delegations, i).delegator == delegator) {
                let former_delegatee = vector::borrow(&book.delegations, i).delegatee;
                vector::remove(&mut book.delegations, i);
                
                // Emit events for tracking
                event::emit(DelegationRemoved {
                    delegator,
                    former_delegatee,
                    timestamp: 0, // Would use clock in production
                });

                event::emit(ParticipationAccessibilityEvent {
                    total_delegations: vector::length(&book.delegations),
                    event_type: 1, // Removed
                });
                
                return;
            };
            i = i + 1;
        };
    }

    /// Find the direct delegatee for a given address.
    public fun get_delegate(book: &DelegationBook, delegator: address): Option<address> {
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            let del = vector::borrow(&book.delegations, i);
            if (del.delegator == delegator) return some(del.delegatee);
            i = i + 1;
        };
        none()
    }

    /// Get total number of active delegations (EbA metric: participation accessibility)
    public fun get_total_delegations(book: &DelegationBook): u64 {
        vector::length(&book.delegations)
    }

    /// Check if an address is a delegate (has delegators)
    public fun is_delegate(book: &DelegationBook, potential_delegate: address): bool {
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            let del = vector::borrow(&book.delegations, i);
            if (del.delegatee == potential_delegate) return true;
            i = i + 1;
        };
        false
    }

    /// Count how many delegators a delegate has
    public fun count_delegators(book: &DelegationBook, delegate: address): u64 {
        let mut count = 0;
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            let del = vector::borrow(&book.delegations, i);
            if (del.delegatee == delegate) count = count + 1;
            i = i + 1;
        };
        count
    }

    /// Internal: Find the Delegation record for an address.
    fun find_delegate_raw(book: &DelegationBook, delegator: address): Option<&Delegation> {
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            let del = vector::borrow(&book.delegations, i);
            if (del.delegator == delegator) return some(del);
            i = i + 1;
        };
        none()
    }

    /// Recursively resolve voting power for an address, summing all addresses that delegate to it (including itself if not delegated away)
    /// `get_voting_power(book, who, base_power_fn)`
    /// base_power_fn: fun(address) -> u128
    public fun get_voting_power(
        book: &DelegationBook,
        who: address,
        base_power_fn: &fn(address): u128
    ): u128 {
        // If this address delegated away, power is 0
        if (is_some(&get_delegate(book, who))) return 0;

        let mut total = base_power_fn(who);
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            let del = vector::borrow(&book.delegations, i);
            if (del.delegatee == who) {
                total = total + get_voting_power(book, del.delegator, base_power_fn);
            };
            i = i + 1;
        };
        total
    }
}
