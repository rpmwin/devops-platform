# DevOps Platform

Production-grade DevOps platform on a single-node k3s homelab cluster demonstrating GitOps, CI/CD, and observability.

## Architecture

```
Developer push
     │
     ▼
┌─────────────────────────────────────────────────────┐
│              GitHub Actions CI/CD                   │
│  checkout → build (multi-stage) → Trivy scan →     │
│  push image (GHCR) → update Helm values tag         │
└───────────────────────┬─────────────────────────────┘
                        │ git push (values.yaml tag)
                        ▼
              ┌──────────────────┐
              │    ArgoCD        │  (auto-sync, selfHeal)
              │  watches repo    │
              └────────┬─────────┘
                       │ helm apply
                       ▼
         ┌─────────────────────────────┐
         │     k3s cluster             │
         │  namespace: apps            │
         │  ┌──────────────────────┐   │
         │  │  sample-app (x2)     │   │
         │  │  /  /health /metrics │   │
         │  │  HPA (2-5 replicas)  │   │
         │  └──────────────────────┘   │
         │                             │
         │  namespace: monitoring      │
         │  ┌──────────────────────┐   │
         │  │  Prometheus          │   │
         │  │  Grafana             │   │
         │  │  Loki + Promtail     │   │
         │  └──────────────────────┘   │
         └─────────────────────────────┘
```

## Tech Stack

| Layer | Tool |
|-------|------|
| Infra provisioning | Terraform (kubernetes provider) |
| GitOps | ArgoCD |
| Packaging | Helm |
| Secrets | Sealed Secrets (bitnami-labs) |
| CI/CD | GitHub Actions |
| Container registry | GHCR |
| Security scanning | Trivy |
| Metrics | Prometheus + kube-prometheus-stack |
| Dashboards | Grafana |
| Logs | Loki + Promtail |
| Ingress | Traefik (k3s default) |
| Autoscaling | HPA (CPU-based) |

## GitOps Loop

```
1. Developer pushes code to apps/sample-app/
2. GitHub Actions triggers:
   a. Multi-stage Docker build (golang:1.22-alpine → scratch)
   b. Trivy vulnerability scan (CRITICAL/HIGH → fail gate)
   c. Image pushed to ghcr.io/iamrpm/devops-platform-sample-app:<sha>
   d. helm/sample-app/values.yaml tag updated → committed → pushed
3. ArgoCD detects the values.yaml change (polls every 3m / webhook)
4. ArgoCD syncs: helm upgrade sample-app in namespace apps
5. Kubernetes rolls out new pods; old pods terminate after health checks pass
6. Prometheus scrapes /metrics on the new pods
7. Grafana dashboards reflect the new deployment
```

## Why `scratch` base image?

No shell, no package manager, no OS libraries. Only the compiled binary runs in the container. Attack surface is minimal — a compromised container has nothing to execute. Produces smaller images (~8MB vs ~30MB with alpine).

## Alerting Rules

| Alert | Expression | Severity | For |
|-------|-----------|----------|-----|
| HighCPUUsage | CPU > 80% in `apps` ns | warning | 5m |
| PodRestartingTooOften | any restart in 15m window | critical | 5m |
| HighMemoryUsage | memory > 85% of limit | warning | 5m |
| ServiceDown | `up{job="sample-app"} == 0` | critical | 1m |

## Grafana Dashboard Panels

1. **Request Rate** — `rate(http_requests_total[5m])` by path
2. **Error Rate** — 5xx responses as % of total
3. **Latency P50/P95/P99** — histogram quantiles from `http_request_duration_seconds_bucket`
4. **Pod CPU** — `rate(container_cpu_usage_seconds_total[5m])` by pod
5. **Pod Memory** — `container_memory_usage_bytes` by pod
6. **Pod Restart Count** — `kube_pod_container_status_restarts_total`
7. **HPA Replica Count** — current vs max replicas

Import: Grafana → Dashboards → Import → upload `monitoring/grafana-dashboards/sample-app.json`

## ArgoCD — selfHeal

`selfHeal: true` means any manual `kubectl` change to the `apps` namespace is automatically reverted by ArgoCD within minutes. Git is the single source of truth. This enforces GitOps discipline — no config drift.

## Sealed Secrets

The Sealed Secrets controller holds a private key. `kubeseal` encrypts secrets client-side with the controller's public cert. Only the controller can decrypt. Encrypted SealedSecret CRDs are safe to commit to git.

```bash
# Encrypt a secret
kubeseal --cert pub-cert.pem --format yaml < raw-secret.yaml > sealed-secrets/my-sealed-secret.yaml

# Get cluster public cert
kubeseal --fetch-cert --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system > pub-cert.pem
```

## Local Development

```bash
cd apps/sample-app
go run .
# http://localhost:8080/
# http://localhost:8080/health
# http://localhost:8080/metrics
```

## Deploy to k3s

```bash
# Prerequisites: Tailscale active, kubectl context 'default' pointing to k3s
./scripts/setup.sh

# Trigger CI/CD pipeline
git commit --allow-empty -m "trigger: initial deployment"
git push origin main
```

## Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Creates namespaces (`apps`, `monitoring`, `argocd`, `sealed-secrets`) and ServiceAccount + RBAC for sample-app. Uses local backend — remote state adds infra overhead not justified for a single-node homelab.
