#!/usr/bin/env bash
set -euo pipefail

if ! command -v argocd &> /dev/null; then
  echo "argocd CLI não encontrado. Instale antes de continuar:"
  echo "https://argo-cd.readthedocs.io/en/stable/cli_installation/"
  exit 1
fi

kubectl config use-context kind-master

echo "Abrindo port-forward para o argocd-server do cluster master..."
kubectl -n argocd port-forward svc/argocd-server 8081:443 >/tmp/argocd-pf.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 4

ARGO_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login localhost:8081 --username admin --password "$ARGO_PWD" --insecure

for shard in shard1 shard2; do
  echo
  echo "### Registrando $shard no ArgoCD ###"

  # kind --internal gera um kubeconfig cujo "server" aponta para o endereço do
  # container do control-plane na rede docker (ex.: https://shard1-control-plane:6443),
  # em vez de https://127.0.0.1:<porta>. É esse endereço que o pod do argocd-server
  # (rodando dentro do cluster master) precisa usar para alcançar o shard.
  kind get kubeconfig --name "$shard" --internal > "/tmp/${shard}-internal.kubeconfig"

  # Renomeia o contexto para não colidir com o "kind-<shard>" já existente
  # (que aponta para localhost e só funciona a partir da sua máquina).
  KUBECONFIG="/tmp/${shard}-internal.kubeconfig" \
    kubectl config rename-context "kind-${shard}" "${shard}-internal"

  # Mescla no kubeconfig padrão para o argocd CLI enxergar o novo contexto
  KUBECONFIG="$HOME/.kube/config:/tmp/${shard}-internal.kubeconfig" \
    kubectl config view --flatten > /tmp/merged.kubeconfig
  mv /tmp/merged.kubeconfig "$HOME/.kube/config"

  shard_label=$(echo "$shard" | sed -E 's/shard([0-9]+)/shard-\1/')
  argocd cluster add "${shard}-internal" --name "$shard_label" --yes
done

kubectl config use-context kind-master

echo
echo "Clusters registrados no ArgoCD:"
argocd cluster list
