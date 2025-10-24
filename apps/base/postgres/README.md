# 🐘 PostgreSQL with CloudNativePG

PostgreSQL deployment using CloudNativePG operator for Kubernetes-native database management.

## Architecture

- **Operator**: CloudNativePG operator (deployed in `cnpg-system` namespace)
- **Database**: Single-instance PostgreSQL 16 cluster
- **Storage**: 20Gi PersistentVolume using K3s `local-path` storage class
- **GUI**: Adminer web interface at `adminer.amajor.cloud`
- **External Access**: TCP port 5432 exposed via Nginx Ingress LoadBalancer

## Deployment Details

### PostgreSQL Cluster

- **Cluster Name**: `postgres`
- **Namespace**: `postgres`
- **Instances**: 1 (single instance, suitable for dev/testing)
- **Primary Service**: `postgres-rw` (read-write endpoint)
- **Storage**: 20Gi PVC

### Initial Configuration

The cluster is bootstrapped with:
- **Default Database**: `postgres` (PostgreSQL default)
- **Superuser**: `postgres`

The superuser password is stored in a sealed secret:
- `postgres-superuser` - superuser credentials

All application users and databases should be created manually via SQL.

### Connection Details

**Internal (from within cluster):**
```
Host: postgres-rw.postgres.svc.cluster.local
Port: 5432
Database: postgres (or your custom database)
Username: postgres (or your custom user)
```

**External (from internet):**
```
Host: <nginx-ingress-loadbalancer-ip>
Port: 5432
Database: postgres (or your custom database)
Username: postgres (or your custom user)
```

To get the LoadBalancer IP:
```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n ingress-nginx get svc ingress-nginx-controller
```

### Adminer Web UI

Adminer is accessible at: **https://adminer.amajor.cloud**

- **Default Server**: `postgres-rw` (automatically filled in)
- **Username**: `postgres` (or your custom users)
- **Password**: Stored in sealed secrets (see command below)
- **Database**: `postgres` (or leave blank to see all databases)

## Getting Database Password

To retrieve the postgres superuser password (requires kubectl access):

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get secret postgres-superuser -o jsonpath='{.data.password}' | base64 -d
```

## User Management

### Current Users

1. **postgres** (superuser)
   - Full administrative privileges
   - Use for database administration, creating new databases, users, etc.
   - Manage all users and permissions from this account

### Creating Additional Users

Connect to the database and run:

```sql
-- Create a new user
CREATE USER myuser WITH PASSWORD 'secure_password';

-- Grant privileges on a database
GRANT ALL PRIVILEGES ON DATABASE app TO myuser;

-- Grant privileges on specific tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myuser;
```

## Security Considerations

- 🔒 TLS connections enforced via `scram-sha-256` authentication
- 🔐 Passwords stored as sealed secrets (encrypted at rest)
- ⚠️ **Port 5432 is exposed to the internet** - ensure strong passwords
- 🔑 Consider IP whitelisting if possible (via nginx-ingress annotations)
- 🌐 Adminer accessible via HTTPS with Let's Encrypt certificate

## Monitoring and Maintenance

### Check Cluster Status

```bash
# View cluster status
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get cluster postgres

# View pods
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get pods

# View services
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get svc

# Check cluster details
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres describe cluster postgres
```

### View Logs

```bash
# PostgreSQL logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres logs -l cnpg.io/cluster=postgres -f

# Adminer logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres logs -l app=adminer -f
```

### Backup and Recovery

CloudNativePG supports automated backups to S3 or local storage. This can be configured by adding a backup section to `cluster.yaml`. For now, manual backups can be done:

```bash
# Exec into the pod
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres exec -it postgres-1 -- bash

# Create backup using pg_dump
pg_dump -U postgres app > /tmp/backup.sql
```

## Troubleshooting

### Cluster Not Starting

```bash
# Check operator logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n cnpg-system logs -l app.kubernetes.io/name=cloudnative-pg -f

# Check cluster events
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres describe cluster postgres
```

### Connection Issues

1. Verify the LoadBalancer IP is accessible
2. Check if port 5432 is open in firewall
3. Verify sealed secrets were properly decrypted
4. Check pod logs for authentication errors

### Adminer Can't Connect

- Ensure you're using `postgres-rw` as the server name
- Verify credentials are correct
- Check that the cluster is running: `kubectl get cluster -n postgres`

## Upgrading

CloudNativePG handles PostgreSQL version upgrades gracefully. Update the image version in `cluster.yaml` and Flux will automatically apply the upgrade.

## Resource Usage

- **PostgreSQL**: 512Mi-1Gi memory, 500m-1000m CPU
- **Adminer**: 64Mi-128Mi memory, 50m CPU
- **Storage**: 20Gi (can be increased by editing `cluster.yaml`)

## Dependencies

This deployment depends on:
- CloudNativePG operator (apps/infra/cloudnative-pg)
- Sealed Secrets (apps/bootstrap-infra/sealed-secrets)
- Nginx Ingress Controller (apps/infra/nginx-ingress)
- Cert-manager (apps/infra/cert-manager)
