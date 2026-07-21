#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v istioctl &> /dev/null; then
  echo "istioctl não encontrado. Instale antes de continuar:"
  echo "https://istio.io/latest/docs/setup/getting-started/#download"
  exit 1
fi

for shard in shard1 shard2; do
  echo "### Instalando Istio no cluster $shard ###"
  kubectl config use-context "kind-${shard}"

  istioctl install --set profile=demo -y
  kubectl label namespace default istio-injection=enabled --overwrite

  kubectl apply -f ../istio/gateway.yaml

  echo "Fixando o NodePort do ingress gateway em 30080"
  echo "(assim o edge router consegue alcançar este shard pela rede docker do kind)"
  kubectl -n istio-system patch svc istio-ingressgateway --type merge -p \
    '{"spec":{"type":"NodePort","ports":[
        {"name":"http2","port":80,"targetPort":8080,"nodePort":30080,"protocol":"TCP"},
        {"name":"status-port","port":15021,"targetPort":15021,"protocol":"TCP"}
    ]}}'
done

kubectl config use-context kind-master
echo
echo "Istio instalado nos shards shard1 e shard2."
