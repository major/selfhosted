# 🔔 kwatch - Kubernetes Event Watcher

**kwatch** is a lightweight Kubernetes event monitoring tool that sends real-time notifications to Discord when pod issues occur (CrashLoopBackOff, ImagePullBackOff, etc.).

## 🎯 What It Monitors

- 💥 **CrashLoopBackOff** - Pods continuously crashing
- 🖼️ **ImagePullBackOff** - Container image pull failures
- 📦 **ErrImagePull** - Image pull errors
- ❌ **Failed** - General failures
- 📅 **FailedScheduling** - Pod scheduling issues
- 💾 **FailedMount** - Volume mount failures
- 🤒 **Unhealthy** - Health check failures
- And more...

## 📦 Components

- **Namespace**: `kwatch`
- **ServiceAccount**: `kwatch` with ClusterRole for read-only access to events and pods
- **ConfigMap**: Configuration file with Discord webhook settings
- **SealedSecret**: Encrypted Discord webhook URL
- **Deployment**: Single replica running `ghcr.io/abahmed/kwatch:v0.10.3`

## 🚀 Setup Instructions

✅ **Already configured!** This deployment reuses the same Discord webhook as `flux-notifications`.

The SealedSecret has been created and is ready to deploy. Simply commit and push to trigger deployment via Flux GitOps.

### 📝 If You Need to Update the Webhook

The configuration includes the cluster name `selfhosted` so alerts clearly identify which cluster has issues.

If you need to change the Discord webhook URL or other settings in the future, use the script in the "Updating the Configuration" section above.

## 🔧 Configuration

The kwatch configuration is stored in `sealed-config.yaml` (encrypted). See `config-template.yaml` for the expected format.

**Important Configuration Options:**

- **app.clusterName**: Set to `selfhosted` to identify which cluster alerts are from
- **maxRecentLogLines**: Number of log lines to include (default: 50)
- **namespaces**: Filter specific namespaces (leave empty for all)
- **reasons**: Filter specific event types (leave empty for all)
- **ignoreContainerNames**: Exclude specific containers (e.g., sidecars)

### Updating the Configuration

To update the sealed configuration with the cluster name:

```bash
# Step 1: Get the Discord webhook URL from flux-notifications
WEBHOOK_URL=$(kubectl --kubeconfig ~/.kube/k3s-psychz-config -n flux-system get secret discord-webhook -o jsonpath='{.data.address}' | base64 -d)

# Step 2: Create a new config.yaml with cluster name
cat > config.yaml << EOF
app:
  clusterName: selfhosted

maxRecentLogLines: 50

alert:
  discord:
    webhook: ${WEBHOOK_URL}

namespaces: []
reasons: []
ignoreContainerNames: []
EOF

# Step 3: Create and seal the secret
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic kwatch-config \
  --from-file=config.yaml=config.yaml \
  --namespace=kwatch \
  --dry-run=client -o yaml | \
/home/major/bin/kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > sealed-config.yaml

# Step 4: Clean up the unencrypted config
rm config.yaml
```

## 📊 Monitoring

Check kwatch status:

```bash
# View kwatch pod
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n kwatch get pods

# View logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n kwatch logs -l app=kwatch -f

# Check configuration
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n kwatch get configmap kwatch -o yaml
```

## 🧪 Testing

To test the Discord notifications, create a failing pod:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config run test-crash \
  --image=busybox \
  --restart=Always \
  -- /bin/sh -c "exit 1"
```

You should receive a Discord notification within seconds! 🎉

To clean up:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config delete pod test-crash
```

## 🔗 Resources

- **GitHub**: https://github.com/abahmed/kwatch
- **Discord Community**: https://discord.gg/kzJszdKmJ7
- **Documentation**: https://kwatch.dev

## 💡 Tips

- Start with monitoring all namespaces, then narrow down if too noisy
- Use `ignoreContainerNames` to exclude noisy sidecars (istio-proxy, etc.)
- The 5-minute deduplication window prevents notification spam
- Check kwatch logs if notifications aren't arriving
