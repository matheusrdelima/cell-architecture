# Cell-Based Architecture PoC — kind + Istio + ArgoCD

PoC de uma **arquitetura em células** rodando localmente em 3 clusters
[kind](https://kind.sigs.k8s.io/): um `master` (GitOps) e dois `shard`
(onde as células rodam de fato). Cada célula tem sua própria API e seu
próprio banco, e adicionar uma célula nova é só um arquivo + `git push`.

## Arquitetura

```
                    edge-router (nginx) — localhost:8080
                       /cell-a ──┐   ┌── /cell-b
                                 ▼   ▼
                  ┌──────────┐     ┌──────────┐
                  │  shard1  │     │  shard2  │   ← Istio + suas células
                  │  cell-a  │     │  cell-b  │      (app + banco isolados)
                  └────▲─────┘     └────▲─────┘
                       └────────┬───────┘
                            ┌────────┐
                            │ master │   ← ArgoCD (GitOps)
                            └────────┘
```

- **`master`**: só roda o ArgoCD, decide onde cada célula é implantada.
- **`shard1` / `shard2`**: rodam Istio e hospedam as células.
- Cada célula = um namespace com API + Postgres, definidos por um
  `values.yaml` que diz o `cellId`, o shard de destino e o path.

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [istioctl](https://istio.io/latest/docs/setup/getting-started/#download)
- Git + uma conta no GitHub para hospedar seu fork

## Como rodar

### 1. Fork e clone

```bash
git clone https://github.com/SEU_USUARIO/SEU_FORK.git
cd SEU_FORK
```

### 2. Suba os clusters e instale as peças

```bash
cd scripts
./01-create-clusters.sh          # cria os 3 clusters kind
./02-install-istio-shards.sh     # instala Istio em shard1 e shard2
./03-install-argocd-master.sh    # instala ArgoCD no master
```

### 3. Aponte para o seu fork

Edite `gitops/root-app.yaml` e troque `SEU_USUARIO/SEU_REPO` pela URL do
seu fork. Depois:

```bash
cd ..
git add gitops/root-app.yaml && git commit -m "chore: meu fork" && git push
cd scripts
```

### 4. Registre os shards e implante as células

```bash
./04-register-shards.sh          # registra shard1 e shard2 no ArgoCD
./05-bootstrap-argocd-apps.sh    # aplica o ApplicationSet
./06-generate-edge-router.sh     # sobe o roteador de entrada
```

### 5. Teste

```bash
./07-test-cells.sh
```

Ou manualmente:

```bash
curl http://localhost:8080/cell-a/
curl http://localhost:8080/cell-b/
```

Cada chamada grava e conta registros no banco daquela célula — prova de
que os dados de `cell-a` e `cell-b` são completamente isolados.

## Adicionando uma nova célula

```bash
cp -r gitops/cells/cell-a gitops/cells/cell-c
```

Edite `gitops/cells/cell-c/values.yaml`:

```yaml
cellId: "c"
targetShard: "shard-2"
gateway:
  pathPrefix: "/cell-c"
```

```bash
git add gitops/cells/cell-c && git commit -m "cell: adiciona cell-c" && git push
cd scripts && ./06-generate-edge-router.sh
```

O ArgoCD detecta a nova pasta sozinho e cria o namespace, o app e o
banco no shard escolhido.

## Limitações (é uma PoC)

- Sem malha Istio entre os shards — cada um é isolado, sem chamada
  direta célula-a-célula entre clusters diferentes.
- A app instala dependências via `pip` no start do container (precisa de
  internet nos nós); numa arquitetura real, use uma imagem já buildada.
- Escolher o `targetShard` é manual.
