// File: sources/delegation_staking.move
// Module for managing validator registration, staking, delegation, and reputation.
// Enhanced with AdminCap and configurable parameters.

module hybrid_governance::delegation_staking {
    use std::signer;
    use std::option::{Self, Option, some, none};
    use std::vector;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, zero, join, split, value};
    use sui::sui::SUI; // Assuming SUI is the staking token
    use sui::object::{Self, ID, UID, new};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::event; // Import event

    // === Constants ===
    // const MIN_VALIDATOR_STAKE: u64 = 1_000_000_000; // Now configurable in GovernanceSystemState
    const INITIAL_REPUTATION: u128 = 100;

    // === Structs ===

    /// Capability object, held by an admin or governance module,
    /// authorizing administrative actions on this module.
    struct AdminCap has key, store {
        id: UID,
    }

    /// Information about a registered validator
    struct Validator has key, store {
        id: UID,
        owner: address,
        total_stake_pool: Balance<SUI>,
        reputation: u128,
        metadata_url: vector<u8>,
        is_active: bool,
    }

    /// Represents a user's staked SUI tokens.
    struct StakedSui has key, store {
        id: UID,
        amount: Balance<SUI>,
        delegated_to_validator_id: Option<ID>,
        reputation_score: u128,
    }

    /// Shared object to store total staked SUI and configurable system parameters.
    struct GovernanceSystemState has key {
        id: UID,
        total_staked_amount: Balance<SUI>,
        min_validator_stake_threshold: u64, // New: Configurable minimum stake for validators
        // Add other configurable parameters here, e.g., initial_reputation_default: u128
    }

    // === Events ===
    struct MinValidatorStakeUpdated has copy, drop {
        updated_by: address, // Address of the admin/governance contract
        new_min_stake: u64,
    }
    // Add other events for staking, delegation, validator registration etc.

    // === Errors ===
    const E_INSUFFICIENT_STAKE_FOR_VALIDATOR: u64 = 101;
    const E_VALIDATOR_ALREADY_EXISTS: u64 = 102;
    const E_VALIDATOR_NOT_FOUND: u64 = 103;
    const E_INSUFFICIENT_BALANCE_TO_STAKE: u64 = 104;
    const E_NOT_ENOUGH_STAKED_TO_UNDELEGATE: u64 = 105;
    const E_ALREADY_DELEGATED: u64 = 106;
    const E_NOT_DELEGATED_TO_THIS_VALIDATOR: u64 = 107;
    const E_STAKED_SUI_OBJECT_NOT_OWNED_BY_SENDER: u64 = 108;
    const E_VALIDATOR_INACTIVE: u64 = 109;
    const E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW: u64 = 110;
    const E_STAKE_AMOUNT_MUST_BE_POSITIVE: u64 = 111;
    const E_SYSTEM_STATE_NOT_FOUND: u64 = 112;
    const E_UNAUTHORIZED_ADMIN_ACTION: u64 = 113; // For AdminCap checks
    const E_INVALID_MIN_STAKE_VALUE: u64 = 114;


    // === Init ===
    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceSystemState {
            id: object::new(ctx),
            total_staked_amount: balance::zero(),
            min_validator_stake_threshold: 1_000_000_000, // Default min validator stake (1 SUI)
        });
        // Create and transfer AdminCap to the deployer
        transfer::transfer(AdminCap { id: object::new(ctx) }, sender(ctx));
    }

    // === Public Entry Functions ===

    public entry fun register_validator(
        system_state: &mut GovernanceSystemState,
        self_stake_coin: Coin<SUI>,
        metadata_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let validator_owner = sender(ctx);
        let stake_value = coin::value(&self_stake_coin);
        // Read min_validator_stake_threshold from system_state
        assert!(stake_value >= system_state.min_validator_stake_threshold, E_INSUFFICIENT_STAKE_FOR_VALIDATOR);

        let validator_stake_pool = coin::into_balance(self_stake_coin);
        let validator = Validator {
            id: object::new(ctx),
            owner: validator_owner,
            total_stake_pool: validator_stake_pool,
            reputation: INITIAL_REPUTATION,
            metadata_url,
            is_active: true,
        };
        transfer::share_object(validator);
        balance::join(&mut system_state.total_staked_amount, balance::copy(&validator.total_stake_pool));
    }

    public entry fun stake_sui(
        system_state: &mut GovernanceSystemState,
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
            reputation_score: INITIAL_REPUTATION,
        };
        transfer::transfer(staked_sui_obj, staker);
        balance::join(&mut system_state.total_staked_amount, balance::copy(&staked_sui_obj.amount));
    }

    public entry fun delegate_sui(
        staked_sui_obj: &mut StakedSui,
        validator: &mut Validator,
        ctx: &mut TxContext // Sender implicitly checked by &mut StakedSui
    ) {
        assert!(option::is_none(&staked_sui_obj.delegated_to_validator_id), E_ALREADY_DELEGATED);
        assert!(validator.is_active, E_VALIDATOR_INACTIVE);
        balance::join(&mut validator.total_stake_pool, balance::copy(&staked_sui_obj.amount));
        staked_sui_obj.delegated_to_validator_id = option::some(object::id(validator));
    }

    public entry fun undelegate_sui(
        staked_sui_obj: &mut StakedSui,
        validator: &mut Validator,
        ctx: &mut TxContext // Sender implicitly checked
    ) {
        assert!(option::is_some(&staked_sui_obj.delegated_to_validator_id), E_NOT_DELEGATED_TO_THIS_VALIDATOR);
        let validator_id = option::destroy_some(staked_sui_obj.delegated_to_validator_id);
        assert!(validator_id == object::id(validator), E_NOT_DELEGATED_TO_THIS_VALIDATOR);
        let amount_to_remove_balance = balance::split(&mut validator.total_stake_pool, balance::value(&staked_sui_obj.amount));
        balance::destroy_zero(amount_to_remove_balance);
        staked_sui_obj.delegated_to_validator_id = option::none();
    }

    public entry fun withdraw_staked_sui(
        system_state: &mut GovernanceSystemState,
        staked_sui_obj: StakedSui, // Takes ownership
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx); // This check is not robust; ownership of staked_sui_obj is key
        assert!(option::is_none(&staked_sui_obj.delegated_to_validator_id), E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW);
        let StakedSui { id, amount, delegated_to_validator_id: _, reputation_score: _ } = staked_sui_obj;
        let withdrawn_amount_value = balance::value(&amount);
        let temp_balance_to_subtract = balance::split(&mut system_state.total_staked_amount, withdrawn_amount_value);
        balance::destroy_zero(temp_balance_to_subtract);
        let liquid_coins = coin::from_balance(amount, ctx);
        transfer::public_transfer(liquid_coins, staker); // Transfer to the original owner of StakedSui
        object::delete(id);
    }

    // === Administrative Functions ===

    /// Updates the minimum stake required to become a validator.
    /// Requires AdminCap.
    public entry fun admin_update_min_validator_stake(
        _admin_cap: &AdminCap, // Capability proving authorization
        system_state: &mut GovernanceSystemState,
        new_min_stake: u64,
        ctx: &mut TxContext
    ) {
        assert!(new_min_stake > 0, E_INVALID_MIN_STAKE_VALUE); // Example validation
        system_state.min_validator_stake_threshold = new_min_stake;

        event::emit(MinValidatorStakeUpdated {
            updated_by: sender(ctx), // Could be the address holding the cap, or governance module
            new_min_stake,
        });
    }

    // Add other admin functions here e.g., for updating default reputation, pausing system, etc.
    // public entry fun transfer_admin_cap(cap: AdminCap, recipient: address, _ctx: &mut TxContext) {
    // transfer::transfer(cap, recipient);
    // }


    // === Getter Functions ===
    public fun get_staked_sui_amount(staked_sui_obj: &StakedSui): u64 { balance::value(&staked_sui_obj.amount) }
    public fun get_staked_sui_reputation(staked_sui_obj: &StakedSui): u128 { staked_sui_obj.reputation_score }
    public fun get_validator_reputation(validator: &Validator): u128 { validator.reputation }
    public fun get_validator_total_stake(validator: &Validator): u64 { balance::value(&validator.total_stake_pool) }
    public fun get_total_system_stake(system_state: &GovernanceSystemState): u64 { balance::value(&system_state.total_staked_amount) }
    public fun get_min_validator_stake_threshold(system_state: &GovernanceSystemState): u64 { system_state.min_validator_stake_threshold }
    public fun is_delegated(staked_sui_obj: &StakedSui): bool { option::is_some(&staked_sui_obj.delegated_to_validator_id) }
    public fun get_delegation_target(staked_sui_obj: &StakedSui): Option<ID> { option::copy(&staked_sui_obj.delegated_to_validator_id) }
    public entry fun update_user_reputation(staked_sui_obj: &mut StakedSui, new_reputation: u128, _ctx: &mut TxContext) { staked_sui_obj.reputation_score = new_reputation; }
    public entry fun update_validator_reputation(validator: &mut Validator, new_reputation: u128, _ctx: &mut TxContext) { validator.reputation = new_reputation; }
    public entry fun set_validator_active_status(validator: &mut Validator, is_active: bool, _ctx: &mut TxContext) { validator.is_active = is_active; }
}
