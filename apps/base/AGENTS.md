# apps/base

User-facing applications deployed via Flux GitOps.

## APPS

| App | Purpose | Storage | Secrets |
|-----|---------|---------|---------|
| flux-webhook | GitHub webhook → instant Flux sync | - | SealedSecret |
| gatus | Uptime monitoring dashboard | - | SealedSecret (Discord) |
| hvcwatch | HVC monitoring | PVC | SealedSecret |
| speedtest | LibreSpeed speed test | - | - |
| stockchartsalerts | Stock chart alerts | - | SealedSecret |
| stocknews | Stock news aggregator | - | SealedSecret |
| thetagang-notifications | Options trading alerts | PVC | SealedSecret |

## APP STRUCTURE

Each app follows this pattern:
```
<app-name>/
├── kustomization.yaml    # Lists all resources
├── namespace.yaml        # App's namespace
├── deployment.yaml       # Pod spec (sha256 image!)
├── service.yaml          # ClusterIP service
├── httproute.yaml        # Gateway API ingress
├── sealed-secret.yaml    # Encrypted secrets (if needed)
└── pvc.yaml              # Persistent storage (if needed)
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Change app config | `deployment.yaml` | Env vars, image, resources |
| Update routing | `httproute.yaml` | Hostname, paths, backends |
| Rotate secrets | `sealed-secret.yaml` | Re-seal with kubeseal |
| Add storage | `pvc.yaml` | Copy from hvcwatch/thetagang |

## ADDING NEW APP

1. `mkdir apps/base/<name>`
2. Copy structure from `speedtest/` (simplest template)
3. Create namespace.yaml with `<name>` namespace
4. Create deployment.yaml with `image: ...:tag@sha256:...`
5. Create httproute.yaml pointing to `<name>.amajor.cloud`
6. Create kustomization.yaml listing all resources
7. Commit on feature branch, PR to main

## NOTES

- HTTPRoute uses `parentRefs` to `envoy-gateway/eg` Gateway
- All apps run in own namespace (isolation)
- gatus has ConfigMap for monitoring targets
- flux-webhook has NetworkPolicy (GitHub IPs only)
