#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v istioctl &> /dev/null; then
  echo "istioctl não encontrado. Instale antes de continuar:"
  echo "https://istio.io/latest/docs/setup/getting-started/#download"
  exit 1
fi

istioctl install --set profile=demo -y

kubectl label namespace default istio-injection=enabled --overwrite

kubectl apply -f ../istio/gateway.yaml

echo "Istio instalado. Use 'kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80' para testar."
