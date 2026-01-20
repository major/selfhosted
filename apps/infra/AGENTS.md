# apps/infra

Infrastructure components deployed via Flux GitOps.

## COMPONENTS

| Component | Type | Purpose |
|-----------|------|---------|
| cert-manager | HelmRelease | TLS certificate automation |
| cert-manager-config | Kustomize | ClusterIssuers, Porkbun webhook |
| envoy-gateway | HelmRelease | Ingress controller (Gateway API) |
| flux-notifications | Kustomize | Discord alerts for Flux events |
| gateway-api-crds | OCIRepository | Gateway API CRD definitions |
| gateway-api-source | GitRepository | Gateway API source |
| kwatch | Kustomize | K8s event monitoring |
| redis | Kustomize | Cache layer with PVC |

## DEPENDENCY ORDER

```
cert-manager → cert-manager-config → infra (main) → envoy-gateway
                                  → gateway-api-crds → gateway-api-source
```

## HELM PATTERNS

HelmReleases follow this structure:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <name>
  namespace: <namespace>
spec:
  interval: 10m
  chart:
    spec:
      chart: <chart-name>
      version: "x.y.z"          # Pin version!
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
  values:
    # Helm values here
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add ClusterIssuer | `cert-manager-config/` | DNS-01 or HTTP-01 |
| Modify Gateway | `envoy-gateway/gateway.yaml` | Listeners, TLS |
| Add Helm repo | `<component>/repository.yaml` | HelmRepository CRD |
| Change alerts | `flux-notifications/` | Provider + Alert CRDs |

## CRD HANDLING

**CRITICAL**: CRD Kustomizations must have `prune: false`

```yaml
# gateway-api-crds/crds-kustomization.yaml
spec:
  prune: false  # NEVER auto-delete CRDs!
```

## NOTES

- envoy-gateway replaces nginx-ingress (migration in progress)
- cert-manager has health checks (wait: true, timeout: 5m)
- Wildcard cert at `envoy-gateway/wildcard-certificate.yaml`
- kwatch sends to Discord via sealed config
