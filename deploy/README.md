# Deploy automático (Raspberry Pi)

O Pi **puxa** as versões novas: nada entra nele de fora, e ele não compila nada.

```
push na main ─▶ testes no Forgejo ─▶ (todos verdes) ─▶ GitHub Actions ─▶ imagens amd64+arm64 no Docker Hub
                                                          │
            timer do systemd no Pi (a cada 5 min) ◀───────┘  docker compose pull → up --wait → rollback
```

## O que faz cada peça

| Peça | Onde | O quê |
|---|---|---|
| `.github/workflows/release-images.yml` | GitHub Actions | monta `pindrel` e `pindrel-gateway` (amd64 + arm64, sem emulação) e publica no Docker Hub (`joaovitor2753/...`) com as tags `<commit completo>` e `latest`. Os testes rodam no Forgejo (`.forgejo/workflows/release.yml`), que só pede o build ao GitHub se todos passarem |
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

## Preparar o registry (uma vez, no GitHub)

1. Docker Hub > Account settings > Personal access tokens: crie um token **Read & Write**.
2. Repositório no GitHub > Settings > Secrets and variables > Actions > New repository secret: `DOCKERHUB_TOKEN` = o token.
   Sem ele o `release-images.yml` para logo no início com uma mensagem clara.
   O Forgejo dispara esse workflow pela API: o secret `GH_RELEASE_TOKEN` do **Forgejo** (token fino do GitHub para este
   repositório) precisa de **Contents: Read and write** e **Actions: Read and write**.
3. Os repositórios `joaovitor2753/pindrel` e `joaovitor2753/pindrel-gateway` são públicos: a Pi puxa sem login.
4. Para a Pi puxar de outro lugar, ponha no `.env` dela `REGISTRY` e `REGISTRY_OWNER` (o padrão é `docker.io` e `joaovitor2753`).

## Runner do PC

O runner do PC só roda os testes (imagem `ci-pc:1`); não compila mais as imagens. Ver `.forgejo/README.md`.

## Preparar o Pi (uma vez)

```sh
# repositório (HTTPS, sem chave: o repo é público)
git clone https://raspberry-joao.tail7a986c.ts.net/joao_vitor/Pindrel.git ~/pindrel && cd ~/pindrel

# configuração: o .env da RAIZ (não o backend/.env, ver o comentário no arquivo)
cp deploy/env.example .env && nano .env      # PORT livre, DB_PASSWORD e JWT_SECRET de verdade

sh deploy/update.sh                                   # primeira subida, para ver funcionando
sudo sh deploy/install-timer.sh                       # liga o timer
```

## Servidor que já roda o Pindrel montado à mão (o Pi do homelab)

O Pi tem a pilha em `/mnt/ssd-data/services/pindrel`, com imagens locais (`pindrel-api:pi`, `pindrel-gateway:pi`), um
`compose.pi.yml` com os ajustes dele (réplicas em `127.0.0.1:19100-19109`, porque a faixa padrão tem a 9090 do
Prometheus; Postgres sem porta publicada e com os dados em `./data/postgres`; 2 réplicas) e o `COMPOSE_FILE` no `.env`.
Para passar ao registry **sem perder nada disso**:

```sh
cd /mnt/ssd-data/services/pindrel

# 1. os compose e o deploy/ vêm do repositório (sparse checkout, sem baixar web/, mobile/ etc.) no mesmo diretório
git init -q -b main && git remote add origin https://raspberry-joao.tail7a986c.ts.net/joao_vitor/Pindrel.git
git sparse-checkout set --no-cone /.gitignore /compose.yml /compose.lb.yml /compose.registry.yml /compose.tls.yml /deploy/
git fetch -q origin main && git checkout -f -q main

# 2. compose.pi.yml sem as linhas image:/build: (agora vêm do compose.registry.yml)
cat > compose.pi.yml <<'YML'
name: pindrel
services:
  pindrel:
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
docker exec pindrel-postgres-1 sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -c "CREATE TABLE IF NOT EXISTS schema_migrations (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL); INSERT INTO schema_migrations SELECT 1, false WHERE NOT EXISTS (SELECT 1 FROM schema_migrations)"'

# 4. primeira atualização (as imagens do Docker Hub são públicas: sem login)
sh deploy/update.sh && sudo sh deploy/install-timer.sh
```

O `update.sh` lê o `COMPOSE_FILE` do `.env`, então respeita esses ajustes e não força o número de réplicas
(só `PINDREL_REPLICAS` define). Sem o passo 3 a API nova recusa subir (o golang-migrate tentaria criar de novo as tabelas) e o
rollback devolve a versão antiga (o erro no log é `relation "users" already exists`).

O usuário precisa estar no grupo `docker`. Ver o que aconteceu: `journalctl -u pindrel-update -e`.
Parar de atualizar: `sudo systemctl disable --now pindrel-update.timer`. Fixar uma versão: `PINDREL_TAG=<commit>`
no ambiente da unit (`systemctl edit pindrel-update.service`).

## HTTPS e pareamento no Raspberry Pi

A imagem `pindrel-gateway` publicada já traz o código de HTTPS (amd64 e arm64, compilada na máquina do build com o `zig` como
compilador C do alvo, sem emulação; ver `gateway/Dockerfile` e `gateway/cross/`). Ele fica **desligado** até o ambiente pedir:
numa Pi que não faz nada disso, nada muda. Para ligar, com as imagens do registry:

```sh
cd /mnt/ssd-data/services/plany          # onde está a pilha

# 1. traga o compose.tls.yml para o checkout (o sparse checkout só tinha os outros)
git sparse-checkout add /compose.tls.yml && git pull --ff-only

# 2. coloque-o por último no COMPOSE_FILE do .env (depois do registry e do compose.pi.yml)
sed -i 's#^COMPOSE_FILE=.*#&:compose.tls.yml#' .env
grep ^COMPOSE_FILE .env

# 3. opcional, no .env: outros nomes no certificado (o nome da Pi na rede) e quantas pessoas pareiam ao mesmo tempo
#    TLS_SANS=raspberrypi.local
#    PAIRING_MAX_ROOMS=6

# 4. a porta segura (8443/tcp) precisa estar liberada no firewall da Pi, se houver um
sudo ufw allow 8443/tcp 2>/dev/null || true

sh deploy/update.sh
```

- O volume `gateway-data` guarda a autoridade certificadora (`/data/tls`): **não apague**, senão todo aparelho pareado precisa
  parear de novo. O `update.sh` troca só a imagem, não o volume.
- O código mestre aparece no log do gateway (`docker logs <gateway> | grep "código mestre"`), uma vez por início e depois de cada uso.
- A RAM do gateway com HTTPS é de poucos MiB em repouso; o teto de 48 MiB do `compose.tls.yml` cobre ~1000 WebSockets.
- O mDNS anuncia a porta comum (HTTP) e, junto, a segura (`tls=<porta>` no registro): quem entende prefere o HTTPS, quem não entende
  usa a comum. O app confirma a porta segura em `/server/info/`.
- `HTTP_MODE` é `full` por padrão: a porta comum responde tudo, sem exigir certificado instalado em lugar nenhum. `HTTP_MODE=redirect`
  deixa a porta comum só com a página de conexão e redireciona o resto ao HTTPS.

## DNS da Pi com Tailscale

O `git pull` do `update.sh` usa o nome do Forgejo no tailnet (`raspberry-joao.tail7a986c.ts.net`). Com o NetworkManager, o
`/etc/resolv.conf` pode listar o DNS do roteador primeiro, que responde "no such host" a esse nome (e o resolvedor para aí,
sem tentar o seguinte). Sintoma no `journalctl -u pindrel-update`: `Could not resolve host`. Correção (na Pi, com o nome do
perfil Wi-Fi que `nmcli con show --active` mostra):

```sh
sudo nmcli con mod "<perfil>" ipv4.dns "100.100.100.100 <ip do roteador>" ipv4.ignore-auto-dns yes
sudo nmcli dev reapply wlan0       # sem derrubar a conexão
```

O `100.100.100.100` resolve os nomes do tailnet e repassa o resto; o do roteador fica de reserva. Para desfazer:
`sudo nmcli con mod "<perfil>" ipv4.dns "" ipv4.ignore-auto-dns no && sudo nmcli dev reapply wlan0`. Teste com uma reversão
agendada (`systemd-run --on-active=240 ...`) antes de confiar, para não perder o acesso se algo der errado.

## Variáveis do `update.sh`

`REGISTRY`, `REGISTRY_OWNER`, `PINDREL_TAG` (`latest`), `PINDREL_REPLICAS` (vazio: o que os compose definem), `WAIT_TIMEOUT` (120),
`PINDREL_STATE_DIR` (`./.deploy-state`), `UPDATE_GIT` (1: faz `git pull --ff-only` antes, para trazer mudanças
nos compose).

## Testes

`sh deploy/test_update.sh`: roda o `update.sh` contra um `docker` falso e cobre versão igual, nova, doente
(rollback), repetida, corrigida, sem rede, primeira instalação, atualização concorrente e as units do systemd.
