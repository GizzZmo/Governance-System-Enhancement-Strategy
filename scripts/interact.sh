#!/bin/bash
# File: scripts/interact.sh
# Interactive script for common governance operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SUI_COMMAND="${SUI_COMMAND:-sui client}"
PACKAGE_ID="${PACKAGE_ID:-}"

# Helper functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if package ID is set
check_package_id() {
    if [ -z "$PACKAGE_ID" ]; then
        print_error "PACKAGE_ID not set. Please set it as environment variable or in this script."
        echo "Example: export PACKAGE_ID=0x123..."
        exit 1
    fi
}

# Main menu
show_menu() {
    print_header "Governance System - Interactive CLI"
    echo "1. Stake SUI"
    echo "2. Create Proposal"
    echo "3. Vote on Proposal"
    echo "4. View Proposal Status"
    echo "5. Execute Proposal"
    echo "6. View Analytics"
    echo "7. Deposit to Treasury"
    echo "8. View Treasury Balance"
    echo "9. Delegate Voting Power"
    echo "0. Exit"
    echo ""
}

# Stake SUI
stake_sui() {
    print_header "Stake SUI"
    
    read -p "Enter amount to stake (in SUI): " amount
    
    # Convert to MIST (1 SUI = 1,000,000,000 MIST)
    amount_mist=$((amount * 1000000000))
    
    print_info "Staking $amount SUI ($amount_mist MIST)..."
    
    $SUI_COMMAND call \
        --package "$PACKAGE_ID" \
        --module delegation_staking \
        --function stake_sui \
        --gas-budget 10000000 \
        --args "$SYSTEM_STATE_ID" "$amount_mist"
    
    print_success "Stake transaction submitted!"
}

# Create proposal
create_proposal() {
    print_header "Create Proposal"
    
    echo "Select proposal type:"
    echo "0 - General Proposal"
    echo "1 - Minor Parameter Change"
    echo "2 - Critical Parameter Change"
    echo "3 - Funding Request"
    echo "4 - Emergency Action"
    read -p "Enter type (0-4): " proposal_type
    
    read -p "Enter description: " description
    
    case $proposal_type in
        3)
            read -p "Enter funding amount (in SUI): " amount
            read -p "Enter recipient address: " recipient
            amount_mist=$((amount * 1000000000))
            
            print_info "Creating funding proposal..."
            $SUI_COMMAND call \
                --package "$PACKAGE_ID" \
                --module governance \
                --function submit_proposal \
                --gas-budget 20000000 \
                --args "$description" "$proposal_type" "$amount_mist" "$recipient"
            ;;
        1|2)
            read -p "Enter target module: " module
            read -p "Enter parameter name: " param_name
            read -p "Enter new value (BCS encoded): " param_value
            
            print_info "Creating parameter change proposal..."
            $SUI_COMMAND call \
                --package "$PACKAGE_ID" \
                --module governance \
                --function submit_proposal \
                --gas-budget 20000000 \
                --args "$description" "$proposal_type" "$module" "$param_name" "$param_value"
            ;;
        *)
            print_info "Creating general proposal..."
            $SUI_COMMAND call \
                --package "$PACKAGE_ID" \
                --module governance \
                --function submit_proposal \
                --gas-budget 20000000 \
                --args "$description" "$proposal_type"
            ;;
    esac
    
    print_success "Proposal created!"
}

# Vote on proposal
vote_on_proposal() {
    print_header "Vote on Proposal"
    
    read -p "Enter proposal ID: " proposal_id
    read -p "Support (yes/no): " support
    read -p "Veto (yes/no, only for critical): " veto
    read -p "Enter your StakedSui object ID: " staked_sui_id
    
    # Convert yes/no to boolean
    support_bool="true"
    if [ "$support" == "no" ]; then
        support_bool="false"
    fi
    
    veto_bool="true"
    if [ "$veto" == "no" ]; then
        veto_bool="false"
    fi
    
    print_info "Casting vote..."
    $SUI_COMMAND call \
        --package "$PACKAGE_ID" \
        --module governance \
        --function hybrid_vote \
        --gas-budget 10000000 \
        --args "$proposal_id" "$staked_sui_id" "$support_bool" "$veto_bool"
    
    print_success "Vote cast!"
}

# View proposal status
view_proposal_status() {
    print_header "View Proposal Status"
    
    read -p "Enter proposal ID: " proposal_id
    
    print_info "Fetching proposal details..."
    $SUI_COMMAND object "$proposal_id"
}

# Execute proposal
execute_proposal() {
    print_header "Execute Proposal"
    
    read -p "Enter proposal ID: " proposal_id
    
    print_info "Executing proposal..."
    print_info "Note: Ensure you have the required capabilities!"
    
    $SUI_COMMAND call \
        --package "$PACKAGE_ID" \
        --module governance \
        --function execute_proposal \
        --gas-budget 30000000 \
        --args "$proposal_id"
    
    print_success "Proposal execution attempted!"
}

# View analytics
view_analytics() {
    print_header "View Governance Analytics"
    
    if [ -z "$ANALYTICS_ID" ]; then
        print_error "ANALYTICS_ID not set"
        return
    fi
    
    print_info "Fetching analytics..."
    $SUI_COMMAND object "$ANALYTICS_ID"
}

# Deposit to treasury
deposit_to_treasury() {
    print_header "Deposit to Treasury"
    
    read -p "Enter amount to deposit (in SUI): " amount
    amount_mist=$((amount * 1000000000))
    
    print_info "Depositing $amount SUI to treasury..."
    $SUI_COMMAND call \
        --package "$PACKAGE_ID" \
        --module treasury \
        --function deposit_funds \
        --gas-budget 10000000 \
        --args "$TREASURY_ID" "$amount_mist"
    
    print_success "Deposit successful!"
}

# View treasury balance
view_treasury_balance() {
    print_header "View Treasury Balance"
    
    if [ -z "$TREASURY_ID" ]; then
        print_error "TREASURY_ID not set"
        return
    fi
    
    print_info "Fetching treasury details..."
    $SUI_COMMAND object "$TREASURY_ID"
}

# Delegate voting power
delegate_voting_power() {
    print_header "Delegate Voting Power"
    
    read -p "Enter your StakedSui object ID: " staked_sui_id
    read -p "Enter delegate address: " delegate_address
    
    print_info "Delegating voting power..."
    $SUI_COMMAND call \
        --package "$PACKAGE_ID" \
        --module delegation_staking \
        --function delegate_voting_power \
        --gas-budget 10000000 \
        --args "$staked_sui_id" "$delegate_address"
    
    print_success "Voting power delegated!"
}

# Main loop
main() {
    check_package_id
    
    while true; do
        show_menu
        read -p "Select an option: " choice
        
        case $choice in
            1) stake_sui ;;
            2) create_proposal ;;
            3) vote_on_proposal ;;
            4) view_proposal_status ;;
            5) execute_proposal ;;
            6) view_analytics ;;
            7) deposit_to_treasury ;;
            8) view_treasury_balance ;;
            9) delegate_voting_power ;;
            0) 
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main
main
