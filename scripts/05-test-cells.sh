#!/usr/bin/env bash
set -euo pipefail

echo "Abrindo port-forward para o istio-ingressgateway em localhost:8080..."
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80 >/tmp/pf.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 4

echo
echo "--- Cell A ---"
curl -s http://localhost:8080/cell-a/ ; echo

echo
echo "--- Cell B ---"
curl -s http://localhost:8080/cell-b/ ; echo
