# ClickHouse Deployment 🗄️

ClickHouse is a high-performance columnar database perfect for financial data analytics, time-series data, and complex analytical queries.

## 🔐 Security Features

This deployment includes several security layers:

1. **Password Authentication** - Sealed secrets for encrypted credential storage
2. **NetworkPolicy** - Restricts network access to authorized sources only
3. **SHA256 Password Hashing** - Passwords are never stored in plaintext
4. **TLS Encryption** - Automatic HTTPS via cert-manager and Let's Encrypt

## 📦 What's Included

- **StatefulSet** with persistent storage (20GB data, 5GB logs)
- **Services** for HTTP (8123) and native protocol (9000)
- **Ingress** with automatic TLS at `clickhouse.amajor.cloud`
- **NetworkPolicy** restricting access
- **Init container** that generates user configuration from sealed secrets
- **Health checks** (liveness and readiness probes)

## 🚀 Setup Instructions

### Step 1: Create Your Encrypted Secret

First, choose a strong password for your ClickHouse admin user. Then create an encrypted secret:

```bash
# Replace 'YOUR_STRONG_PASSWORD_HERE' with your actual password
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic clickhouse-auth \
  --namespace=clickhouse \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password='YOUR_STRONG_PASSWORD_HERE' \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/clickhouse/sealed-secret.yaml
```

**Tips:**
- Use a password manager to generate a strong password (20+ characters)
- You can change the username from 'admin' to anything you prefer
- The sealed-secret.yaml file is encrypted and safe to commit to git ✅

### Step 2: Enable the Sealed Secret

Edit `apps/base/clickhouse/kustomization.yaml` and uncomment the sealed-secret line:

```yaml
resources:
  - namespace.yaml
  - configmap.yaml
  - statefulset.yaml
  - service.yaml
  - ingress.yaml
  - networkpolicy.yaml
  - sealed-secret.yaml  # ← Uncomment this line
```

### Step 3: Commit and Push

The files are ready to deploy! Commit them to trigger Flux deployment:

```bash
# Review what you're committing
git status
git diff

# Commit the changes (I'll handle this for you based on your preferences)
```

Once pushed, Flux will automatically deploy ClickHouse within 10 minutes (or immediately via webhook).

### Step 4: Monitor Deployment

Watch the deployment progress:

```bash
# Watch ClickHouse pods starting up
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get pods -w

# Check the init container logs (this sets up authentication)
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse logs -l app=clickhouse -c setup-auth

# Check the main ClickHouse container logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse logs -l app=clickhouse -c clickhouse -f

# Check certificate status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get certificate
```

### Step 5: Access ClickHouse

Once deployed, you can access ClickHouse at:

**Web UI (Play interface):**
```
https://clickhouse.amajor.cloud/play
```

**HTTP API (for queries):**
```bash
# Example query via HTTP API
curl -u admin:YOUR_PASSWORD 'https://clickhouse.amajor.cloud/?query=SELECT%20version()'
```

**Native protocol (from within cluster):**
```bash
# Connect from another pod in the cluster
clickhouse-client --host=clickhouse-client.clickhouse.svc.cluster.local --user=admin --password=YOUR_PASSWORD
```

## 🔒 Security Details

### NetworkPolicy

The NetworkPolicy restricts access to:
- ✅ HTTP port (8123): Accessible only via Nginx Ingress
- ✅ Native protocol (9000): Only from pods within the clickhouse namespace
- ✅ Inter-server (9009): Only between ClickHouse pods (for future clustering)

This means:
- 🌐 You can access the web UI and HTTP API via the Ingress
- 🚫 Direct connections to the native protocol are blocked from outside
- 🔐 All access requires authentication

### How Authentication Works

1. **Sealed Secret** - Your password is encrypted using sealed-secrets
2. **Init Container** - On pod start, generates SHA256 hash of your password
3. **Users Config** - Creates `/etc/clickhouse-server/users.d/admin-user.xml` with hashed password
4. **ClickHouse** - Reads the config and requires authentication

Your plaintext password is only used during init (never stored on disk in plaintext).

## 📊 Using ClickHouse for Financial Data

ClickHouse excels at financial data analytics. Here's a quick example:

### Create a Stock Prices Table

```sql
CREATE TABLE stock_prices
(
    symbol String,
    timestamp DateTime,
    open Decimal(18, 2),
    high Decimal(18, 2),
    low Decimal(18, 2),
    close Decimal(18, 2),
    volume UInt64
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (symbol, timestamp);
```

### Insert Sample Data

```sql
INSERT INTO stock_prices VALUES
    ('AAPL', '2024-01-15 09:30:00', 185.50, 186.75, 185.20, 186.50, 1000000),
    ('AAPL', '2024-01-15 09:31:00', 186.50, 187.00, 186.25, 186.80, 950000);
```

### Query with Aggregations

```sql
-- Calculate daily OHLC
SELECT
    symbol,
    toDate(timestamp) as date,
    min(open) as open,
    max(high) as high,
    min(low) as low,
    max(close) as close,
    sum(volume) as total_volume
FROM stock_prices
WHERE symbol = 'AAPL'
GROUP BY symbol, date
ORDER BY date;
```

### Performance Tips

- ✅ Use `Decimal` types for financial data (not Float)
- ✅ Partition by time period (month/year)
- ✅ Order by commonly queried columns
- ✅ Use materialized views for common aggregations
- ✅ Enable compression (already configured with LZ4)

## 🔧 Configuration

### Memory Limits

Default limits (adjust in `statefulset.yaml` based on your cluster):
- **Requests:** 512Mi RAM, 250m CPU
- **Limits:** 4Gi RAM, 2000m CPU

### Storage

Default storage (adjust in `statefulset.yaml`):
- **Data:** 20Gi (persistent volume)
- **Logs:** 5Gi (persistent volume)

### Advanced Settings

Edit `configmap.yaml` to adjust:
- `max_memory_usage` - Memory limit per query
- `max_concurrent_queries` - Maximum parallel queries
- Compression settings
- Logging levels

## 🐛 Troubleshooting

### Pod won't start

```bash
# Check init container logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse logs -l app=clickhouse -c setup-auth

# Common issue: Sealed secret not created yet
# Solution: Follow Step 1 above to create it
```

### Can't connect

```bash
# Verify the service is running
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get svc

# Check if pods are ready
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get pods

# Verify NetworkPolicy allows your connection
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse describe networkpolicy clickhouse
```

### Authentication fails

```bash
# Verify the sealed secret was created correctly
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get sealedsecret

# Check if the secret was decrypted
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get secret clickhouse-auth

# Review init container logs for password hash generation
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse logs -l app=clickhouse -c setup-auth
```

### Certificate not issued

```bash
# Check certificate status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get certificate

# View cert-manager logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n cert-manager logs -l app.kubernetes.io/name=cert-manager -f

# Verify ingress is configured
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n clickhouse get ingress
```

## 📚 Resources

- [ClickHouse Documentation](https://clickhouse.com/docs)
- [SQL Reference](https://clickhouse.com/docs/en/sql-reference)
- [Financial Data Best Practices](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- [Performance Optimization](https://clickhouse.com/docs/en/operations/optimizing-performance)

## 🎯 Next Steps

Once ClickHouse is running:

1. 📊 **Access the Play UI** at https://clickhouse.amajor.cloud/play
2. 🗄️ **Create your first database and tables** for financial data
3. 📈 **Import historical data** from your data sources
4. 🔍 **Run analytical queries** to analyze your financial data
5. 🚀 **Consider setting up:**
   - Materialized views for pre-aggregated data
   - Scheduled imports from data sources
   - Backup strategy for critical data
   - Additional users with restricted permissions

Happy querying! 🎉
