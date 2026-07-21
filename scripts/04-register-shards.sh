#!/usr/bin/env bash
set -euo pipefail

kubectl config use-context kind-master

# Garante que as entradas de cluster/context no seu ~/.kube/config estão
# com o endereço/porta ATUAIS de cada cluster kind.
for c in master shard1 shard2; do
  kind export kubeconfig --name "$c"
done
kubectl config use-context kind-master

# NOTA: não usamos "argocd cluster add" aqui. Esse comando, depois de criar a
# ServiceAccount localmente, pede para o PRÓPRIO POD do argocd-server validar
# a conectividade com o cluster alvo usando o server URL fornecido. Como esse
# URL só é alcançável a partir da sua máquina (127.0.0.1:<porta>), e não de
# dentro de um pod no cluster master, essa validação nunca teria sucesso
# nesse cenário — por isso registramos o cluster criando o Secret do ArgoCD
# manualmente, com o endereço interno (via rede docker) direto.

for shard in shard1 shard2; do
  shard_label=$(echo "$shard" | sed -E 's/shard([0-9]+)/shard-\1/')
  ctx="kind-${shard}"

  echo
  echo "### Registrando $shard ($shard_label) no ArgoCD ###"

  echo "Criando ServiceAccount + RBAC no cluster $shard (via sua máquina, endereço externo)..."
  kubectl --context "$ctx" apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
  - nonResourceURLs: ["*"]
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-manager-role
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
YAML

  echo "Aguardando o Kubernetes preencher o token do ServiceAccount..."
  TOKEN=""
  for i in $(seq 1 30); do
    TOKEN=$(kubectl --context "$ctx" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null || true)
    [ -n "$TOKEN" ] && break
    sleep 1
  done
  if [ -z "$TOKEN" ]; then
    echo "ERRO: token do ServiceAccount não apareceu a tempo em $shard."
    exit 1
  fi
  TOKEN=$(echo "$TOKEN" | base64 -d)

  CA_DATA=$(kubectl --context "$ctx" config view --raw --minify --flatten \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

  # Endereço que o POD do argocd-server (dentro do cluster master) vai usar —
  # nome do container do control-plane na rede docker compartilhada pelo kind.
  internal_server="https://${shard}-control-plane:6443"
  secret_name="cluster-${shard_label}"

  echo "Criando/atualizando o Secret de cluster no ArgoCD (server: $internal_server)..."
  kubectl --context kind-master -n argocd apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${shard_label}
  server: ${internal_server}
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA_DATA}"
      }
    }
YAML

  echo "$shard_label registrado."
done

kubectl config use-context kind-master

echo
echo "Clusters registrados no ArgoCD (secrets em argocd/*):"
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster
