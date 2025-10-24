# 📊 StockCharts Alerts

A Discord bot that monitors StockCharts' alerts page and redistributes notifications via Discord webhooks.

## 🚀 Deployment

This application is deployed as a Kubernetes Deployment without a web service (no Service or IngressRoute needed).

### 📦 Resources

- **Namespace**: `stockchartsalerts`
- **Deployment**: Runs the bot container from `ghcr.io/major/stockchartsalerts:latest`
- **SealedSecret**: Stores the Discord webhook URL securely

## 🔐 Creating the Sealed Secret

The bot requires a Discord webhook URL to send alerts. Follow these steps to create the sealed secret:

### 1️⃣ Create the Discord Webhook

1. Open your Discord server settings
2. Navigate to **Integrations** → **Webhooks**
3. Click **New Webhook** or **Create Webhook**
4. Configure the webhook (name, channel, avatar)
5. Copy the webhook URL

### 2️⃣ Seal the Secret

Replace `YOUR_DISCORD_WEBHOOK_URL` with your actual Discord webhook URL:

```bash
kubectl create secret generic stockchartsalerts-secrets \
  --from-literal=discord-webhook-url=YOUR_DISCORD_WEBHOOK_URL \
  --namespace=stockchartsalerts \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/stockchartsalerts/sealedsecret.yaml
```

### 3️⃣ Commit and Push

The sealed secret is safe to commit to Git. Once pushed, Flux will automatically apply it to the cluster.

## 🔧 Environment Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `SENTRY_DSN` | Sentry error tracking DSN | Hardcoded in deployment |
| `DISCORD_WEBHOOK_URL` | Discord webhook for sending alerts | SealedSecret |

## 📝 Useful Commands

### Check Deployment Status

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts get pods
```

### View Logs

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts logs -l app=stockchartsalerts -f
```

### Force Flux Reconciliation

```bash
flux reconcile kustomization apps
```

### Restart the Deployment

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts rollout restart deployment/stockchartsalerts
```

## 🐛 Troubleshooting

### Check if the secret exists

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts get secret stockchartsalerts-secrets
```

### Check deployment events

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts describe deployment stockchartsalerts
```

### Check pod events

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n stockchartsalerts describe pod -l app=stockchartsalerts
```

## 📊 Resource Limits

- **CPU Request**: 50m
- **CPU Limit**: 200m
- **Memory Request**: 64Mi
- **Memory Limit**: 256Mi

## 🔗 Links

- **Source Repository**: https://github.com/major/stockchartsalerts
- **Container Registry**: https://github.com/major/stockchartsalerts/pkgs/container/stockchartsalerts
