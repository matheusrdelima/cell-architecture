# PoC — Arquitetura em Células (Cell-Based Architecture)

PoC simples e funcional de uma arquitetura baseada em células, rodando em
`kind`, com **Istio** (service mesh + roteamento) e **ArgoCD** (GitOps).
Cada célula tem sua própria aplicação e seu próprio banco de dados,
isolados em um namespace dedicado.

## Arquitetura

```
                        ┌─────────────────────────┐
   cliente ── HTTP ──▶  │  Istio Ingress Gateway   │
                        └───────────┬──────────────┘
                     /cell-a │             │ /cell-b
                             ▼             ▼
                  ┌────────────────┐  ┌────────────────┐
                  │  ns: cell-a    │  │  ns: cell-b    │
                  │  ┌──────────┐  │  │  ┌──────────┐  │
                  │  │ cell-app │  │  │  │ cell-app │  │
                  │  └────┬─────┘  │  │  └────┬─────┘  │
                  │       ▼        │  │       ▼        │
                  │  ┌──────────┐  │  │  ┌──────────┐  │
                  │  │ cell-db  │  │  │  │ cell-db  │  │
                  │  │(postgres)│  │  │  │(postgres)│  │
                  │  └──────────┘  │  │  └──────────┘  │
                  └────────────────┘  └────────────────┘
```

- **Istio Gateway** único (`istio/gateway.yaml`), na `istio-system`, recebe
  todo o tráfego de entrada.
- Cada célula tem um **VirtualService** que casa por prefixo de path
  (`/cell-a`, `/cell-b`, ...) e roteia só para os serviços daquele
  namespace — nenhuma célula enxerga ou depende da outra.
- Cada célula é um **namespace isolado** (`cell-<id>`) com:
  - `cell-app`: um Deployment com uma API Flask simples.
  - `cell-db`: um StatefulSet Postgres com seu próprio PVC.
  - `PeerAuthentication` em modo `STRICT` (mTLS obrigatório dentro da célula).
- Tudo é gerenciado por um **Helm chart único** (`gitops/cell-chart`),
  parametrizado por um `values.yaml` por célula
  (`gitops/cells/<nome>/values.yaml`).
- Um **ArgoCD ApplicationSet** (`gitops/root-app.yaml`) usa o *git directory
  generator* para descobrir automaticamente cada pasta em `gitops/cells/*`
  e criar/sincronizar uma Application por célula.

### Por que isso deixa fácil adicionar células novas

Adicionar uma célula = criar uma pasta com um `values.yaml` e dar `git push`.
O ArgoCD ApplicationSet detecta a nova pasta sozinho e cria o namespace, o
app, o banco e as regras de roteamento — sem tocar em nenhum outro
componente do cluster.

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [istioctl](https://istio.io/latest/docs/setup/getting-started/#download)
- Um repositório git próprio (GitHub, GitLab, etc.) para hospedar este
  diretório — o ArgoCD sincroniza a partir dele, não do seu disco local.

## Passo a passo

### 1. Suba o cluster kind

```bash
cd scripts
./01-create-cluster.sh
```

### 2. Instale o Istio

```bash
./02-install-istio.sh
```

### 3. Instale o ArgoCD

```bash
./03-install-argocd.sh
```

Guarde a senha do `admin` que o script imprime.

### 4. Publique este repositório no seu git

```bash
cd ..
git init
git add .
git commit -m "poc: arquitetura em celulas"
git remote add origin https://github.com/SEU_USUARIO/SEU_REPO.git
git push -u origin main
```

Depois edite `gitops/root-app.yaml` e troque as duas ocorrências de
`https://github.com/SEU_USUARIO/SEU_REPO.git` pela URL real do seu
repositório.

### 5. Aplique o ApplicationSet (bootstrap GitOps)

```bash
cd scripts
./04-bootstrap-argocd-apps.sh
```

Acompanhe:

```bash
kubectl -n argocd get applications
kubectl get ns | grep cell-
```

Em alguns segundos você deve ver os namespaces `cell-a` e `cell-b` criados
e sincronizados.

### 6. Teste

```bash
./05-test-cells.sh
```

Ou manualmente:

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80
curl http://localhost:8080/cell-a/
curl http://localhost:8080/cell-b/
```

Cada chamada grava uma linha no Postgres **daquela célula** e devolve a
contagem — prova de que os dados de `cell-a` e `cell-b` são
completamente independentes.

## Como adicionar uma nova célula

1. Copie um dos exemplos:
   ```bash
   cp -r gitops/cells/cell-a gitops/cells/cell-c
   ```
2. Edite `gitops/cells/cell-c/values.yaml`:
   ```yaml
   cellId: "c"
   gateway:
     pathPrefix: "/cell-c"
   ```
3. Commit e push:
   ```bash
   git add gitops/cells/cell-c
   git commit -m "cell: adiciona cell-c"
   git push
   ```

O ArgoCD ApplicationSet detecta a nova pasta no próximo poll (por padrão a
cada ~3 minutos, ou force com `argocd app sync` / clique em *Refresh* na
UI) e cria automaticamente o namespace `cell-c`, o app, o banco e o
roteamento — nada mais precisa ser tocado.

## Limitações conscientes (é uma PoC)

- A imagem da aplicação instala `flask`/`psycopg2-binary` via `pip` no
  start do container (precisa de acesso à internet a partir dos nós do
  cluster). Suficiente para demo; numa arquitetura real cada célula teria
  sua própria imagem versionada em um registry.
- Sem autenticação/gateway de API, rate limiting ou observabilidade
  (Kiali/Grafana/Prometheus do próprio Istio addon podem ser plugados
  depois, `istioctl install --set profile=demo` já os prepara para
  instalação via `samples/addons`).
- `repoURL` no `root-app.yaml` precisa ser um repositório git real e
  acessível pelo ArgoCD (público, ou com credencial configurada no ArgoCD
  para repositório privado).
