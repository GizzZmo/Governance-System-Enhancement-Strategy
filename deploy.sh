# File: scripts/deploy.sh

# Exit immediately if a command exits with a non-zero status.
set -e

echo "🚀 Building and Deploying Sui Governance Package..."

# Define your package path (assuming the script is run from the root of hybrid-governance)
PACKAGE_PATH="." 

# Ensure you are in the correct directory (where Move.toml is located)
# cd /path/to/hybrid-governance 

echo "🛠️ Building Sui package at path: $PACKAGE_PATH"
sui move build --path "$PACKAGE_PATH"

echo "🚢 Publishing Sui package..."
# Adjust gas budget as needed. This is a placeholder value.
# The output of this command will contain the package ID and created objects.
# Capture the output to extract necessary IDs.
PUBLISH_OUTPUT=$(sui client publish --gas-budget 200000000 --path "$PACKAGE_PATH")

echo "✅ Deployment Attempted."
echo "📜 Full Publish Output:"
echo "$PUBLISH_OUTPUT"

# --- Extracting IDs (Example - requires jq for robust JSON parsing) ---
# This part is crucial for interacting with your package later.
# The output format of `sui client publish` can change, so adapt as needed.
# Assuming the output contains JSON with objectChanges or similar.

# Example using grep and awk (less robust than jq):
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | grep -o -E 'packageID":\s*"([^"]+)"' | grep -o -E '0x[0-9a-fA-F]+' | head -n 1)
# For objects created, you'd parse the "created" section of objectChanges.
# For example, to get the TotalSystemStake shared object ID:
# TOTAL_SYSTEM_STAKE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | contains("::delegation_staking::TotalSystemStake")) | .objectId')


if [ -n "$PACKAGE_ID" ]; then
    echo "🎉 Package ID: $PACKAGE_ID"
    echo "📌 You should update your Move.toml and any client-side configurations with this ID."
    # echo "TotalSystemStake Object ID: $TOTAL_SYSTEM_STAKE_ID" # If extracted
else
    echo "⚠️ Could not automatically extract Package ID. Please check the output above."
fi

echo "🔗 Next steps: Initialize any required states in your modules using the CLI or scripts."
echo "For example, calling init functions if they are public entry and need specific arguments not handled by one-time init."
