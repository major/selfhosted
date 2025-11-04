# 📊 Thetagang Notifications

Monitors r/thetagang subreddit for trade notifications and sends them to Discord.

## 📝 Description

This application monitors thetagang trades and sends real-time notifications to Discord. It uses Redis for caching and persistent storage for maintaining state across restarts.

## 🏗️ Architecture

- **Namespace**: `thetagang`
- **Image**: `ghcr.io/major/thetagang-notifications:main@sha256:a5659bb73ebe5ae0246f7c3b0168c26913b52e214c1526ee297d695e99db37ad`
- **Storage**: 1Gi PersistentVolumeClaim mounted at `/storage`
- **Redis**: Connects to Redis in `redis-system` namespace via `redis.redis-system.svc.cluster.local:6379`
- **Security**: Read-only root filesystem enabled

## 🔧 Configuration

### Environment Variables

**From SealedSecret** (`thetagang-secrets`):
- `WEBHOOK_URL_TRADES` - Discord webhook URL for trade notifications
- `TRADES_API_KEY` - API key for trades authentication

**Direct Configuration**:
- `DAEMONIZE_TRADE_BOT=1` - Run as a daemon process
- `PATRON_TRADES_ONLY=1` - Only monitor patron trades
- `STORAGE_DIR=/storage` - Persistent storage directory
- `SKIPPED_USERS=antithetagang,jrue` - Users to skip in monitoring
- `REDIS_HOST=redis.redis-system.svc.cluster.local` - Redis service hostname
- `REDIS_PORT=6379` - Redis port

## 🔐 Secrets Management

Sensitive credentials are stored as a SealedSecret. To update credentials:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic thetagang-secrets \
  --namespace=thetagang \
  --from-literal=webhook-url-trades='YOUR_WEBHOOK_URL' \
  --from-literal=trades-api-key='YOUR_API_KEY' \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/thetagang-notifications/sealed-secret.yaml
```

See `secret-template.yaml` for the complete template.

## 📦 Resources

- **Memory Request**: 128Mi
- **Memory Limit**: 256Mi
- **CPU Request**: 100m
- **CPU Limit**: 500m
- **Storage**: 1Gi (ReadWriteOnce)

## 🔗 Dependencies

- **Redis** - Must be running in `redis-system` namespace
- **SealedSecrets** - For encrypted secret management

## 🚀 Deployment

The application is automatically deployed by Flux when changes are pushed to the `main` branch.

### Manual Operations

```bash
# Force reconciliation
flux reconcile kustomization apps

# Check deployment status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang get pods

# View logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang logs -l app=thetagang-notifications -f

# Check Redis connectivity
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang exec -it deployment/thetagang-notifications -- sh
```

## 🔍 Troubleshooting

### Redis Connection Issues

If the application can't connect to Redis:

```bash
# Verify Redis is running
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n redis-system get pods

# Test DNS resolution from the pod
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang exec -it deployment/thetagang-notifications -- nslookup redis.redis-system.svc.cluster.local
```

### Secret Decryption Issues

If the SealedSecret fails to decrypt:

1. Verify the sealed-secrets controller is running:
   ```bash
   kubectl --kubeconfig ~/.kube/k3s-psychz-config -n sealed-secrets get pods
   ```

2. Check the SealedSecret status:
   ```bash
   kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang get sealedsecrets
   ```

3. Re-seal the secret using the current controller's public key (see Secrets Management above)

### Storage Issues

If the persistent volume is not mounting:

```bash
# Check PVC status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang get pvc

# Check PV status
kubectl --kubeconfig ~/.kube/k3s-psychz-config get pv
```

## 📊 Monitoring

Check application logs for trade notifications:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n thetagang logs -l app=thetagang-notifications --tail=100 -f
```

## 🔄 Updates

Container images are managed via SHA256 hashes. To update to a new version:

1. Get the new image SHA:
   ```bash
   skopeo inspect docker://ghcr.io/major/thetagang-notifications:main | jq -r '.Digest'
   ```

2. Update the image reference in `deployment.yaml` with the new SHA256 hash

3. Commit and push - Flux will automatically deploy the update
