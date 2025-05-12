#!/bin/bash

# File: scripts/deploy.sh
# Script to build and publish the HybridGovernance Sui package.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "🚀 Building and Deploying Sui Governance Package..."

# Define your package path. This script assumes it's run from the root
# of the 'hybrid-governance' project directory where Move.toml is located.
PACKAGE_PATH="."

# You can customize the Sui client command, e.g., to specify a network or alias
# SUI_NETWORK="devnet" # or "testnet", "mainnet"
# SUI_CLIENT_ALIAS="your_alias" # if you use custom client.yaml aliases
# SUI_COMMAND="sui client --network $SUI_NETWORK --alias $SUI_CLIENT_ALIAS"
SUI_COMMAND="sui client" # Uses default sui client configuration

echo "🛠️ Building Sui package at path: $PACKAGE_PATH"
# The build command checks for errors and compiles the Move code.
# Using --install-dir can help with resolving dependencies if they are local.
# Use --fetch-deps-only to only download dependencies if needed.
$SUI_COMMAND move build --path "$PACKAGE_PATH" --install-dir

echo "🚢 Publishing Sui package..."
# Adjust gas budget as needed. This is a placeholder value.
# For complex packages, a higher budget might be necessary.
# The output of this command will contain the package ID and created/mutated objects.
# Using the --json flag provides structured output for easier parsing.
PUBLISH_OUTPUT=$($SUI_COMMAND publish --gas-budget 300000000 --path "$PACKAGE_PATH" --json) # Increased gas budget

echo "✅ Deployment Attempted."
echo "📜 Full Publish Output (JSON):"
echo "$PUBLISH_OUTPUT"

# --- Extracting IDs using jq (recommended for robust JSON parsing) ---
# Ensure jq is installed on your system (e.g., sudo apt-get install jq or brew install jq).

# Extract Package ID (Immutable object created for the package itself)
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.effects.created[] | select(.owner == "Immutable") | .reference.objectId')

# Extract IDs of shared objects created by the init functions of your modules.
# The objectType will be in the format: <PACKAGE_ID>::<MODULE_NAME>::<STRUCT_NAME>
# Adjust the module and struct names as per your actual definitions.

TREASURY_CHEST_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::treasury::TreasuryChest$\")) | .objectId")
SYSTEM_STATE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::delegation_staking::GovernanceSystemState$\")) | .objectId")

# Extract IDs of Capability objects transferred to the deployer by init functions.
# These will appear in objectChanges with owner being an AddressOwner.
DEPLOYER_ADDRESS=$($SUI_COMMAND active-address) # Get the deployer's active address

TREASURY_ACCESS_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::treasury::TreasuryAccessCap$\")) | select(.owner.AddressOwner == \"$DEPLOYER_ADDRESS\") | .objectId")
TREASURY_ADMIN_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::treasury::TreasuryAdminCap$\")) | select(.owner.AddressOwner == \"$DEPLOYER_ADDRESS\") | .objectId")
STAKING_ADMIN_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::delegation_staking::AdminCap$\")) | select(.owner.AddressOwner == \"$DEPLOYER_ADDRESS\") | .objectId")
PROPOSAL_EXEC_CAP_ID=$(echo "$PUBLISH_OUTPUT" | jq -r ".objectChanges[] | select(.objectType | test(\"::proposal_handler::ProposalExecutionCap$\")) | select(.owner.AddressOwner == \"$DEPLOYER_ADDRESS\") | .objectId")


echo "--- Extracted Information ---"
if [ -n "$PACKAGE_ID" ] && [ "$PACKAGE_ID" != "null" ]; then
    echo "🎉 Package ID: $PACKAGE_ID"
    echo "📌 IMPORTANT: Update 'hybrid_governance_pkg = \"$PACKAGE_ID\"' in your Move.toml and re-run 'sui move build' then re-publish if this was the first publish or if the ID was a placeholder."
else
    echo "⚠️ Could not automatically extract Package ID. Please check the JSON output above."
fi

if [ -n "$TREASURY_CHEST_ID" ] && [ "$TREASURY_CHEST_ID" != "null" ]; then
    echo "💰 TreasuryChest (Shared Object) ID: $TREASURY_CHEST_ID"
else
    echo "⚠️ Could not automatically extract TreasuryChest Object ID."
fi

if [ -n "$SYSTEM_STATE_ID" ] && [ "$SYSTEM_STATE_ID" != "null" ]; then
    echo "⚙️ GovernanceSystemState (Shared Object) ID: $SYSTEM_STATE_ID"
else
    echo "⚠️ Could not automatically extract GovernanceSystemState Object ID."
fi

echo "--- Capability Objects (Owned by Deployer: $DEPLOYER_ADDRESS) ---"
if [ -n "$TREASURY_ACCESS_CAP_ID" ] && [ "$TREASURY_ACCESS_CAP_ID" != "null" ]; then echo "🔑 TreasuryAccessCap ID: $TREASURY_ACCESS_CAP_ID"; else echo "⚠️ TreasuryAccessCap ID not found."; fi
if [ -n "$TREASURY_ADMIN_CAP_ID" ] && [ "$TREASURY_ADMIN_CAP_ID" != "null" ]; then echo "🔑 TreasuryAdminCap ID: $TREASURY_ADMIN_CAP_ID"; else echo "⚠️ TreasuryAdminCap ID not found."; fi
if [ -n "$STAKING_ADMIN_CAP_ID" ] && [ "$STAKING_ADMIN_CAP_ID" != "null" ]; then echo "🔑 StakingAdminCap ID: $STAKING_ADMIN_CAP_ID"; else echo "⚠️ StakingAdminCap ID not found."; fi
if [ -n "$PROPOSAL_EXEC_CAP_ID" ] && [ "$PROPOSAL_EXEC_CAP_ID" != "null" ]; then echo "🔑 ProposalExecutionCap ID: $PROPOSAL_EXEC_CAP_ID"; else echo "⚠️ ProposalExecutionCap ID not found."; fi


echo ""
echo "🔗 Next Steps After First Successful Publish:"
echo "1. Update 'hybrid_governance_pkg = \"$PACKAGE_ID\"' in Move.toml."
echo "2. Re-run 'sui move build --path .' to ensure modules compile with the correct package ID."
echo "3. Re-run this 'deploy.sh' script. The second publish will upgrade the existing package."
echo "4. Transfer Capability Objects: Use the Sui CLI to transfer the extracted Cap IDs from the deployer ($DEPLOYER_ADDRESS) to the appropriate module admin addresses or to a shared 'CapabilityRegistry' object if you design one."
echo "   Example: sui client transfer --gas-budget 50000000 --object-id <CAP_ID_HERE> --recipient <GOVERNANCE_MODULE_ADMIN_ADDRESS>"
echo "5. Call any necessary post-deployment setup functions using the shared object IDs."

