#!/bin/bash
# File: scripts/vote.sh
# Simplified voting script for EbA governance system
# Based on EBA_IMPLEMENTATION_ROADMAP.md simplification example
#
# Usage: ./scripts/vote.sh <proposal-id> <support|against> [staked-sui-id]
#
# This script simplifies the complex voting command into an easy-to-use interface

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <proposal-id> <support|against> [staked-sui-id]"
    echo ""
    echo "Examples:"
    echo "  $0 0x123abc support"
    echo "  $0 0x123abc against 0xdef456"
    echo ""
    echo "If staked-sui-id is not provided, the script will attempt to find one automatically."
    exit 1
fi

PROPOSAL_ID=$1
VOTE_DIRECTION=$2
STAKED_SUI_ID=${3:-""}

# Validate vote direction
if [ "$VOTE_DIRECTION" != "support" ] && [ "$VOTE_DIRECTION" != "against" ]; then
    print_error "Vote direction must be 'support' or 'against'"
    exit 1
fi

# Convert vote direction to boolean flags
if [ "$VOTE_DIRECTION" = "support" ]; then
    VOTE_FOR="true"
    VOTE_AGAINST="false"
else
    VOTE_FOR="false"
    VOTE_AGAINST="true"
fi

print_info "Preparing to vote on proposal ${PROPOSAL_ID}..."
print_info "Vote direction: ${VOTE_DIRECTION}"

# Check if required environment variables are set
if [ -z "$PACKAGE_ID" ]; then
    print_error "PACKAGE_ID environment variable is not set"
    print_info "Please set it with: export PACKAGE_ID=<your-package-id>"
    exit 1
fi

# If staked SUI ID not provided, try to find one
if [ -z "$STAKED_SUI_ID" ]; then
    print_info "No staked SUI ID provided, attempting to find one..."
    
    # Get owned objects and try to find StakedSui object
    # This is a simplified approach - in production, would parse JSON properly
    OWNED_OBJECTS=$(sui client objects 2>/dev/null || echo "")
    
    if [ -z "$OWNED_OBJECTS" ]; then
        print_error "Could not retrieve owned objects. Please provide staked-sui-id manually."
        exit 1
    fi
    
    print_warning "Please provide your staked SUI object ID manually for now"
    print_info "You can find it by running: sui client objects"
    exit 1
fi

print_info "Using staked SUI: ${STAKED_SUI_ID}"

# Gas budget (10 SUI)
GAS_BUDGET=10000000

# Execute the vote
print_info "Submitting vote..."

VOTE_COMMAND="sui client call \
    --package $PACKAGE_ID \
    --module governance \
    --function hybrid_vote \
    --args $PROPOSAL_ID $STAKED_SUI_ID $VOTE_FOR $VOTE_AGAINST \
    --gas-budget $GAS_BUDGET"

# Show the command being executed
print_info "Executing: sui client call --module governance --function hybrid_vote ..."

# Execute the command
if $VOTE_COMMAND; then
    print_success "Vote submitted successfully!"
    print_info "Your vote '${VOTE_DIRECTION}' has been recorded for proposal ${PROPOSAL_ID}"
else
    print_error "Vote submission failed"
    exit 1
fi

# Optional: Show proposal status after voting
print_info "Fetching updated proposal status..."
sui client object $PROPOSAL_ID 2>/dev/null || print_warning "Could not fetch proposal status"

echo ""
print_success "Vote complete!"
