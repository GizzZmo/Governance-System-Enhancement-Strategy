// File: sources/delegation_staking.move
// Module for managing validator registration, staking, delegation, and reputation.

module hybrid_governance::delegation_staking {
    use std::signer;
    use std::option::{Self, Option, some, none};
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, zero, join, split, value};
    use sui::sui::SUI; // Assuming SUI is the staking token, replace if custom
    use sui::object::{Self, ID, UID, new};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};

    // === Constants ===
    const MIN_VALIDATOR_STAKE: u64 = 1_000_000_000; // Example: 1 SUI (assuming SUI has 9 decimals)
    const INITIAL_REPUTATION: u128 = 100;

    // === Structs ===

    /// Information about a registered validator
    struct Validator has key, store {
        id: UID,
        owner: address,
        total_stake_pool: Balance<SUI>, // Pool of all stake delegated to this validator
        reputation: u128,
        metadata_url: vector<u8>,
        is_active: bool,
    }

    /// Represents a user's staked SUI tokens. This object is owned by the user.
    /// It can be delegated to a validator or remain undelegated for direct voting power.
    struct StakedSui has key, store {
        id: UID,
        // owner: address, // Owner is implicit by who holds the object
        amount: Balance<SUI>,
        delegated_to_validator_id: Option<ID>, // ID of the Validator object
        reputation_score: u128, // User's individual reputation
        // unbonding_start_epoch: Option<u64>, // For unstaking lockups based on epochs
    }

    /// Shared object to store total staked SUI in the system.
    /// Crucial for quorum calculations in the governance module.
    struct GovernanceSystemState has key {
        id: UID,
        total_staked_amount: Balance<SUI>,
        // Could also hold other system-wide params like min_validator_stake if configurable
    }

    // === Errors ===
    const E_INSUFFICIENT_STAKE_FOR_VALIDATOR: u64 = 101;
    const E_VALIDATOR_ALREADY_EXISTS: u64 = 102; // Needs a registry to check this properly
    const E_VALIDATOR_NOT_FOUND: u64 = 103;
    const E_INSUFFICIENT_BALANCE_TO_STAKE: u64 = 104;
    const E_NOT_ENOUGH_STAKED_TO_UNDELEGATE: u64 = 105; // Should not happen if amounts match
    const E_ALREADY_DELEGATED: u64 = 106;
    const E_NOT_DELEGATED_TO_THIS_VALIDATOR: u64 = 107;
    const E_STAKED_SUI_OBJECT_NOT_OWNED_BY_SENDER: u64 = 108;
    const E_VALIDATOR_INACTIVE: u64 = 109;
    const E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW: u64 = 110;
    const E_STAKE_AMOUNT_MUST_BE_POSITIVE: u64 = 111;
    const E_SYSTEM_STATE_NOT_FOUND: u64 = 112; // Should not happen after init

    // === Init ===
    // This function is called once when the module is published.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceSystemState {
            id: object::new(ctx),
            total_staked_amount: balance::zero(),
        });
    }

    // === Public Entry Functions ===

    /// Registers the sender as a validator.
    /// The sender must provide an initial `self_stake_coin` meeting `MIN_VALIDATOR_STAKE`.
    public entry fun register_validator(
        system_state: &mut GovernanceSystemState, // Pass the shared system state
        self_stake_coin: Coin<SUI>,
        metadata_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let validator_owner = sender(ctx);
        let stake_value = coin::value(&self_stake_coin);
        assert!(stake_value >= MIN_VALIDATOR_STAKE, E_INSUFFICIENT_STAKE_FOR_VALIDATOR);

        // In a full system, check if validator_owner already has a Validator object.
        // This might involve a separate ValidatorRegistry object.

        let validator_stake_pool = coin::into_balance(self_stake_coin);

        // Create and share the Validator object
        let validator = Validator {
            id: object::new(ctx),
            owner: validator_owner,
            total_stake_pool: validator_stake_pool, // Initially contains their self-stake
            reputation: INITIAL_REPUTATION,
            metadata_url,
            is_active: true,
        };
        transfer::share_object(validator);

        // Update total system stake
        balance::join(&mut system_state.total_staked_amount, balance::copy(&validator.total_stake_pool));
        // Event: ValidatorRegistered { validator_id: object::id(&validator), owner: validator_owner, initial_stake: stake_value }
    }

    /// Creates a `StakedSui` object owned by the sender, representing their staked tokens.
    public entry fun stake_sui(
        system_state: &mut GovernanceSystemState, // Pass the shared system state
        coins_to_stake: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx);
        let stake_amount = coin::value(&coins_to_stake);
        assert!(stake_amount > 0, E_STAKE_AMOUNT_MUST_BE_POSITIVE);

        let staked_sui_balance = coin::into_balance(coins_to_stake);

        let staked_sui_obj = StakedSui {
            id: object::new(ctx),
            amount: staked_sui_balance,
            delegated_to_validator_id: option::none(),
            reputation_score: INITIAL_REPUTATION, // Or fetch existing reputation if staker already has one
        };
        transfer::transfer(staked_sui_obj, staker); // Sender owns their StakedSui object

        // Update total system stake
        balance::join(&mut system_state.total_staked_amount, balance::copy(&staked_sui_obj.amount));
        // Event: SuiStaked { staker, amount: stake_amount, staked_sui_id: object::id(&staked_sui_obj) }
    }

    /// Delegates the sender's `StakedSui` object to a chosen `Validator`.
    public entry fun delegate_sui(
        staked_sui_obj: &mut StakedSui,
        validator: &mut Validator, // The Validator object must be shared and mutable
        ctx: &mut TxContext
    ) {
        // Ownership of staked_sui_obj is implicitly checked by Sui if passed by &mut from sender's assets
        assert!(option::is_none(&staked_sui_obj.delegated_to_validator_id), E_ALREADY_DELEGATED);
        assert!(validator.is_active, E_VALIDATOR_INACTIVE);

        // Add the stake to the validator's pool
        balance::join(&mut validator.total_stake_pool, balance::copy(&staked_sui_obj.amount));
        staked_sui_obj.delegated_to_validator_id = option::some(object::id(validator));

        // Event: SuiDelegated { staker: sender(ctx), validator_id: object::id(validator), amount: balance::value(&staked_sui_obj.amount) }
    }

    /// Undelegates the sender's `StakedSui` from its current validator.
    /// The stake remains in the `StakedSui` object, now undelegated.
    public entry fun undelegate_sui(
        staked_sui_obj: &mut StakedSui,
        validator: &mut Validator, // The Validator object from which to undelegate
        ctx: &mut TxContext
    ) {
        assert!(option::is_some(&staked_sui_obj.delegated_to_validator_id), E_NOT_DELEGATED_TO_THIS_VALIDATOR); // General "not delegated"
        let validator_id = option::destroy_some(staked_sui_obj.delegated_to_validator_id); // Get and remove validator_id
        assert!(validator_id == object::id(validator), E_NOT_DELEGATED_TO_THIS_VALIDATOR);

        // Remove the stake from the validator's pool
        // This requires the amount to be available in the pool.
        let amount_to_remove_balance = balance::split(&mut validator.total_stake_pool, balance::value(&staked_sui_obj.amount));
        // The split balance should be destroyed or handled if it's not exactly the stake amount (which it should be here)
        balance::destroy_zero(amount_to_remove_balance); // Assuming it's exactly the amount, or handle remainder

        staked_sui_obj.delegated_to_validator_id = option::none();
        // Add unbonding period logic here if desired, e.g., set staked_sui_obj.unbonding_start_epoch
        // Event: SuiUndelegated { staker: sender(ctx), validator_id: object::id(validator), amount: balance::value(&staked_sui_obj.amount) }
    }

    /// Withdraws the SUI from a `StakedSui` object back to liquid `Coin<SUI>`.
    /// The `StakedSui` object must be undelegated.
    public entry fun withdraw_staked_sui(
        system_state: &mut GovernanceSystemState, // Pass the shared system state
        staked_sui_obj: StakedSui, // Takes ownership to consume the object
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx);
        assert!(option::is_none(&staked_sui_obj.delegated_to_validator_id), E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW);
        // Add check for unbonding period if implemented

        let StakedSui { id, amount, delegated_to_validator_id: _, reputation_score: _ } = staked_sui_obj;
        
        // Update total system stake
        let withdrawn_amount_value = balance::value(&amount);
        let temp_balance_to_subtract = balance::split(&mut system_state.total_staked_amount, withdrawn_amount_value);
        balance::destroy_zero(temp_balance_to_subtract); // Assuming exact subtraction

        let liquid_coins = coin::from_balance(amount, ctx);
        transfer::public_transfer(liquid_coins, staker);

        object::delete(id); // Deletes the StakedSui object's UID

        // Event: StakedSuiWithdrawn { staker, amount: withdrawn_amount_value }
    }

    // === Getter Functions (Read-only, typically no TxContext needed unless accessing shared objects) ===

    public fun get_staked_sui_amount(staked_sui_obj: &StakedSui): u64 {
        balance::value(&staked_sui_obj.amount)
    }

    public fun get_staked_sui_reputation(staked_sui_obj: &StakedSui): u128 {
        staked_sui_obj.reputation_score
    }

    public fun get_validator_reputation(validator: &Validator): u128 {
        validator.reputation
    }

    public fun get_validator_total_stake(validator: &Validator): u64 {
        balance::value(&validator.total_stake_pool)
    }
    
    public fun get_total_system_stake(system_state: &GovernanceSystemState): u64 {
        balance::value(&system_state.total_staked_amount)
    }

    public fun is_delegated(staked_sui_obj: &StakedSui): bool {
        option::is_some(&staked_sui_obj.delegated_to_validator_id)
    }

    public fun get_delegation_target(staked_sui_obj: &StakedSui): Option<ID> {
        option::copy(&staked_sui_obj.delegated_to_validator_id)
    }

    // === Internal / Admin Functions (Example) ===
    public entry fun update_user_reputation(
        staked_sui_obj: &mut StakedSui, 
        new_reputation: u128, 
        // admin_cap: &AdminCap, // Capability to ensure only authorized calls
        ctx: &mut TxContext
    ) {
        // assert!(tx_context::sender(ctx) == admin_cap.owner, "Not authorized"); // Example admin check
        staked_sui_obj.reputation_score = new_reputation;
    }

    public entry fun update_validator_reputation(
        validator: &mut Validator, 
        new_reputation: u128,
        // admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        validator.reputation = new_reputation;
    }

    public entry fun set_validator_active_status(
        validator: &mut Validator,
        is_active: bool,
        // admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        validator.is_active = is_active;
        // If becoming inactive, may need logic to handle existing delegations (e.g., force undelegation)
    }
}

