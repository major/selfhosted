# Sealed Secrets

Sealed Secrets provides encryption for Kubernetes secrets that can be safely stored in Git.

## Installation

### 1. Install kubeseal CLI

```bash
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.2/kubeseal-0.27.2-linux-amd64.tar.gz
tar xfz kubeseal-0.27.2-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# macOS
brew install kubeseal
```

### 2. Deploy the controller

The Sealed Secrets controller will be automatically deployed by Flux once this is committed and synced.

Verify deployment:
```bash
kubectl get pods -n sealed-secrets
flux get helmreleases -n sealed-secrets
```

## Creating Sealed Secrets

### Basic workflow

1. Create a regular Kubernetes secret (DON'T commit this):
```bash
kubectl create secret generic my-secret \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  --dry-run=client -o yaml > secret.yaml
```

2. Seal the secret:
```bash
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml
```

3. Commit the sealed secret to git:
```bash
git add sealed-secret.yaml
git commit -m "Add sealed secret"
```

4. The Sealed Secrets controller will decrypt it automatically in the cluster

### Example: Porkbun DNS API credentials for Traefik

Create a secret with your Porkbun API credentials:

```bash
kubectl create secret generic porkbun-credentials \
  --namespace=traefik \
  --from-literal=api-key=pk1_your_api_key_here \
  --from-literal=secret-key=sk1_your_secret_key_here \
  --dry-run=client -o yaml | \
  kubeseal --format=yaml > apps/base/traefik/porkbun-sealed-secret.yaml
```

Then commit the sealed secret file. The actual Secret will be created automatically by the controller.

## Managing Secrets

### View sealed secrets
```bash
kubectl get sealedsecrets -A
```

### View decrypted secrets (requires cluster access)
```bash
kubectl get secret porkbun-credentials -n traefik -o yaml
```

### Update a sealed secret
Re-run the creation steps and replace the file. The controller will update the decrypted secret.

### Backup the sealing key
The controller generates a private key used for decryption. Back it up:

```bash
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```

Store this backup securely offline. You'll need it to restore the controller if you rebuild the cluster.

## Troubleshooting

### Check controller logs
```bash
kubectl logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

### Verify the secret was created
```bash
kubectl get secrets -A | grep porkbun
```
