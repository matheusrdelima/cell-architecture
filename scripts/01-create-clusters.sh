#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

for c in master shard1 shard2; do
  echo "### Criando cluster kind: $c ###"
  kind create cluster --name "$c" --config "../kind/kind-${c}.yaml"
done

echo
echo "Clusters criados:"
kubectl config get-contexts | grep -E "kind-(master|shard1|shard2)"
