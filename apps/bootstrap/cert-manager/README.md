# cert-manager Setup

This directory contains the cert-manager deployment for automatic TLS certificate management using Let's Encrypt and Porkbun DNS challenge.

## Components

- **[namespace.yaml](namespace.yaml)** - cert-manager namespace
- **[helmrelease.yaml](helmrelease.yaml)** - cert-manager core installation via Helm
- **[porkbun-webhook-helmrelease.yaml](porkbun-webhook-helmrelease.yaml)** - Porkbun DNS webhook provider
- **[porkbun-credentials-sealed.yaml](porkbun-credentials-sealed.yaml)** - SealedSecret with Porkbun API credentials
- **[clusterissuer.yaml](clusterissuer.yaml)** - Let's Encrypt ClusterIssuer using Porkbun DNS-01 challenge
- **[certificate.yaml](certificate.yaml)** - Wildcard certificate for `amajor.cloud` and `*.amajor.cloud`

## Architecture

cert-manager automatically manages TLS certificates for the cluster:

1. **Certificate Resource** requests a wildcard cert for `*.amajor.cloud`
2. **ClusterIssuer** uses Let's Encrypt with DNS-01 challenge via Porkbun
3. **Porkbun Webhook** handles DNS record creation for ACME challenge
4. **Certificate Secret** (`amajor-cloud-tls`) is created in the `traefik` namespace
5. **Traefik** uses this certificate as the default for all HTTPS traffic

## Certificate Details

- **Domains**: `amajor.cloud`, `*.amajor.cloud`
- **Issuer**: Let's Encrypt Production
- **Secret Name**: `amajor-cloud-tls` (in `traefik` namespace)
- **Duration**: 90 days (Let's Encrypt default)
- **Auto-renewal**: 30 days before expiry

## Verification

```bash
# Check cert-manager pods
kubectl -n cert-manager get pods

# Check ClusterIssuer status
kubectl get clusterissuer letsencrypt-porkbun -o yaml

# Check Certificate status
kubectl -n traefik get certificate amajor-cloud-wildcard

# View certificate details
kubectl -n traefik describe certificate amajor-cloud-wildcard

# Check if secret was created
kubectl -n traefik get secret amajor-cloud-tls
```

## Troubleshooting

If the certificate isn't being issued:

```bash
# Check cert-manager logs
kubectl -n cert-manager logs -l app=cert-manager

# Check webhook logs
kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager-webhook-porkbun

# Check CertificateRequest
kubectl -n traefik get certificaterequest

# Describe Certificate for events
kubectl -n traefik describe certificate amajor-cloud-wildcard
```

Common issues:
- **Porkbun API credentials** - Verify the sealed secret contains correct API keys
- **DNS propagation** - Webhook needs time to create DNS records
- **Rate limits** - Let's Encrypt has rate limits (50 certs per domain per week)

## Adding New Certificates

To request additional certificates, create a new Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: <target-namespace>
spec:
  secretName: example-tls
  issuerRef:
    name: letsencrypt-porkbun
    kind: ClusterIssuer
  dnsNames:
    - "example.amajor.cloud"
```
