#!/usr/bin/env bash
set -euo pipefail

echo "--- Cell A (edge router -> shard-1) ---"
curl -s http://localhost:8080/cell-a/ ; echo
echo
echo "--- Cell B (edge router -> shard-2) ---"
curl -s http://localhost:8080/cell-b/ ; echo
