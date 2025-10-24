# 🚀 PostgreSQL Quick Reference

## 🔐 Getting Admin Credentials

### Username
```
postgres
```

### Password
```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  get secret postgres-superuser -o jsonpath='{.data.password}' | base64 -d && echo
```

## 🔗 Connection Information

### Internal Connection (from within K8s)
```
postgresql://postgres:<PASSWORD>@postgres-rw.postgres.svc.cluster.local:5432/postgres
```

### External Connection (from internet)
First get the LoadBalancer IP:
```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n ingress-nginx \
  get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' && echo
```

Then connect:
```
postgresql://postgres:<PASSWORD>@<LOADBALANCER-IP>:5432/postgres
```

### Adminer Web UI
```
URL: https://adminer.amajor.cloud
Server: postgres-rw
Username: postgres
Password: <get from command above>
Database: postgres
```

## 📊 Useful Management Commands

### Check Cluster Status
```bash
# View cluster health
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get cluster postgres

# View pods
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get pods

# View services
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get svc

# Describe cluster (detailed info)
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres describe cluster postgres
```

### View Logs
```bash
# PostgreSQL logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  logs -l cnpg.io/cluster=postgres -f

# Adminer logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  logs -l app=adminer -f
```

### Connect via psql (from within a pod)
```bash
# Exec into the PostgreSQL pod
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  exec -it postgres-1 -- psql -U postgres

# Or run a single command
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  exec -it postgres-1 -- psql -U postgres -c "SELECT version();"
```

### Connect via psql (from your local machine)
```bash
# Get the password first
export PGPASSWORD=$(kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  get secret postgres-superuser -o jsonpath='{.data.password}' | base64 -d)

# Get the LoadBalancer IP
export PGHOST=$(kubectl --kubeconfig ~/.kube/k3s-psychz-config -n ingress-nginx \
  get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Connect
psql -h $PGHOST -p 5432 -U postgres -d postgres
```

## 🛠️ Common SQL Tasks

### Create a New Database
```sql
CREATE DATABASE myapp;
```

### Create a New User
```sql
CREATE USER myappuser WITH PASSWORD 'secure_password';
```

### Grant Privileges
```sql
-- Full access to a database
GRANT ALL PRIVILEGES ON DATABASE myapp TO myappuser;

-- Connect and grant schema permissions
\c myapp
GRANT ALL ON SCHEMA public TO myappuser;
GRANT ALL ON ALL TABLES IN SCHEMA public TO myappuser;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO myappuser;

-- For future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO myappuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO myappuser;
```

### List Databases
```sql
\l
-- or
SELECT datname FROM pg_database;
```

### List Users
```sql
\du
-- or
SELECT usename FROM pg_user;
```

### List Tables
```sql
\dt
-- or
SELECT tablename FROM pg_tables WHERE schemaname = 'public';
```

### Check Connections
```sql
SELECT * FROM pg_stat_activity;
```

### Database Size
```sql
SELECT pg_database.datname,
       pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;
```

## 🔄 Backup and Restore

### Create Backup (from within pod)
```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  exec -it postgres-1 -- pg_dump -U postgres -d myapp > backup.sql
```

### Restore Backup (from within pod)
```bash
cat backup.sql | kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  exec -i postgres-1 -- psql -U postgres -d myapp
```

## 📈 Performance Monitoring

### Current Configuration
```sql
-- Show all settings
SHOW ALL;

-- Show specific settings
SHOW shared_buffers;
SHOW max_connections;
SHOW work_mem;
```

### Active Queries
```sql
SELECT pid, usename, application_name, state, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

### Kill Long-Running Query
```sql
-- Cancel query gracefully
SELECT pg_cancel_backend(PID);

-- Terminate connection forcefully
SELECT pg_terminate_backend(PID);
```

## 🚨 Troubleshooting

### Cluster Not Starting
```bash
# Check operator logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n cnpg-system \
  logs -l app.kubernetes.io/name=cloudnative-pg -f

# Check cluster events
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  describe cluster postgres
```

### Can't Connect
```bash
# Check if pod is running
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get pods

# Check service endpoints
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get endpoints

# Test connection from within cluster
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres \
  exec -it postgres-1 -- psql -U postgres -c "SELECT 1;"
```

### Adminer Not Working
```bash
# Check Adminer pod
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get pods -l app=adminer

# Check Adminer logs
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres logs -l app=adminer

# Check ingress
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n postgres get ingress
```

## 🔐 Security Best Practices

### Change Admin Password
```sql
ALTER USER postgres WITH PASSWORD 'new_secure_password';
```

**Note:** If you change the password, you'll need to update the sealed secret:
```bash
# Create new sealed secret with updated password
kubectl create secret generic postgres-superuser \
  --from-literal=username=postgres \
  --from-literal=password='new_secure_password' \
  --namespace=postgres \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/base/postgres/sealed-secret-superuser.yaml
```

### Create Read-Only User
```sql
CREATE USER readonly WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE myapp TO readonly;
\c myapp
GRANT USAGE ON SCHEMA public TO readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly;
```

## 📚 Resource Information

**Current Configuration:**
- CPU: 2 cores (request) / 8 cores (limit)
- Memory: 4Gi (request) / 8Gi (limit)
- Storage: 20Gi
- Max Connections: 200
- Shared Buffers: 2GB
- Effective Cache Size: 6GB

**Files Location:**
- Manifests: `/home/major/git/major/selfhosted/apps/base/postgres/`
- Full README: `apps/base/postgres/README.md`
- Secrets Template: `apps/base/postgres/secrets-template.yaml`
