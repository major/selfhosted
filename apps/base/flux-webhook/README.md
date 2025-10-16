# 🪝 Flux GitHub Webhook Receiver

GitHub webhook receiver for instant Flux reconciliation. Instead of waiting up to 10 minutes for Flux's polling interval, webhooks trigger immediate reconciliation when you push to the `main` branch.

## 📦 Components

- **Flux Receiver**: Receives GitHub webhook events and triggers GitRepository reconciliation
- **Ingress**: Exposes the webhook endpoint at `webhook.amajor.cloud/hook/`
- **Network Policy**: Allows traffic from nginx ingress controller
- **Sealed Secret**: Encrypted webhook token for authentication

## 🔐 Creating the Sealed Secret

The webhook requires a secret token for authentication between GitHub and Flux.

### Generate a Random Token

First, generate a secure random token:

```bash
# Generate a random token (save this for GitHub webhook configuration)
TOKEN=$(openssl rand -hex 32)
echo "Your webhook token: $TOKEN"
```

### Create the Sealed Secret

```bash
# Replace YOUR_TOKEN_HERE with the token generated above
kubectl --kubeconfig ~/.kube/k3s-config create secret generic webhook-token \
  --namespace=flux-system \
  --from-literal=token='YOUR_TOKEN_HERE' \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/flux-webhook/webhook-token-secret.yaml
```

## ⚙️ GitHub Webhook Configuration

After deploying the webhook receiver, configure GitHub to send webhook events:

1. Go to your repository: https://github.com/major/selfhosted
2. Navigate to **Settings → Webhooks → Add webhook**
3. Configure the webhook:
   - **Payload URL**: Get the URL from the receiver:
     ```bash
     kubectl --kubeconfig ~/.kube/k3s-config -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}'
     ```
     The full URL will be: `https://webhook.amajor.cloud/hook/<receiver-id>`

   - **Content type**: `application/json`
   - **Secret**: Use the same token you generated earlier
   - **SSL verification**: Enable
   - **Which events**: Select "Just the push event"
   - **Active**: ✅ Enable

4. Click **Add webhook**

## 🚀 Deployment

After creating the sealed secret:

1. Commit the `webhook-token-secret.yaml` file to git
2. Push to the `main` branch
3. Flux will automatically deploy
4. Configure the GitHub webhook (see above)

To force immediate reconciliation:

```bash
flux reconcile kustomization apps
```

## 🔍 Verification

### Check Receiver Status

```bash
# Get receiver status
kubectl --kubeconfig ~/.kube/k3s-config -n flux-system get receiver github-receiver

# Get webhook URL
kubectl --kubeconfig ~/.kube/k3s-config -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}'
```

### Test the Webhook

After configuring the GitHub webhook:

1. Make a small change to the repository
2. Push to `main`
3. Check GitHub webhook deliveries (Settings → Webhooks → Recent Deliveries)
4. Verify Flux reconciliation:

```bash
# Watch for reconciliation
flux logs --level=info --follow

# Check when last reconciliation occurred
flux get sources git
```

### View Receiver Logs

```bash
kubectl --kubeconfig ~/.kube/k3s-config -n flux-system logs -l app=notification-controller --tail=100
```

## 🔧 Troubleshooting

### Webhook Delivery Fails

Check GitHub webhook delivery details (Settings → Webhooks → Recent Deliveries) for error messages.

Common issues:
- **SSL certificate error**: Ensure cert-manager has issued the certificate for `webhook.amajor.cloud`
- **401 Unauthorized**: Token mismatch between GitHub and sealed secret
- **Timeout**: Check ingress and network policy configuration

### Secret Decryption Errors

If you see "no key could decrypt secret", re-create the sealed secret:

```bash
# Get a fresh token or use your existing one
TOKEN="your-existing-token"

kubectl --kubeconfig ~/.kube/k3s-config create secret generic webhook-token \
  --namespace=flux-system \
  --from-literal=token="$TOKEN" \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/flux-webhook/webhook-token-secret.yaml
```

### Receiver Not Found

Verify the receiver was created:

```bash
kubectl --kubeconfig ~/.kube/k3s-config -n flux-system get receivers
```

If missing, check Flux logs:

```bash
flux logs --level=error
```

## 📊 Monitoring

### Check Webhook Activity

```bash
# View recent webhook events in GitHub
# Go to: Settings → Webhooks → Recent Deliveries

# View Flux reconciliation history
flux events --for=GitRepository/flux-system

# Watch reconciliation in real-time
watch -n 1 'flux get sources git'
```

### Performance

With webhooks enabled:
- **Without webhook**: Reconciliation every ~10 minutes (polling)
- **With webhook**: Reconciliation within seconds of push event

## 📁 Files

- **receiver.yaml** - Flux Receiver resource configuration
- **ingress.yaml** - Ingress exposing webhook endpoint at `webhook.amajor.cloud`
- **networkpolicy.yaml** - Network policy allowing nginx ingress traffic
- **webhook-token-secret.yaml** - Encrypted webhook token (you create this)
- **kustomization.yaml** - Kustomize configuration

## 🔗 References

- [Flux Webhook Receivers Documentation](https://fluxcd.io/flux/guides/webhook-receivers/)
- [GitHub Webhooks Documentation](https://docs.github.com/en/webhooks)
- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
