#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

kind create cluster --name cell-poc --config ../kind/kind-cluster.yaml
kubectl cluster-info --context kind-cell-poc
