# 🚀 K3s System Upgrade Controller

Automates k3s cluster upgrades by monitoring the stable release channel.

## 📋 What's Deployed

- **system-upgrade-controller**: Monitors for new k3s releases and orchestrates upgrades
- **k3s-server Plan**: Automatically upgrades k3s when new stable versions are released
- **Discord Notifications**: Get notified on Discord when upgrades start/complete

## 🔔 Setting Up Discord Notifications

### 1. Create Discord Webhook

1. Open your Discord server
2. Go to **Server Settings** → **Integrations** → **Webhooks**
3. Click **New Webhook** or **Create Webhook**
4. Name it something like "K3s Upgrades"
5. Choose the channel where you want notifications
6. Copy the **Webhook URL**

### 2. Create Sealed Secret

Run this command on your local machine (replace `YOUR_WEBHOOK_URL`):

```bash
kubectl --kubeconfig ~/.kube/k3s-config create secret generic discord-webhook \
  --from-literal=address='YOUR_WEBHOOK_URL_HERE' \
  --namespace=system-upgrade \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/system-upgrade-controller/discord-webhook-sealed-secret.yaml
```

### 3. Enable Notifications

Edit `kustomization.yaml` and uncomment these lines:

```yaml
  - discord-webhook-sealed-secret.yaml
  - discord-provider.yaml
  - alert.yaml
```

### 4. Commit and Push

The webhook will be deployed automatically via Flux!

## 📊 Monitoring Upgrades

```bash
# Check for available upgrades
kubectl --kubeconfig ~/.kube/k3s-config get plans -n system-upgrade

# Watch upgrade progress
kubectl --kubeconfig ~/.kube/k3s-config get jobs -n system-upgrade -w

# View upgrade logs
kubectl --kubeconfig ~/.kube/k3s-config logs -n system-upgrade -l upgrade.cattle.io/component=upgrade-job -f

# Check controller status
kubectl --kubeconfig ~/.kube/k3s-config get pods -n system-upgrade
kubectl --kubeconfig ~/.kube/k3s-config logs -n system-upgrade -l upgrade.cattle.io/controller=system-upgrade-controller
```

## ⚙️ Configuration

### Upgrade Frequency

The controller checks for new versions every **15 minutes** (configurable in `rbac.yaml` → `SYSTEM_UPGRADE_PLAN_POLLING_INTERVAL`).

### Release Channel

Currently tracking the **stable** channel. To change:

Edit `plan-k3s.yaml`:
```yaml
channel: https://update.k3s.io/v1-release/channels/stable  # or latest, v1.33, etc.
```

### Available Channels

- `stable` - Stable releases (recommended)
- `latest` - Latest releases (may include RCs)
- `v1.33` - Specific version track
- `v1.32` - Previous version track

## 🎯 How It Works

1. 🔍 Controller polls the k3s release channel every 15 minutes
2. 📢 When a new version is detected, it creates an upgrade Job
3. 🔄 The Job:
   - Cordons the node (prevents new pod scheduling)
   - Downloads the new k3s binary
   - Replaces `/usr/local/bin/k3s`
   - Restarts the k3s service
   - Uncordons the node
4. ✅ Discord notification sent on completion
5. 🎉 Your cluster is now running the latest k3s!

## 🔐 Security Notes

- The controller uses `cluster-admin` role (required for node operations)
- Upgrade jobs run as privileged (needed to replace the k3s binary)
- The webhook URL is encrypted using Sealed Secrets

## 🛠️ Troubleshooting

### Upgrade Failed

```bash
# Check job status
kubectl --kubeconfig ~/.kube/k3s-config describe job -n system-upgrade

# Check logs
kubectl --kubeconfig ~/.kube/k3s-config logs -n system-upgrade -l upgrade.cattle.io/component=upgrade-job --tail=100
```

### Controller Not Running

```bash
kubectl --kubeconfig ~/.kube/k3s-config get pods -n system-upgrade
kubectl --kubeconfig ~/.kube/k3s-config logs -n system-upgrade deployment/system-upgrade-controller
```

### Discord Notifications Not Working

```bash
# Check provider
kubectl --kubeconfig ~/.kube/k3s-config get providers -n flux-system

# Check alert
kubectl --kubeconfig ~/.kube/k3s-config get alerts -n flux-system

# Check notification controller logs
kubectl --kubeconfig ~/.kube/k3s-config logs -n flux-system deployment/notification-controller
```
