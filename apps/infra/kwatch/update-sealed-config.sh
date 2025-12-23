#!/bin/bash
# Script to update kwatch sealed config with cluster name
# This script must be run on a machine with kubectl access to the cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-~/.kube/k3s-psychz-config}"
KUBESEAL_PATH="${KUBESEAL_PATH:-/home/major/bin/kubeseal}"

echo "🔧 Updating kwatch configuration with cluster name..."
echo ""

# Step 1: Get the Discord webhook URL from flux-notifications
echo "📥 Step 1: Retrieving Discord webhook URL from flux-notifications..."
WEBHOOK_URL=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n flux-system get secret discord-webhook -o jsonpath='{.data.address}' | base64 -d)

if [ -z "$WEBHOOK_URL" ]; then
    echo "❌ Error: Could not retrieve Discord webhook URL"
    exit 1
fi

echo "✅ Retrieved webhook URL"
echo ""

# Step 2: Create config.yaml with cluster name
echo "📝 Step 2: Creating config.yaml with cluster name placeholder..."
cat > /tmp/kwatch-config.yaml << 'EOF'
app:
  clusterName: ${CLUSTER_NAME}

maxRecentLogLines: 50

alert:
  discord:
    webhook: WEBHOOK_URL_PLACEHOLDER

namespaces: []
reasons: []
ignoreContainerNames: []
EOF

# Replace the webhook placeholder with the actual URL
sed -i "s|WEBHOOK_URL_PLACEHOLDER|${WEBHOOK_URL}|g" /tmp/kwatch-config.yaml

echo "✅ Created config.yaml"
echo ""

# Step 3: Create and seal the secret
echo "🔒 Step 3: Sealing the configuration..."
kubectl --kubeconfig "$KUBECONFIG_PATH" create secret generic kwatch-config \
  --from-file=config.yaml=/tmp/kwatch-config.yaml \
  --namespace=kwatch \
  --dry-run=client -o yaml | \
"$KUBESEAL_PATH" --kubeconfig "$KUBECONFIG_PATH" \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > "$SCRIPT_DIR/sealed-config.yaml"

echo "✅ Created sealed-config.yaml"
echo ""

# Step 4: Clean up
echo "🧹 Step 4: Cleaning up temporary files..."
rm /tmp/kwatch-config.yaml
echo "✅ Cleanup complete"
echo ""

echo "✨ Done! The sealed-config.yaml has been updated with cluster name 'selfhosted'"
echo "📤 Please commit and push the updated sealed-config.yaml file"
