#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Os CRDs do ArgoCD (ex.: applicationsets.argoproj.io) são grandes demais para
# o "kubectl apply" padrão, que guarda o manifesto inteiro na annotation
# kubectl.kubernetes.io/last-applied-configuration (limite de 262144 bytes).
# Server-side apply resolve isso, pois não usa essa annotation.
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Aguardando ArgoCD ficar pronto (pode levar alguns minutos)..."
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server

echo
echo "Senha inicial do usuário admin:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
echo
echo "Para acessar a UI: kubectl -n argocd port-forward svc/argocd-server 8081:443"
echo "Depois abra https://localhost:8081 (usuário: admin)"
