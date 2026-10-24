# Deploy automático (Raspberry Pi)

O Pi **puxa** as versões novas: nada entra nele de fora, e ele não compila nada.

```
push na main ─▶ Forgejo Actions (runner do PC) ─▶ imagens amd64+arm64 no registry do Forgejo
                                                          │
            timer do systemd no Pi (a cada 5 min) ◀───────┘  docker compose pull → up --wait → rollback
```

## O que faz cada peça

| Peça | Onde | O quê |
|---|---|---|
| `.forgejo/workflows/release.yml` | runner do PC (label `build`) | monta `plany` e `plany-gateway` (amd64 + arm64, sem emulação) e publica com as tags `<commit>` e `latest` |
| `compose.registry.yml` | Pi | troca `build:` por `image:` do registry |
| `deploy/update.sh` | Pi | baixa, recria, espera ficar saudável, volta atrás se não ficar |
| `deploy/install-timer.sh` | Pi | instala o timer do systemd que roda o `update.sh` |
| `database.Migrate` (API, golang-migrate) | contêiner | aplica as migrations que vão dentro do binário ao iniciar |

## Atualização sem parar (rolling) e rollback

A API roda em réplicas, e `update.sh` as troca **uma por vez**: sobe uma réplica nova ao lado das antigas, espera
ficar `healthy` e só então para uma antiga; repete até não sobrar nenhuma antiga. As antigas seguem servindo o
tempo todo (o gateway repete numa outra réplica uma conexão que falhou, e vê as novas em até 3 s).

- Se a imagem nova **não** ficar saudável, nenhuma réplica antiga foi tocada: a nova é removida, o par de imagens
  que falhou fica anotado (`.deploy-state/failed`) e a mesma versão não é tentada outra vez, só uma publicada depois.
  Se a falha vier no meio da troca, as réplicas novas são trocadas de volta pelas antigas do mesmo jeito.
- O **gateway** é um contêiner só (rede do host, uma porta): recriá-lo é o único corte, de cerca de meio segundo,
  e só acontece quando a imagem dele mudou.
- Medido no Pi (2 réplicas, 20 requisições por segundo durante a troca): nenhuma falha na troca da API; só a
  recriação do gateway deu ~0,45 s de "conexão recusada".
- A nova réplica sobe, e aplica as migrations, **enquanto as antigas ainda servem**: toda migration precisa ser
  compatível com o código da versão anterior (ver abaixo).

**Limite do rollback: o banco.** As migrations só andam para frente. Uma migration que apaga ou renomeia
coluna deixa o código antigo sem chão. Escreva-as em duas etapas (primeiro adiciona e passa a usar, depois
remove numa release seguinte) para a versão anterior sempre funcionar contra o schema novo.

## Preparar o registry (uma vez, no Forgejo)

1. Conta `joao_vitor` > Configurações > Aplicativos: dois tokens.
   - `plany-ci`, escopo **write:package** (publicar). Vira secret do repositório (abaixo).
   - `plany-pi`, escopo **read:package** (só puxar). Fica no Pi.
2. Repositório Plany > Configurações > Actions > Secrets: `REGISTRY_USER` = `joao_vitor` e
   `REGISTRY_TOKEN` = o token `plany-ci`.
3. O registry fica em `https://raspberry-joao.tail7a986c.ts.net` (Tailscale `serve` + `ROOT_URL` do Forgejo).

## Preparar o runner (uma vez, no PC)

Ver `.forgejo/README.md`, seção "Runner de release": imagem `ci-docker:1`, label `build` e o socket do Docker.

## Preparar o Pi (uma vez)

```sh
# repositório (HTTPS, sem chave: o repo é público)
git clone https://raspberry-joao.tail7a986c.ts.net/joao_vitor/Plany.git ~/plany && cd ~/plany

# configuração: o .env da RAIZ (não o backend/.env, ver o comentário no arquivo)
cp deploy/env.example .env && nano .env      # PORT livre, DB_PASSWORD e JWT_SECRET de verdade

docker login raspberry-joao.tail7a986c.ts.net -u joao_vitor   # opcional enquanto os pacotes forem públicos; senha: o token plany-pi
sh deploy/update.sh                                   # primeira subida, para ver funcionando
sudo sh deploy/install-timer.sh                       # liga o timer
```

## Servidor que já roda o Plany montado à mão (o Pi do homelab)

O Pi tem a pilha em `/mnt/ssd-data/services/plany`, com imagens locais (`plany-api:pi`, `plany-gateway:pi`), um
`compose.pi.yml` com os ajustes dele (réplicas em `127.0.0.1:19100-19109`, porque a faixa padrão tem a 9090 do
Prometheus; Postgres sem porta publicada e com os dados em `./data/postgres`; 2 réplicas) e o `COMPOSE_FILE` no `.env`.
Para passar ao registry **sem perder nada disso**:

```sh
cd /mnt/ssd-data/services/plany

# 1. os compose e o deploy/ vêm do repositório (sparse checkout, sem baixar web/, mobile/ etc.) no mesmo diretório
git init -q -b main && git remote add origin https://raspberry-joao.tail7a986c.ts.net/joao_vitor/Plany.git
git sparse-checkout set --no-cone /.gitignore /compose.yml /compose.lb.yml /compose.registry.yml /deploy/
git fetch -q origin main && git checkout -f -q main

# 2. compose.pi.yml sem as linhas image:/build: (agora vêm do compose.registry.yml)
cat > compose.pi.yml <<'YML'
name: plany
services:
  plany:
    ports: !override
      - "127.0.0.1:19100-19109:8080"
    deploy:
      replicas: 2
  postgres:
    ports: !reset []
    volumes: !override
      - ./data/postgres:/var/lib/postgresql
  gateway:
    environment:
      - UPSTREAMS=127.0.0.1:19100-19109
YML
sed -i 's#^COMPOSE_FILE=.*#COMPOSE_FILE=compose.yml:compose.lb.yml:compose.registry.yml:compose.pi.yml#' .env

# 3. o banco foi migrado à mão (sem schema_migrations): registre a versão já aplicada (só a 1). Com o CLI
#    golang-migrate, de qualquer máquina que alcance o banco: migrate -path backend/internal/database/migrations -database "$URL" force 1
#    ou, direto no contêiner, o mesmo que o `force` faz (tabela e linha no formato do golang-migrate):
docker exec plany-postgres-1 sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -c "CREATE TABLE IF NOT EXISTS schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL); INSERT INTO schema_migrations SELECT 1, false WHERE NOT EXISTS (SELECT 1 FROM schema_migrations)"'

# 4. login no registry (token plany-pi) e primeira atualização
docker login raspberry-joao.tail7a986c.ts.net -u joao_vitor
sh deploy/update.sh && sudo sh deploy/install-timer.sh
```

O `update.sh` lê o `COMPOSE_FILE` do `.env`, então respeita esses ajustes e não força o número de réplicas
(só `PLANY_REPLICAS` define). Sem o passo 3 a API nova recusa subir (o golang-migrate tentaria criar de novo as tabelas) e o
rollback devolve a versão antiga (o erro no log é `relation "users" already exists`).

O usuário precisa estar no grupo `docker`. Ver o que aconteceu: `journalctl -u plany-update -e`.
Parar de atualizar: `sudo systemctl disable --now plany-update.timer`. Fixar uma versão: `PLANY_TAG=<commit>`
no ambiente da unit (`systemctl edit plany-update.service`).

## Variáveis do `update.sh`

`REGISTRY`, `REGISTRY_OWNER`, `PLANY_TAG` (`latest`), `PLANY_REPLICAS` (vazio: o que os compose definem), `WAIT_TIMEOUT` (120),
`PLANY_STATE_DIR` (`./.deploy-state`), `UPDATE_GIT` (1: faz `git pull --ff-only` antes, para trazer mudanças
nos compose).

## Testes

`sh deploy/test_update.sh`: roda o `update.sh` contra um `docker` falso e cobre versão igual, nova, doente
(rollback), repetida, corrigida, sem rede, primeira instalação, atualização concorrente e as units do systemd.
