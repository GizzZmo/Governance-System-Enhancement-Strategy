// File: sources/delegation.move
module hybrid_governance_pkg::delegation {
    use sui::tx_context::{Self, TxContext, sender};
    use sui::object::{Self, ID, UID, new, uid_to_inner};
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

    /// Initialize the delegation book (should only be called once, by admin)
    public entry fun init_delegation_book(ctx: &TxContext): DelegationBook {
        let book_id = uid_to_inner(&new(ctx));
        DelegationBook { id: book_id, delegations: vector::empty<Delegation>() }
    }

    /// Set or update a delegation.
    /// Prevents self-delegation and cycles.
    public entry fun set_delegate(
        book: &mut DelegationBook,
        delegatee: address,
        ctx: &TxContext
    ) {
        let delegator = sender(ctx);
        assert!(delegator != delegatee, 100, "Cannot delegate to self");
        // Prevent cycles by resolving the chain
        let mut current = delegatee;
        let mut steps = 0u8;
        while (steps < 16) { // Arbitrary max depth
            match find_delegate_raw(book, current) {
                some(d) => {
                    if (d.delegatee == delegator) {
                        abort 101; // Cycle found
                    };
                    current = d.delegatee;
                },
                none => break,
            };
            steps = steps + 1;
        };

        // Remove any existing delegation by delegator
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            if (vector::borrow(&book.delegations, i).delegator == delegator) {
                vector::remove(&mut book.delegations, i);
                break;
            };
            i = i + 1;
        };
        let id = uid_to_inner(&new(ctx));
        let new_del = Delegation { id, delegator, delegatee };
        vector::push_back(&mut book.delegations, new_del);
    }

    /// Remove delegation (undelegate)
    public entry fun clear_delegate(
        book: &mut DelegationBook,
        ctx: &TxContext
    ) {
        let delegator = sender(ctx);
        let mut i = 0;
        while (i < vector::length(&book.delegations)) {
            if (vector::borrow(&book.delegations, i).delegator == delegator) {
                vector::remove(&mut book.delegations, i);
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
