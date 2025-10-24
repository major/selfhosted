# 📧 hvcwatch - Trading Alert Monitor

A bot that watches Fastmail inbox for ThinkOrSwim trading alerts and posts them to Discord and optionally Mastodon.

## 📦 Container Image

- **Image**: `ghcr.io/major/hvcwatch:latest`
- **Source**: https://github.com/major/hvcwatch

## 🔐 Creating the Sealed Secret

Before deploying hvcwatch, you need to create a sealed secret with your credentials.

### Required Credentials

- **📧 fastmail-user**: Your Fastmail email address
- **🔑 fastmail-pass**: Your Fastmail app-specific password
- **🔔 discord-webhook-url**: Discord webhook URL for notifications
- **📊 polygon-api-key**: API key from https://polygon.io/dashboard/api-keys

### Optional Credentials

- **🐘 mastodon-server-url**: Mastodon instance URL (e.g., `https://mastodon.social`)
- **🔑 mastodon-access-token**: Mastodon access token for posting statuses

### Creating the Sealed Secret

**Option 1: With Mastodon notifications**

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic hvcwatch-secrets \
  --namespace=hvcwatch \
  --from-literal=fastmail-user='your-email@fastmail.com' \
  --from-literal=fastmail-pass='your-app-specific-password' \
  --from-literal=discord-webhook-url='https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN' \
  --from-literal=polygon-api-key='your-polygon-api-key' \
  --from-literal=mastodon-server-url='https://mastodon.social' \
  --from-literal=mastodon-access-token='your-mastodon-access-token' \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/hvcwatch/sealed-secret.yaml
```

**Option 2: Without Mastodon notifications**

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic hvcwatch-secrets \
  --namespace=hvcwatch \
  --from-literal=fastmail-user='your-email@fastmail.com' \
  --from-literal=fastmail-pass='your-app-specific-password' \
  --from-literal=discord-webhook-url='https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN' \
  --from-literal=polygon-api-key='your-polygon-api-key' \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/hvcwatch/sealed-secret.yaml
```

### Getting Mastodon Access Token

If you want to post alerts to Mastodon:

1. Go to your Mastodon instance (e.g., https://mastodon.social)
2. Navigate to **Preferences → Development → New Application**
3. Give your app a name (e.g., "HVC Watch Bot")
4. Required scopes: `write:statuses`
5. Save and copy the access token

## ⚙️ Configuration

The deployment is configured with the following defaults:

- **IMAP_HOST**: `imap.fastmail.com`
- **IMAP_PORT**: `993`
- **IMAP_FOLDER**: `Trading/ToS Alerts`
- **LOG_LEVEL**: `INFO`

To customize these values, edit `deployment.yaml` and modify the environment variables.

## 🚀 Deployment

After creating the sealed secret:

1. Commit the `sealed-secret.yaml` file to git
2. Push to the `main` branch
3. Flux will automatically deploy (immediately via webhook or within 10 minutes via polling)

To force immediate reconciliation:

```bash
flux reconcile kustomization apps
```

## 📊 Monitoring

Check deployment status:

```bash
# Check pod status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch get pods

# View logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch logs -l app=hvcwatch -f

# Check deployment
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch get deployment
```

## 🔍 Troubleshooting

### Pod not starting

Check if the sealed secret was created correctly:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch get sealedsecrets
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch get secrets
```

### Secret decryption errors

If you see "no key could decrypt secret", the sealed secret was encrypted with a different controller's key. Re-create the sealed secret using the commands above.

### Email connection issues

Check the logs for IMAP connection errors:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n hvcwatch logs -l app=hvcwatch --tail=100
```

Verify your Fastmail credentials and that you're using an app-specific password (not your main account password).

## 📁 Files

- **namespace.yaml** - Creates the `hvcwatch` namespace
- **deployment.yaml** - Deployment configuration using `ghcr.io/major/hvcwatch:latest`
- **sealed-secret.yaml** - Encrypted credentials (you create this)
- **kustomization.yaml** - Kustomize configuration
- **secret-template.yaml** - Template with instructions (reference only)
