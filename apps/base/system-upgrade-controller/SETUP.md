# 🚀 Quick Setup Guide

## ✅ What's Been Created

All the k3s upgrade controller manifests are ready! Here's what will be deployed:

1. 🤖 **System Upgrade Controller** - Monitors k3s releases
2. 📋 **K3s Server Plan** - Auto-upgrades to stable releases
3. 🔔 **Discord Notifications** - Get notified of upgrades (needs setup)

## 🎯 Next Steps

### 1. Create Discord Webhook (2 minutes)

1. Go to your Discord server
2. **Server Settings** → **Integrations** → **Webhooks** → **New Webhook**
3. Name it "K3s Upgrades"
4. Choose your notification channel
5. **Copy the Webhook URL**

### 2. Create Sealed Secret (1 command)

```bash
kubectl --kubeconfig ~/.kube/k3s-config create secret generic discord-webhook \
  --from-literal=address='PASTE_YOUR_WEBHOOK_URL_HERE' \
  --namespace=system-upgrade \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/system-upgrade-controller/discord-webhook-sealed-secret.yaml
```

### 3. Enable Notifications

Edit `apps/base/system-upgrade-controller/kustomization.yaml` and uncomment these lines:

```yaml
  # - discord-webhook-sealed-secret.yaml
  # - discord-provider.yaml
  # - alert.yaml                 # K3s upgrade notifications
  # - alert-flux-all.yaml        # General Flux notifications (recommended!)
```

Remove the `#` at the start of each line.

💡 **Tip**: Enable both alerts to get notified about:
- K3s upgrades (alert.yaml)
- All Flux reconciliations, errors, and updates (alert-flux-all.yaml)

### 4. Commit Changes

Push your changes and let Flux deploy everything!

## 🧪 Testing

Once deployed, you can test the notification:

```bash
# Trigger a test alert
kubectl --kubeconfig ~/.kube/k3s-config -n flux-system patch alert k3s-upgrade-notifications \
  --type=json -p='[{"op": "add", "path": "/metadata/annotations/test", "value": "true"}]'
```

## 📊 Verify Deployment

```bash
# Check controller is running
kubectl --kubeconfig ~/.kube/k3s-config get pods -n system-upgrade

# Check plan status
kubectl --kubeconfig ~/.kube/k3s-config get plans -n system-upgrade

# Should show: k3s-server with current version
```

## 🎉 That's It!

Your cluster will now automatically upgrade to new stable k3s releases and notify you on Discord!

Current behavior:
- ✅ Checks for updates every 15 minutes
- ✅ Follows the **stable** release channel
- ✅ Sends Discord notifications for all upgrade events
- ✅ Safe single-node upgrade (cordons during upgrade)
