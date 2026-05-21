#!/usr/bin/env bash
# Run this from the homelab node (via Tailscale SSH) or from Mac with Tailscale active.
# kubectl context: default (k3s at 100.114.206.128:6443)
set -euo pipefail

CONTEXT="default"
KC="kubectl --context=${CONTEXT}"
HC="helm --kube-context=${CONTEXT}"

echo "==> 1. Install ArgoCD"
$KC create namespace argocd --dry-run=client -o yaml | $KC apply -f -
$KC apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "Waiting for ArgoCD pods..."
$KC wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s

echo "==> 2. Install Sealed Secrets controller (if not present)"
$KC apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml

echo "==> 3. Terraform — create namespaces + RBAC"
(cd "$(dirname "$0")/../terraform" && terraform init && terraform apply -auto-approve)

echo "==> 4. Apply ArgoCD Application"
$KC apply -f "$(dirname "$0")/../argocd/apps/sample-app.yaml"

echo "==> 5. Install Loki stack (if not present)"
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update
$HC upgrade --install loki grafana/loki-stack -n monitoring --create-namespace \
  --set promtail.enabled=true \
  --set grafana.enabled=false

echo "==> 6. Apply custom alerting rules"
$KC apply -f "$(dirname "$0")/../monitoring/alerting-rules/custom-rules.yaml"

echo "==> 7. Import Grafana dashboard"
echo "Manual step: In Grafana UI → Dashboards → Import → upload monitoring/grafana-dashboards/sample-app.json"

echo "==> 8. Apply sealed secret example"
$KC apply -f "$(dirname "$0")/../sealed-secrets/example-sealed-secret.yaml"

echo ""
echo "Done. ArgoCD UI:"
$KC get svc argocd-server -n argocd
echo "Default admin password:"
$KC -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
