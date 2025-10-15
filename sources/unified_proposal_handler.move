// File: sources/unified_proposal_handler.move
// Unified proposal execution handler module
// Implements EbA (Ecosystem-based Adaptation) principle of coordinated decision-making
//
// This module provides a centralized, coordinated system for handling all proposal
// types, addressing the institutional barrier of fragmented decision-making.

module hybrid_governance_pkg::unified_proposal_handler {
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};

    // === Error Codes ===
    
    /// Proposal not found
    const E_PROPOSAL_NOT_FOUND: u64 = 1;
    
    /// Proposal already executed
    const E_ALREADY_EXECUTED: u64 = 2;
    
    /// Proposal not approved
    const E_NOT_APPROVED: u64 = 3;
    
    /// Invalid proposal type
    const E_INVALID_PROPOSAL_TYPE: u64 = 4;
    
    /// Unauthorized execution attempt
    const E_UNAUTHORIZED: u64 = 5;

    /// Execution failed
    const E_EXECUTION_FAILED: u64 = 6;

    // === Constants ===
    
    /// Proposal Types
    const PROPOSAL_TYPE_GENERAL: u8 = 0;
    const PROPOSAL_TYPE_PARAMETER: u8 = 1;
    const PROPOSAL_TYPE_CRITICAL: u8 = 2;
    const PROPOSAL_TYPE_FUNDING: u8 = 3;
    const PROPOSAL_TYPE_EMERGENCY: u8 = 4;

    // === Structs ===

    /// Unified proposal registry tracking all proposals
    struct ProposalRegistry has key {
        id: UID,
        /// All proposals indexed by ID
        proposals: Table<ID, ProposalInfo>,
        /// Proposals by type for filtering
        proposals_by_type: Table<u8, vector<ID>>,
        /// Execution queue (approved but not yet executed)
        execution_queue: vector<ID>,
        /// Total proposals processed
        total_processed: u64,
        /// Failed executions count
        failed_executions: u64,
    }

    /// Information about a proposal in the unified system
    struct ProposalInfo has store, copy, drop {
        proposal_id: ID,
        proposal_type: u8,
        creator: address,
        approved: bool,
        executed: bool,
        execution_result: Option<bool>,
        created_timestamp: u64,
        executed_timestamp: u64,
        description_hash: vector<u8>, // Hash of description for verification
    }

    /// Execution capability - restricts who can execute proposals
    struct ExecutionCapability has key, store {
        id: UID,
        authorized_executors: vector<address>,
    }

    /// Event emitted when proposal is registered
    struct ProposalRegistered has copy, drop {
        proposal_id: ID,
        proposal_type: u8,
        creator: address,
        timestamp: u64,
    }

    /// Event emitted when proposal execution is attempted
    struct ProposalExecutionAttempted has copy, drop {
        proposal_id: ID,
        proposal_type: u8,
        executor: address,
        success: bool,
        timestamp: u64,
    }

    /// Event emitted when proposal is approved
    struct ProposalApproved has copy, drop {
        proposal_id: ID,
        proposal_type: u8,
        timestamp: u64,
    }

    /// Event emitted when execution queue is processed
    struct ExecutionQueueProcessed has copy, drop {
        proposals_processed: u64,
        successful_executions: u64,
        failed_executions: u64,
        timestamp: u64,
    }

    // === Init Function ===

    /// Initialize the unified proposal handler system
    fun init(ctx: &mut TxContext) {
        let registry = ProposalRegistry {
            id: object::new(ctx),
            proposals: table::new(ctx),
            proposals_by_type: table::new(ctx),
            execution_queue: vector::empty(),
            total_processed: 0,
            failed_executions: 0,
        };
        
        let capability = ExecutionCapability {
            id: object::new(ctx),
            authorized_executors: vector::empty(),
        };
        
        transfer::share_object(registry);
        transfer::transfer(capability, tx_context::sender(ctx));
    }

    // === Public Functions ===

    /// Register a new proposal in the unified system
    /// 
    /// All proposal types route through this unified registration system
    /// to ensure centralized tracking and coordination
    /// 
    /// # Arguments
    /// * `registry` - The proposal registry
    /// * `proposal_id` - ID of the proposal object
    /// * `proposal_type` - Type of proposal (0-4)
    /// * `description_hash` - Hash of proposal description
    /// * `ctx` - Transaction context
    public fun register_proposal(
        registry: &mut ProposalRegistry,
        proposal_id: ID,
        proposal_type: u8,
        description_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(proposal_type <= 4, E_INVALID_PROPOSAL_TYPE);
        
        let proposal_info = ProposalInfo {
            proposal_id,
            proposal_type,
            creator: tx_context::sender(ctx),
            approved: false,
            executed: false,
            execution_result: option::none(),
            created_timestamp: tx_context::epoch(ctx),
            executed_timestamp: 0,
            description_hash,
        };
        
        // Add to main registry
        table::add(&mut registry.proposals, proposal_id, proposal_info);
        
        // Add to type-specific index
        if (!table::contains(&registry.proposals_by_type, proposal_type)) {
            table::add(&mut registry.proposals_by_type, proposal_type, vector::empty());
        };
        let type_list = table::borrow_mut(&mut registry.proposals_by_type, proposal_type);
        vector::push_back(type_list, proposal_id);
        
        event::emit(ProposalRegistered {
            proposal_id,
            proposal_type,
            creator: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Mark a proposal as approved
    /// 
    /// Called by governance system when voting concludes successfully
    /// Adds proposal to execution queue
    public fun approve_proposal(
        registry: &mut ProposalRegistry,
        proposal_id: ID,
        ctx: &mut TxContext
    ) {
        assert!(table::contains(&registry.proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        
        let proposal_info = table::borrow_mut(&mut registry.proposals, proposal_id);
        proposal_info.approved = true;
        
        // Add to execution queue
        vector::push_back(&mut registry.execution_queue, proposal_id);
        
        event::emit(ProposalApproved {
            proposal_id,
            proposal_type: proposal_info.proposal_type,
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Execute a proposal through the unified handler
    /// 
    /// This is the centralized execution point for all proposal types,
    /// ensuring coordinated and consistent execution logic
    /// 
    /// # Arguments
    /// * `registry` - The proposal registry
    /// * `capability` - Execution capability (authorization)
    /// * `proposal_id` - ID of the proposal to execute
    /// * `ctx` - Transaction context
    public fun execute_proposal(
        registry: &mut ProposalRegistry,
        capability: &ExecutionCapability,
        proposal_id: ID,
        ctx: &mut TxContext
    ): bool {
        // Verify authorization
        let executor = tx_context::sender(ctx);
        assert!(
            is_authorized_executor(capability, executor),
            E_UNAUTHORIZED
        );
        
        // Get proposal info
        assert!(table::contains(&registry.proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        let proposal_info = table::borrow_mut(&mut registry.proposals, proposal_id);
        
        // Verify proposal can be executed
        assert!(proposal_info.approved, E_NOT_APPROVED);
        assert!(!proposal_info.executed, E_ALREADY_EXECUTED);
        
        // Execute based on proposal type
        let success = execute_by_type(
            proposal_info.proposal_type,
            proposal_id,
            ctx
        );
        
        // Update execution status
        proposal_info.executed = true;
        proposal_info.execution_result = option::some(success);
        proposal_info.executed_timestamp = tx_context::epoch(ctx);
        
        // Update registry statistics
        registry.total_processed = registry.total_processed + 1;
        if (!success) {
            registry.failed_executions = registry.failed_executions + 1;
        };
        
        // Remove from execution queue
        remove_from_queue(&mut registry.execution_queue, proposal_id);
        
        event::emit(ProposalExecutionAttempted {
            proposal_id,
            proposal_type: proposal_info.proposal_type,
            executor,
            success,
            timestamp: tx_context::epoch(ctx),
        });
        
        success
    }

    /// Process the entire execution queue
    /// 
    /// Batch execution of all approved proposals
    /// Useful for scheduled execution runs
    public fun process_execution_queue(
        registry: &mut ProposalRegistry,
        capability: &ExecutionCapability,
        max_to_process: u64,
        ctx: &mut TxContext
    ) {
        let queue_size = vector::length(&registry.execution_queue);
        let to_process = if (max_to_process < queue_size) { max_to_process } else { queue_size };
        
        let (processed, successful, failed) = process_queue_recursive(
            registry,
            capability,
            0,
            to_process,
            0,
            0,
            0,
            ctx
        );
        
        event::emit(ExecutionQueueProcessed {
            proposals_processed: processed,
            successful_executions: successful,
            failed_executions: failed,
            timestamp: tx_context::epoch(ctx),
        });
    }
    
    /// Helper to process queue recursively
    fun process_queue_recursive(
        registry: &mut ProposalRegistry,
        capability: &ExecutionCapability,
        i: u64,
        to_process: u64,
        processed: u64,
        successful: u64,
        failed: u64,
        ctx: &mut TxContext
    ): (u64, u64, u64) {
        if (i >= to_process || i >= vector::length(&registry.execution_queue)) {
            return (processed, successful, failed)
        };
        
        let proposal_id = *vector::borrow(&registry.execution_queue, i);
        let success = execute_proposal(registry, capability, proposal_id, ctx);
        
        let new_processed = processed + 1;
        let new_successful = if (success) { successful + 1 } else { successful };
        let new_failed = if (!success) { failed + 1 } else { failed };
        
        process_queue_recursive(
            registry,
            capability,
            i + 1,
            to_process,
            new_processed,
            new_successful,
            new_failed,
            ctx
        )
    }

    /// Add an authorized executor
    public fun add_authorized_executor(
        capability: &mut ExecutionCapability,
        executor: address,
        ctx: &mut TxContext
    ) {
        // Only the capability owner can add executors
        // In production, this would have additional authorization checks
        vector::push_back(&mut capability.authorized_executors, executor);
    }

    // === Helper Functions ===

    /// Execute proposal based on its type
    /// 
    /// Routes to appropriate execution logic for each proposal type
    fun execute_by_type(
        proposal_type: u8,
        proposal_id: ID,
        ctx: &mut TxContext
    ): bool {
        if (proposal_type == PROPOSAL_TYPE_GENERAL) {
            execute_general_proposal(proposal_id, ctx)
        } else if (proposal_type == PROPOSAL_TYPE_PARAMETER) {
            execute_parameter_proposal(proposal_id, ctx)
        } else if (proposal_type == PROPOSAL_TYPE_CRITICAL) {
            execute_critical_proposal(proposal_id, ctx)
        } else if (proposal_type == PROPOSAL_TYPE_FUNDING) {
            execute_funding_proposal(proposal_id, ctx)
        } else if (proposal_type == PROPOSAL_TYPE_EMERGENCY) {
            execute_emergency_proposal(proposal_id, ctx)
        } else {
            false // Unknown type
        }
    }

    /// Execute general proposal
    fun execute_general_proposal(proposal_id: ID, ctx: &mut TxContext): bool {
        // General proposals typically just signal community consensus
        // Actual implementation would depend on specific use case
        true
    }

    /// Execute parameter change proposal
    fun execute_parameter_proposal(proposal_id: ID, ctx: &mut TxContext): bool {
        // Would update system parameters
        // Implementation depends on parameter storage system
        true
    }

    /// Execute critical system change proposal
    fun execute_critical_proposal(proposal_id: ID, ctx: &mut TxContext): bool {
        // Would execute critical system changes
        // Requires extra validation and safeguards
        true
    }

    /// Execute funding request proposal
    fun execute_funding_proposal(proposal_id: ID, ctx: &mut TxContext): bool {
        // Would transfer funds from treasury
        // Implementation depends on treasury system
        true
    }

    /// Execute emergency proposal
    fun execute_emergency_proposal(proposal_id: ID, ctx: &mut TxContext): bool {
        // Would execute emergency actions
        // Fast-track execution with heightened security
        true
    }

    /// Check if address is authorized executor
    fun is_authorized_executor(capability: &ExecutionCapability, executor: address): bool {
        vector::contains(&capability.authorized_executors, &executor)
    }

    /// Remove proposal from execution queue
    fun remove_from_queue(queue: &mut vector<ID>, proposal_id: ID) {
        let (found, index) = vector::index_of(queue, &proposal_id);
        if (found) {
            vector::remove(queue, index);
        };
    }

    // === View Functions ===

    /// Get proposal information
    public fun get_proposal_info(
        registry: &ProposalRegistry,
        proposal_id: ID
    ): (u8, address, bool, bool) {
        assert!(table::contains(&registry.proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        let info = table::borrow(&registry.proposals, proposal_id);
        (info.proposal_type, info.creator, info.approved, info.executed)
    }

    /// Get execution queue length
    public fun get_queue_length(registry: &ProposalRegistry): u64 {
        vector::length(&registry.execution_queue)
    }

    /// Get total proposals processed
    public fun get_total_processed(registry: &ProposalRegistry): u64 {
        registry.total_processed
    }

    /// Get failed executions count
    public fun get_failed_executions(registry: &ProposalRegistry): u64 {
        registry.failed_executions
    }

    /// Get proposals by type
    public fun get_proposals_by_type(
        registry: &ProposalRegistry,
        proposal_type: u8
    ): u64 {
        if (!table::contains(&registry.proposals_by_type, proposal_type)) {
            0
        } else {
            vector::length(table::borrow(&registry.proposals_by_type, proposal_type))
        }
    }

    /// Calculate execution success rate (in basis points)
    public fun get_execution_success_rate(registry: &ProposalRegistry): u64 {
        if (registry.total_processed == 0) {
            return 10000 // 100% if no executions yet
        };
        
        let successful = registry.total_processed - registry.failed_executions;
        (successful * 10000) / registry.total_processed
    }

    // === Test-only Functions ===

    #[test_only]
    /// Initialize for testing
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
