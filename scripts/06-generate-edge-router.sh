#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CONF=/tmp/edge-router.conf

# Mapa shard -> nome do container docker do control-plane daquele cluster kind.
# Usamos uma função com "case" em vez de array associativo (declare -A) porque
# o /bin/bash padrão do macOS é a versão 3.2, que não suporta arrays
# associativos (só existem a partir do bash 4).
shard_host() {
  case "$1" in
    shard-1) echo "shard1-control-plane" ;;
    shard-2) echo "shard2-control-plane" ;;
    # Ao adicionar um shard novo, inclua uma linha aqui:
    # shard-3) echo "shard3-control-plane" ;;
    *) echo "" ;;
  esac
}

echo "Gerando roteamento a partir de gitops/cells/*/values.yaml ..."

{
  echo "server {"
  echo "    listen 80;"
} > "$CONF"

for dir in ../gitops/cells/*/; do
  cell_file="${dir}values.yaml"
  [ -f "$cell_file" ] || continue

  prefix=$(grep 'pathPrefix' "$cell_file" | sed -E 's/.*pathPrefix:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/')
  shard=$(grep 'targetShard' "$cell_file" | sed -E 's/.*targetShard:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/')
  host="$(shard_host "$shard")"

  if [ -z "$host" ]; then
    echo "AVISO: shard '$shard' desconhecido em $cell_file (adicione um caso na função shard_host deste script). Pulando."
    continue
  fi

  {
    echo "    location ${prefix}/ {"
    echo "        proxy_pass http://${host}:30080${prefix}/;"
    echo "    }"
  } >> "$CONF"
  echo "  -> ${prefix} roteado para ${shard} (${host})"
done

echo "}" >> "$CONF"

echo
echo "--- nginx.conf gerado ---"
cat "$CONF"
echo "-------------------------"

echo
echo "Subindo/atualizando o container do edge router..."
docker rm -f edge-router >/dev/null 2>&1 || true
docker run -d --name edge-router \
  --network kind \
  -p 8080:80 \
  -v "$CONF:/etc/nginx/conf.d/default.conf:ro" \
  nginx:alpine >/dev/null

echo "Edge router disponível em http://localhost:8080"
