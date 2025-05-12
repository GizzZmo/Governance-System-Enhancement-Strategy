// File: sources/delegation_staking.move
// Module for managing validator registration, staking, delegation, and reputation.
module hybrid_governance_pkg::delegation_staking {
    use std::option::{Self, Option, some, none, copy as option_copy, is_some, destroy_some};
    use std::vector; // Not used yet, but potentially for lists of delegators
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, zero, join, split, value, destroy_zero};
    use sui::sui::SUI; // Assuming SUI is the staking token
    use sui::object::{Self, ID, UID, new, id}; // Import id
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::event;

    // === Constants ===
    const INITIAL_REPUTATION: u128 = 100; // Default reputation for new stakers/validators

    // === Structs ===

    /// Capability object, held by an admin or governance module (via proposal_handler),
    /// authorizing administrative actions on this module (e.g., updating min_validator_stake).
    struct AdminCap has key, store {
        id: UID,
    }

    /// Information about a registered validator. This is a shared object.
    struct Validator has key, store {
        id: UID, // The UID of this Validator object
        owner: address, // Address of the validator operator
        total_stake_pool: Balance<SUI>, // Pool of all SUI staked to this validator
        reputation: u128,
        metadata_url: vector<u8>, // URL to off-chain validator metadata (name, logo, etc.)
        is_active: bool, // Whether the validator is currently active and accepting delegations
    }

    /// Represents a user's staked SUI tokens. This object is owned by the user.
    struct StakedSui has key, store {
        id: UID, // The UID of this StakedSui object
        amount: Balance<SUI>, // Amount of SUI staked
        delegated_to_validator_id: Option<ID>, // ID of the Validator object if delegated
        reputation_score: u128, // User's individual reputation score
        // unbonding_start_epoch: Option<u64>, // For future unstaking lockup logic
    }

    /// Shared object storing global system parameters for staking and governance.
    struct GovernanceSystemState has key {
        id: UID,
        total_staked_amount: Balance<SUI>, // Total SUI staked across the entire system
        min_validator_stake_threshold: u64, // Minimum SUI required for a new validator registration
    }

    // === Events ===
    struct ValidatorRegistered has copy, drop { validator_id: ID, owner: address, initial_stake: u64, metadata_url: vector<u8> }
    struct SuiStaked has copy, drop { staker: address, amount: u64, staked_sui_id: ID }
    struct SuiDelegated has copy, drop { staker: address, validator_id: ID, staked_sui_id: ID, amount: u64 }
    struct SuiUndelegated has copy, drop { staker: address, validator_id: ID, staked_sui_id: ID, amount: u64 }
    struct StakedSuiWithdrawn has copy, drop { staker: address, amount: u64, returned_sui_id: ID }
    struct MinValidatorStakeUpdated has copy, drop { updated_by_module: bool, new_min_stake: u64 } // updated_by_module true if by proposal_handler
    struct UserReputationUpdated has copy, drop { user_address: address, staked_sui_id: ID, new_reputation: u128 }
    struct ValidatorReputationUpdated has copy, drop { validator_id: ID, new_reputation: u128 }
    struct ValidatorStatusUpdated has copy, drop { validator_id: ID, is_active: bool }


    // === Errors ===
    const E_INSUFFICIENT_STAKE_FOR_VALIDATOR: u64 = 101;
    const E_VALIDATOR_NOT_FOUND: u64 = 103; // Used if trying to delegate to non-existent/inactive validator
    const E_INSUFFICIENT_BALANCE_TO_STAKE: u64 = 104; // Should be caught by coin value check
    const E_ALREADY_DELEGATED: u64 = 106;
    const E_NOT_DELEGATED_TO_THIS_VALIDATOR: u64 = 107; // If trying to undelegate from wrong validator
    const E_VALIDATOR_INACTIVE: u64 = 109;
    const E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW: u64 = 110;
    const E_STAKE_AMOUNT_MUST_BE_POSITIVE: u64 = 111;
    const E_UNAUTHORIZED_ADMIN_ACTION: u64 = 113;
    const E_INVALID_MIN_STAKE_VALUE: u64 = 114;
    const E_NOT_DELEGATED: u64 = 115; // If trying to undelegate when not delegated at all

    // === Init ===
    /// Initializes the module, creating the shared GovernanceSystemState and AdminCap.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(GovernanceSystemState {
            id: object::new(ctx),
            total_staked_amount: balance::zero(),
            min_validator_stake_threshold: 1_000_000_000, // Default: 1 SUI (9 decimals)
        });
        // AdminCap is created and given to the deployer of the package.
        // This cap must then be transferred to the governance module or a secure admin.
        transfer::transfer(AdminCap { id: object::new(ctx) }, sender(ctx));
    }

    // === Public Entry Functions: User Actions ===

    /// Registers the sender as a new validator.
    public entry fun register_validator(
        system_state: &mut GovernanceSystemState,
        self_stake_coin: Coin<SUI>, // Validator's initial own stake
        metadata_url: vector<u8>,
        ctx: &mut TxContext
    ) {
        let validator_owner = sender(ctx);
        let stake_value = coin::value(&self_stake_coin);
        assert!(stake_value >= system_state.min_validator_stake_threshold, E_INSUFFICIENT_STAKE_FOR_VALIDATOR);

        let validator_stake_pool = coin::into_balance(self_stake_coin);
        let validator_uid = object::new(ctx);
        let validator_id_val = object::uid_to_inner(&validator_uid);

        let validator = Validator {
            id: validator_uid,
            owner: validator_owner,
            total_stake_pool: validator_stake_pool,
            reputation: INITIAL_REPUTATION,
            metadata_url,
            is_active: true,
        };
        transfer::share_object(validator); // Validators are shared objects

        balance::join(&mut system_state.total_staked_amount, balance::copy(&validator.total_stake_pool));
        event::emit(ValidatorRegistered { validator_id: validator_id_val, owner: validator_owner, initial_stake: stake_value, metadata_url });
    }

    /// Stakes SUI tokens, creating a `StakedSui` object owned by the sender.
    public entry fun stake_sui(
        system_state: &mut GovernanceSystemState,
        coins_to_stake: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx);
        let stake_amount = coin::value(&coins_to_stake);
        assert!(stake_amount > 0, E_STAKE_AMOUNT_MUST_BE_POSITIVE);

        let staked_sui_balance = coin::into_balance(coins_to_stake);
        let staked_sui_uid = object::new(ctx);
        let staked_sui_id_val = object::uid_to_inner(&staked_sui_uid);

        let staked_sui_obj = StakedSui {
            id: staked_sui_uid,
            amount: staked_sui_balance,
            delegated_to_validator_id: option::none(),
            reputation_score: INITIAL_REPUTATION,
        };
        transfer::transfer(staked_sui_obj, staker); // User owns their StakedSui object

        balance::join(&mut system_state.total_staked_amount, balance::copy(&staked_sui_obj.amount));
        event::emit(SuiStaked { staker, amount: stake_amount, staked_sui_id: staked_sui_id_val });
    }

    /// Delegates the sender's `StakedSui` object to a chosen `Validator`.
    public entry fun delegate_sui(
        staked_sui_obj: &mut StakedSui, // Sender must own this object
        validator: &mut Validator,      // The shared Validator object to delegate to
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx); // For event
        assert!(is_none(&staked_sui_obj.delegated_to_validator_id), E_ALREADY_DELEGATED);
        assert!(validator.is_active, E_VALIDATOR_INACTIVE);

        let stake_amount_val = value(&staked_sui_obj.amount);
        balance::join(&mut validator.total_stake_pool, balance::copy(&staked_sui_obj.amount));
        staked_sui_obj.delegated_to_validator_id = option::some(id(validator));

        event::emit(SuiDelegated { staker, validator_id: id(validator), staked_sui_id: object::id(staked_sui_obj), amount: stake_amount_val });
    }

    /// Undelegates the sender's `StakedSui` from its current validator.
    public entry fun undelegate_sui(
        staked_sui_obj: &mut StakedSui, // Sender must own this
        validator: &mut Validator,      // The shared Validator object to undelegate from
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx); // For event
        assert!(is_some(&staked_sui_obj.delegated_to_validator_id), E_NOT_DELEGATED);
        let current_delegation_id = *option_borrow(&staked_sui_obj.delegated_to_validator_id);
        assert!(current_delegation_id == id(validator), E_NOT_DELEGATED_TO_THIS_VALIDATOR);

        let stake_amount_val = value(&staked_sui_obj.amount);
        // Remove the stake from the validator's pool
        let removed_balance = balance::split(&mut validator.total_stake_pool, stake_amount_val);
        // This removed_balance should exactly match the stake_amount_val. If not, there's an issue.
        // For safety, destroy it if it's zero, otherwise, this indicates a logic flaw.
        balance::destroy_zero(removed_balance);

        staked_sui_obj.delegated_to_validator_id = option::none();
        event::emit(SuiUndelegated { staker, validator_id: id(validator), staked_sui_id: object::id(staked_sui_obj), amount: stake_amount_val });
    }

    /// Withdraws SUI from a `StakedSui` object back to liquid `Coin<SUI>`.
    public entry fun withdraw_staked_sui(
        system_state: &mut GovernanceSystemState,
        staked_sui_obj: StakedSui, // Takes ownership to consume the object
        ctx: &mut TxContext
    ) {
        let staker = sender(ctx); // This is the caller, not necessarily original owner of StakedSui.
                                 // Sui's ownership model ensures only owner can pass StakedSui by value.
        assert!(is_none(&staked_sui_obj.delegated_to_validator_id), E_MUST_UNDELEGATE_FIRST_TO_WITHDRAW);

        let StakedSui { id, amount, delegated_to_validator_id: _, reputation_score: _ } = staked_sui_obj;
        let withdrawn_amount_value = value(&amount);

        // Subtract from total system stake
        let temp_balance_to_subtract = balance::split(&mut system_state.total_staked_amount, withdrawn_amount_value);
        balance::destroy_zero(temp_balance_to_subtract);

        let liquid_coins = coin::from_balance(amount, ctx);
        let liquid_coins_id = object::id(&liquid_coins); // For event
        transfer::public_transfer(liquid_coins, staker); // Transfer to the transaction sender

        object::delete(id); // Deletes the StakedSui object's UID

        event::emit(StakedSuiWithdrawn { staker, amount: withdrawn_amount_value, returned_sui_id: liquid_coins_id });
    }

    // === Administrative Functions ===

    /// Updates the minimum stake required for validator registration. Requires AdminCap.
    public entry fun admin_update_min_validator_stake(
        _admin_cap: &AdminCap, // Capability proving authorization
        system_state: &mut GovernanceSystemState,
        new_min_stake: u64,
        _ctx: &mut TxContext // Context for sender if needed for events, but cap is main auth
    ) {
        assert!(new_min_stake > 0, E_INVALID_MIN_STAKE_VALUE); // Basic validation
        system_state.min_validator_stake_threshold = new_min_stake;

        event::emit(MinValidatorStakeUpdated {
            updated_by_module: true, // Indicates called by an authorized entity (via proposal_handler)
            new_min_stake,
        });
    }

    /// Allows an authorized entity (e.g., governance module) to update a user's reputation.
    public entry fun admin_update_user_reputation(
        _admin_cap: &AdminCap, // Or a more specific capability for reputation management
        staked_sui_obj: &mut StakedSui,
        new_reputation: u128,
        ctx: &mut TxContext
    ) {
        staked_sui_obj.reputation_score = new_reputation;
        event::emit(UserReputationUpdated {
            user_address: sender(ctx), // This is who called; might be better to get owner of StakedSui if possible
            staked_sui_id: object::id(staked_sui_obj),
            new_reputation,
        });
    }

    /// Allows an authorized entity to update a validator's reputation.
    public entry fun admin_update_validator_reputation(
        _admin_cap: &AdminCap,
        validator: &mut Validator,
        new_reputation: u128,
        _ctx: &mut TxContext
    ) {
        validator.reputation = new_reputation;
        event::emit(ValidatorReputationUpdated { validator_id: id(validator), new_reputation });
    }

    /// Allows an authorized entity to set a validator's active status.
    public entry fun admin_set_validator_active_status(
        _admin_cap: &AdminCap,
        validator: &mut Validator,
        is_active: bool,
        _ctx: &mut TxContext
    ) {
        validator.is_active = is_active;
        event::emit(ValidatorStatusUpdated { validator_id: id(validator), is_active });
        // Note: If deactivating, more complex logic might be needed to handle existing delegators.
    }

    /// Transfers the AdminCap to a new address. Only the current owner of the cap can call this.
    public entry fun transfer_admin_cap(cap: AdminCap, recipient: address, _ctx: &mut TxContext) {
        transfer::transfer(cap, recipient);
    }

    // === Getter Functions (Read-only) ===
    public fun get_staked_sui_amount(staked_sui_obj: &StakedSui): u64 { value(&staked_sui_obj.amount) }
    public fun get_staked_sui_reputation(staked_sui_obj: &StakedSui): u128 { staked_sui_obj.reputation_score }
    public fun get_validator_reputation(validator: &Validator): u128 { validator.reputation }
    public fun get_validator_total_stake(validator: &Validator): u64 { value(&validator.total_stake_pool) }
    public fun get_total_system_stake(system_state: &GovernanceSystemState): u64 { value(&system_state.total_staked_amount) }
    public fun get_min_validator_stake_threshold(system_state: &GovernanceSystemState): u64 { system_state.min_validator_stake_threshold }
    public fun is_delegated(staked_sui_obj: &StakedSui): bool { is_some(&staked_sui_obj.delegated_to_validator_id) }
    public fun get_delegation_target(staked_sui_obj: &StakedSui): Option<ID> { option_copy(&staked_sui_obj.delegated_to_validator_id) }
}

