# 🚀 Nginx → Envoy Gateway Migration Plan (Revised)

> **Updated based on Munger inversion risk analysis from issue #91**

## 📋 Summary

Migrate from Nginx Ingress Controller + HTTP-01 validation to **Envoy Gateway** with **DNS-01 validation** using Porkbun DNS for wildcard certificates.

### Key Changes from Original Plan

| Risk Identified | Mitigation Applied |
|-----------------|-------------------|
| ❌ Big bang app migration | ✅ Incremental migration with canary |
| ❌ Port conflicts (nginx vs envoy) | ✅ Use separate LoadBalancer IP during transition |
| ❌ Missing Gateway API CRDs | ✅ Explicit CRD installation phase |
| ❌ Race conditions (cert timing) | ✅ Health checks + staging cert first |
| ❌ Weak rollback strategy | ✅ Parallel operation, no deletions until verified |
| ❌ No observability | ✅ Explicit success criteria per phase |

---

## 🔧 Phase 0: Preparation (Pre-Migration)

### 0.1 Verify Porkbun API Credentials

**Before sealing secrets**, manually test credentials work:

```bash
# Test API access
curl -X POST https://api.porkbun.com/api/json/v3/dns/retrieve/amajor.cloud \
  -H "Content-Type: application/json" \
  -d '{
    "apikey": "YOUR_API_KEY",
    "secretapikey": "YOUR_SECRET_API_KEY"
  }'

# Expected: {"status":"SUCCESS","cloudflare":"enabled",...}
```

**Only proceed if API test succeeds!**

### 0.2 Document Current Service Ports

Verify actual service ports for each app:

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config get svc -A -o wide | grep -E "gatus|speedtest|flux-webhook|stockchartsalerts|stocknews|thetagang|tickerlake"
```

Document in table:
| App | Namespace | Service Name | Port |
|-----|-----------|--------------|------|
| gatus | gatus | gatus | 8080 |
| speedtest | speedtest | speedtest | 80 |
| ... | ... | ... | ... |

### 0.3 Audit NetworkPolicies

Find apps with NetworkPolicies that need updating:

```bash
grep -r "kind: NetworkPolicy" apps/base/
```

Each must add `envoy-gateway-system` namespace to allowed ingress.

### Success Criteria - Phase 0
- [ ] Porkbun API credentials verified working
- [ ] All service ports documented
- [ ] NetworkPolicies identified and update plan ready
- [ ] Current endpoints documented for comparison

---

## 🏗️ Phase 1: Infrastructure Setup (Parallel Operation)

> **nginx-ingress continues running throughout this phase**

### 1.1 Install Gateway API CRDs

**Critical prerequisite - must be installed BEFORE Envoy Gateway!**

Create `apps/infra/gateway-api-crds/`:

```yaml
# gitrepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gateway-api
  namespace: flux-system
spec:
  interval: 24h
  url: https://github.com/kubernetes-sigs/gateway-api
  ref:
    tag: v1.2.1
  ignore: |
    /*
    !/config/crd
---
# kustomization (Flux)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: gateway-api-crds
  namespace: flux-system
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: gateway-api
  path: ./config/crd/standard
  prune: false  # NEVER auto-delete CRDs
```

### 1.2 Deploy Porkbun Webhook

Create `apps/infra/cert-manager-config/porkbun-webhook/`:

```yaml
# gitrepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: porkbun-webhook
  namespace: flux-system
spec:
  interval: 24h
  url: https://github.com/mdonoughe/porkbun-webhook
  ref:
    tag: v0.1.5

---
# helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: porkbun-webhook
  namespace: cert-manager
spec:
  interval: 1h
  chart:
    spec:
      chart: ./deploy/porkbun-webhook
      sourceRef:
        kind: GitRepository
        name: porkbun-webhook
        namespace: flux-system
  values:
    groupName: acme.amajor.cloud
```

### 1.3 Create Porkbun Credentials (SealedSecret)

```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config create secret generic porkbun-credentials \
  --from-literal=api-key='YOUR_API_KEY' \
  --from-literal=secret-api-key='YOUR_SECRET_API_KEY' \
  --namespace=cert-manager \
  --dry-run=client -o yaml | \
kubeseal --kubeconfig ~/.kube/k3s-psychz-config \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml > apps/infra/cert-manager-config/porkbun-sealed-secret.yaml
```

### 1.4 Add DNS-01 ClusterIssuer (KEEP existing HTTP-01!)

**Do NOT modify existing ClusterIssuers** - add NEW ones alongside:

```yaml
# apps/infra/cert-manager-config/clusterissuer-dns01.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns01  # NEW - for testing
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: major@mhtx.net
    privateKeySecretRef:
      name: letsencrypt-staging-dns01-account
    solvers:
      - dns01:
          webhook:
            groupName: acme.amajor.cloud
            solverName: porkbun
            config:
              apiKeySecretRef:
                name: porkbun-credentials
                key: api-key
              secretKeySecretRef:
                name: porkbun-credentials
                key: secret-api-key
              propagationTimeout: 600  # 10 minutes for DNS propagation
              pollingInterval: 10
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns01  # NEW - for production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: major@mhtx.net
    privateKeySecretRef:
      name: letsencrypt-production-dns01-account
    solvers:
      - dns01:
          webhook:
            groupName: acme.amajor.cloud
            solverName: porkbun
            config:
              apiKeySecretRef:
                name: porkbun-credentials
                key: api-key
              secretKeySecretRef:
                name: porkbun-credentials
                key: secret-api-key
              propagationTimeout: 600
              pollingInterval: 10
```

### 1.5 Create envoy-gateway-system Namespace

```yaml
# apps/infra/envoy-gateway/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: envoy-gateway-system
```

### 1.6 Request STAGING Wildcard Certificate First

**Use staging issuer to validate DNS-01 works before production!**

```yaml
# apps/infra/cert-manager-config/wildcard-certificate-staging.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: amajor-cloud-wildcard-staging
  namespace: envoy-gateway-system
spec:
  secretName: amajor-cloud-tls-staging
  issuerRef:
    name: letsencrypt-staging-dns01
    kind: ClusterIssuer
  dnsNames:
    - "amajor.cloud"
    - "*.amajor.cloud"
```

### 1.7 Add Flux Kustomization with Health Checks

```yaml
# clusters/selfhosted/cert-manager-config.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager-config
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/infra/cert-manager-config
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: cert-manager
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: porkbun-webhook
      namespace: cert-manager
  timeout: 5m
```

### Success Criteria - Phase 1
- [ ] Gateway API CRDs installed: `kubectl get crd gateways.gateway.networking.k8s.io`
- [ ] Porkbun webhook pod running: `kubectl -n cert-manager get pods -l app.kubernetes.io/name=porkbun-webhook`
- [ ] Staging wildcard cert issued: `kubectl -n envoy-gateway-system get certificate amajor-cloud-wildcard-staging` shows `Ready=True`
- [ ] DNS TXT record visible: `dig _acme-challenge.amajor.cloud TXT`
- [ ] nginx-ingress still running, all apps still accessible via current URLs

---

## 🌐 Phase 2: Envoy Gateway Deployment (Isolated)

> **nginx-ingress continues running - no port conflict approach**

### Strategy: Separate LoadBalancer

Deploy Envoy Gateway with its own LoadBalancer IP. Test routing works before any cutover.

### 2.1 Add Envoy Gateway Helm Release

```yaml
# apps/infra/envoy-gateway/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: envoy-gateway
  namespace: envoy-gateway-system
spec:
  interval: 1h
  chart:
    spec:
      chart: gateway-helm
      version: v1.6.1
      sourceRef:
        kind: HelmRepository
        name: envoy-gateway
        namespace: envoy-gateway-system
  values:
    # Default settings - Envoy will get its own LoadBalancer IP
```

### 2.2 Add GatewayClass

```yaml
# apps/infra/envoy-gateway/gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

### 2.3 Create Gateway with STAGING Cert

**Use staging cert initially - switch to production after validation!**

```yaml
# apps/infra/envoy-gateway/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: amajor-cloud-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: amajor-cloud-tls-staging  # Start with staging!
            kind: Secret
      allowedRoutes:
        namespaces:
          from: All
```

### 2.4 Add HTTP→HTTPS Redirect

```yaml
# apps/infra/envoy-gateway/http-redirect.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-redirect
  namespace: envoy-gateway-system
spec:
  parentRefs:
    - name: amajor-cloud-gateway
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

### 2.5 Add Flux Kustomization with Health Checks

```yaml
# clusters/selfhosted/envoy-gateway.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: envoy-gateway
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/infra/envoy-gateway
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: cert-manager-config
    - name: gateway-api-crds
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: envoy-gateway
      namespace: envoy-gateway-system
    - apiVersion: gateway.networking.k8s.io/v1
      kind: Gateway
      name: amajor-cloud-gateway
      namespace: envoy-gateway-system
  timeout: 5m
```

### 2.6 Get Envoy Gateway LoadBalancer IP

After deployment:
```bash
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n envoy-gateway-system get svc
# Note the EXTERNAL-IP for the gateway service
```

### Success Criteria - Phase 2
- [ ] Envoy Gateway pods running: `kubectl -n envoy-gateway-system get pods`
- [ ] Gateway programmed: `kubectl -n envoy-gateway-system get gateway` shows `Programmed=True`
- [ ] Envoy has LoadBalancer IP (different from nginx!)
- [ ] Can curl Envoy IP directly: `curl -v http://<ENVOY_IP>` returns response (even 404)
- [ ] nginx-ingress still running on its original IP
- [ ] All existing apps still accessible via nginx

---

## 🐤 Phase 3: Canary Migration (ONE App)

> **Migrate speedtest first - least critical, good canary**

### 3.1 Create HTTPRoute for speedtest

```yaml
# apps/base/speedtest/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: speedtest
  namespace: speedtest
spec:
  parentRefs:
    - name: amajor-cloud-gateway
      namespace: envoy-gateway-system
  hostnames:
    - speedtest.amajor.cloud
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: speedtest
          port: 80  # Verify this matches actual service port!
```

### 3.2 Update DNS (or /etc/hosts for testing)

**Option A: Local testing first**
```bash
# Add to /etc/hosts for testing:
<ENVOY_IP>  speedtest.amajor.cloud
```

**Option B: Split DNS**
- Update DNS for `speedtest.amajor.cloud` to point to Envoy IP
- Keep other apps pointing to nginx IP

### 3.3 Verify speedtest Works via Envoy

```bash
# Test via Envoy
curl -v https://speedtest.amajor.cloud --resolve speedtest.amajor.cloud:443:<ENVOY_IP>

# Verify TLS (will be staging cert - browser warning expected)
openssl s_client -connect <ENVOY_IP>:443 -servername speedtest.amajor.cloud
```

### 3.4 Wait 48 Hours

Monitor speedtest for 48 hours before proceeding:
- Check gatus/uptime monitoring
- Verify no errors in logs
- Confirm TLS renewal would work

### Success Criteria - Phase 3 (Canary)
- [ ] HTTPRoute attached: `kubectl -n speedtest get httproute speedtest`
- [ ] speedtest accessible via Envoy IP
- [ ] TLS working (staging cert)
- [ ] 48 hours stable operation
- [ ] All OTHER apps still working via nginx

---

## 📈 Phase 4: Incremental Migration

> **Migrate remaining apps ONE BY ONE with 24h wait between each**

### Migration Order (recommended)

1. **gatus** (monitoring - migrate early so it can monitor others)
2. **flux-webhook** (infrastructure)
3. **stockchartsalerts**
4. **stocknews**
5. **thetagang-notifications**
6. **tickerlake**

### Per-App Migration Template

For each app:

```yaml
# apps/base/<app>/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <namespace>
spec:
  parentRefs:
    - name: amajor-cloud-gateway
      namespace: envoy-gateway-system
  hostnames:
    - <hostname>.amajor.cloud
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>
          port: <PORT>  # From Phase 0 documentation!
```

### Per-App Success Criteria
- [ ] HTTPRoute attached to Gateway
- [ ] `curl https://<app>.amajor.cloud` returns 200
- [ ] TLS cert valid (staging initially)
- [ ] App logs show no errors
- [ ] Monitoring confirms app healthy
- [ ] Wait 24 hours before next app

### Update NetworkPolicies

For apps with NetworkPolicies (e.g., flux-webhook):

```yaml
# Add to NetworkPolicy ingress rules:
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: envoy-gateway-system
```

---

## 🎫 Phase 5: Production Certificate

> **Only after ALL apps migrated and stable**

### 5.1 Request Production Wildcard Certificate

```yaml
# apps/infra/cert-manager-config/wildcard-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: amajor-cloud-wildcard
  namespace: envoy-gateway-system
spec:
  secretName: amajor-cloud-tls
  issuerRef:
    name: letsencrypt-production-dns01  # Production issuer!
    kind: ClusterIssuer
  dnsNames:
    - "amajor.cloud"
    - "*.amajor.cloud"
```

### 5.2 Update Gateway to Use Production Cert

```yaml
# Modify apps/infra/envoy-gateway/gateway.yaml
listeners:
  - name: https
    tls:
      certificateRefs:
        - name: amajor-cloud-tls  # Production cert
```

### 5.3 Verify Production TLS

```bash
# Verify production cert
curl -v https://speedtest.amajor.cloud 2>&1 | grep "issuer:"
# Should show: "issuer: C=US; O=Let's Encrypt; CN=R10" (or similar)

# Verify all apps have valid certs
for app in speedtest gatus flux-webhook stockchartsalerts stocknews thetagang tickerlake; do
  echo "=== $app ==="
  curl -sI https://$app.amajor.cloud | head -1
done
```

### Success Criteria - Phase 5
- [ ] Production wildcard cert issued: `Ready=True`
- [ ] All apps showing valid Let's Encrypt production cert
- [ ] No browser security warnings
- [ ] Certificate expiry > 60 days out

---

## 🔄 Phase 6: DNS Cutover

> **Point all DNS to Envoy Gateway**

### 6.1 Update DNS Records

Update Porkbun DNS:
- Point `*.amajor.cloud` A record to Envoy Gateway LoadBalancer IP
- Keep nginx IP noted for rollback

### 6.2 Verify All Traffic Flows Through Envoy

```bash
# Verify DNS resolution
dig speedtest.amajor.cloud +short
# Should return Envoy Gateway IP

# Test all apps
for app in speedtest gatus flux-webhook stockchartsalerts stocknews thetagang tickerlake; do
  echo "=== $app ==="
  curl -sI https://$app.amajor.cloud | head -1
done
```

### Success Criteria - Phase 6
- [ ] All `*.amajor.cloud` DNS points to Envoy Gateway
- [ ] All apps accessible via production URLs
- [ ] nginx-ingress still running (fallback)

---

## 🧹 Phase 7: Cleanup

> **Only after 1 week of stable operation on Envoy**

### 7.1 Remove Ingress Resources

Delete Ingress resources from each app (they're no longer used):
```bash
rm apps/base/gatus/ingress.yaml
rm apps/base/speedtest/ingress.yaml
# etc for each app
```

### 7.2 Remove nginx-ingress

```bash
rm -rf apps/infra/nginx-ingress/
```

Update `clusters/selfhosted/infra.yaml` to remove nginx-ingress reference.

### 7.3 Remove Staging Resources

```bash
rm apps/infra/cert-manager-config/wildcard-certificate-staging.yaml
```

### 7.4 Remove HTTP-01 ClusterIssuers (Optional)

If no longer needed for any other purpose:
```bash
# Remove HTTP-01 issuers from clusterissuer.yaml
# Keep only DNS-01 issuers
```

### 7.5 Update CLAUDE.md

Update documentation to reflect:
- Envoy Gateway instead of nginx-ingress
- HTTPRoute instead of Ingress
- DNS-01 instead of HTTP-01
- Wildcard cert instead of per-app certs

### Success Criteria - Phase 7
- [ ] No Ingress resources in git: `grep -r "kind: Ingress" apps/`
- [ ] nginx-ingress directory removed
- [ ] Flux reconciliation successful
- [ ] All apps still working after cleanup

---

## 🚨 Emergency Rollback Procedure

### If Migration Fails

```bash
# 1. Suspend Flux to stop automated changes
flux suspend kustomization apps --kubeconfig ~/.kube/k3s-psychz-config

# 2. Point DNS back to nginx-ingress IP
# (Manual step in Porkbun dashboard)

# 3. Verify nginx-ingress still running
kubectl --kubeconfig ~/.kube/k3s-psychz-config -n nginx-ingress get pods

# 4. If nginx-ingress was deleted, restore from git history
git checkout HEAD~1 apps/infra/nginx-ingress/
kubectl apply -k apps/infra/nginx-ingress/ --kubeconfig ~/.kube/k3s-psychz-config

# 5. Resume Flux
flux resume kustomization apps --kubeconfig ~/.kube/k3s-psychz-config

# 6. Document what went wrong for post-mortem
```

### Key Rollback Principle

**Because we kept nginx-ingress running until Phase 7**, rollback is simple:
- DNS change back to nginx IP
- All apps immediately accessible again
- No git reverts needed for rollback

---

## 📁 File Structure

```
apps/infra/
├── cert-manager-config/
│   ├── clusterissuer.yaml              # KEEP existing HTTP-01
│   ├── clusterissuer-dns01.yaml        # NEW: DNS-01 issuers
│   ├── wildcard-certificate-staging.yaml  # NEW: Staging cert
│   ├── wildcard-certificate.yaml       # NEW: Production cert
│   ├── porkbun-sealed-secret.yaml      # NEW: Credentials
│   └── porkbun-webhook/
│       ├── gitrepository.yaml          # NEW
│       ├── helmrelease.yaml            # NEW
│       └── kustomization.yaml          # NEW
├── gateway-api-crds/
│   ├── gitrepository.yaml              # NEW
│   └── kustomization.yaml              # NEW (Flux kind)
├── envoy-gateway/
│   ├── namespace.yaml                  # NEW
│   ├── repository.yaml                 # NEW
│   ├── helmrelease.yaml                # NEW
│   ├── gatewayclass.yaml               # NEW
│   ├── gateway.yaml                    # NEW
│   ├── http-redirect.yaml              # NEW
│   └── kustomization.yaml              # NEW
└── nginx-ingress/                      # KEEP until Phase 7!

apps/base/*/
├── httproute.yaml                      # NEW for each app (Phase 3-4)
├── ingress.yaml                        # KEEP until Phase 7!
└── ...

clusters/selfhosted/
├── gateway-api-crds.yaml               # NEW
├── cert-manager-config.yaml            # NEW/MODIFY
├── envoy-gateway.yaml                  # NEW
├── infra.yaml                          # KEEP nginx until Phase 7
└── apps.yaml                           # MODIFY dependsOn
```

---

## 📊 Dependency Chain (Final State)

```
bootstrap-infra (sealed-secrets)
    ↓
cert-manager
    ↓
gateway-api-crds ←──────┐
    ↓                   │
cert-manager-config     │
    ↓                   │
envoy-gateway ──────────┘
    ↓
apps
```

---

## ✅ Migration Checklist Summary

| Phase | Status | Duration | Key Milestone |
|-------|--------|----------|---------------|
| 0: Preparation | ⬜ | 1 day | Credentials verified, ports documented |
| 1: Infrastructure | ⬜ | 1-2 days | Staging wildcard cert issued |
| 2: Envoy Gateway | ⬜ | 1 day | Gateway programmed, separate IP |
| 3: Canary (speedtest) | ⬜ | 2 days | speedtest working via Envoy |
| 4: Incremental Migration | ⬜ | 7 days | All apps migrated, 24h between each |
| 5: Production Cert | ⬜ | 1 day | Production wildcard working |
| 6: DNS Cutover | ⬜ | 1 day | All traffic via Envoy |
| 7: Cleanup | ⬜ | 1 day | nginx-ingress removed |

**Total: ~2-3 weeks for safe migration**

---

## 📚 References

- [Envoy Gateway docs](https://gateway.envoyproxy.io/)
- [Porkbun webhook](https://github.com/mdonoughe/porkbun-webhook)
- [Gateway API docs](https://gateway-api.sigs.k8s.io/)
- [cert-manager DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/)
