#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "IMPORTANTE: edite gitops/root-app.yaml e aponte 'repoURL' para o seu"
echo "repositório git (este diretório precisa estar versionado e com push feito)"
echo "antes de rodar este script."
read -p "Já editou o repoURL? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Edite gitops/root-app.yaml e rode este script novamente."
  exit 1
fi

kubectl apply -f ../gitops/root-app.yaml
echo "ApplicationSet aplicado. Acompanhe com: kubectl -n argocd get applications"
