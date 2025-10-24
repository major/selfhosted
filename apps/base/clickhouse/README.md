# ClickHouse Deployment 🐘

This deploys ClickHouse using the [Altinity Helm Chart](https://github.com/Altinity/helm-charts/tree/main/charts/clickhouse) for a production-ready analytical database.

## Architecture 🏗️

- **Single-node deployment** (no clustering/replication currently)
- **Persistent storage**: 20Gi for data, 5Gi for logs
- **Web access**: `clickhouse.amajor.cloud` with automatic TLS
- **Authentication**: Password-based via SealedSecret
- **Resources**: 512Mi-4Gi RAM, 250m-2 CPU cores

## Components 📦

| File | Purpose |
|------|---------|
| `repository.yaml` | Altinity Helm repository |
| `release.yaml` | HelmRelease with ClickHouse configuration |
| `namespace.yaml` | Namespace definition |
| `sealed-secret-default.yaml` | Encrypted password for 'default' user |
| `sealed-secret-major.yaml` | Encrypted password for 'major' user (your admin account) |
| `ingress.yaml` | HTTPS ingress with cert-manager TLS |
| `secret-template.yaml` | Template for creating/updating passwords |

## Users 👥

This setup creates two users:

- **`default`** - Required by ClickHouse, restricted to localhost only (for internal use)
- **`major`** - Your admin user with full privileges and external access

You'll primarily use the `major` user for all your work.

## Initial Setup 🚀

### 1. Create the Sealed Secrets

Each user needs a separate sealed secret. Update passwords and seal them:

```bash
# Seal the 'default' user password (restricted to localhost)
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic clickhouse-default-auth \
  --from-literal=password=YOUR_DEFAULT_USER_PASSWORD \
  --namespace=clickhouse \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/clickhouse/sealed-secret-default.yaml

# Seal the 'major' user password (your main admin account)
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic clickhouse-major-auth \
  --from-literal=password=YOUR_MAJOR_USER_PASSWORD \
  --namespace=clickhouse \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/clickhouse/sealed-secret-major.yaml
```

### 2. Deploy via Flux

Flux automatically deploys ClickHouse when you commit the changes:

```bash
# Force immediate reconciliation (optional)
flux reconcile kustomization apps --kubeconfig ~/.kube/k3s-psychz-config
```

### 3. Verify Deployment

```bash
# Check HelmRelease status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get helmrelease

# Check pod status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get pods

# Check persistent volumes
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get pvc
```

## Accessing ClickHouse 🔌

### Via Web Interface

Visit: `https://clickhouse.amajor.cloud`

- **Username**: `major`
- **Password**: Your major user password

### Via CLI (from within cluster)

```bash
# As the 'major' user (recommended)
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse exec -it clickhouse-0 -- clickhouse-client -u major --password YOUR_MAJOR_PASSWORD

# As the 'default' user (localhost only, limited access)
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse exec -it clickhouse-0 -- clickhouse-client
```

### Via Native Client

```bash
clickhouse-client --host clickhouse.amajor.cloud --secure --port 9440 --user major --password YOUR_MAJOR_PASSWORD
```

## Configuration ⚙️

Key settings in `release.yaml`:

- **Storage**: Configured via `clickhouse.persistence.*`
- **Resources**: Set via `clickhouse.resources.*`
- **Performance**: Tuned via `clickhouse.configOverride.*`
- **Authentication**: References `clickhouse-auth` secret

## Upgrading 📈

### Upgrade ClickHouse Version

Edit `release.yaml` and update the version:

```yaml
spec:
  chart:
    spec:
      version: '0.3.2'  # Update this
```

Flux will automatically roll out the upgrade.

### Scale to Multi-Node Cluster

To enable clustering (requires Keeper):

```yaml
values:
  keeper:
    enabled: true
  clickhouse:
    replicas: 3  # Number of ClickHouse nodes
```

## Troubleshooting 🔧

### Check HelmRelease Status

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse describe helmrelease clickhouse
```

### View Pod Logs

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse logs -f clickhouse-0
```

### Check Secrets

```bash
# Verify the sealed secrets were decrypted
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get secrets

# Check specific secret
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get secret clickhouse-major-auth -o yaml
```

### Common Issues

**HelmRelease fails to install:**
- Check that the HelmRepository is synced: `kubectl -n clickhouse get helmrepository`
- View detailed error: `kubectl -n clickhouse describe helmrelease clickhouse`

**Pod won't start:**
- Check PVC status: `kubectl -n clickhouse get pvc`
- Check events: `kubectl -n clickhouse get events --sort-by='.lastTimestamp'`

**Can't connect to ClickHouse:**
- Verify service exists: `kubectl -n clickhouse get svc`
- Check ingress: `kubectl -n clickhouse get ingress`
- Test internal connectivity: `kubectl -n clickhouse exec clickhouse-0 -- clickhouse-client -q "SELECT 1"`

## Resources 📚

- [Altinity ClickHouse Helm Chart](https://github.com/Altinity/helm-charts/tree/main/charts/clickhouse)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Flux HelmRelease Guide](https://fluxcd.io/docs/components/helm/)
