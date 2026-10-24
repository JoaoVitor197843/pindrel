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
| `database.Migrate` (API) | contêiner | aplica as migrations que vão dentro do binário ao iniciar |

## Rollback

`update.sh` guarda o id da imagem que roda. Se a nova não ficar `healthy` em `WAIT_TIMEOUT` (120 s), ele
aponta a tag de volta para a imagem de antes, recria os contêineres e **anota o par de imagens que falhou**
(`.deploy-state/failed`): a mesma versão não é tentada outra vez, só uma nova publicada depois.

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

docker login raspberry-joao.tail7a986c.ts.net -u joao_vitor   # senha: o token plany-pi (read:package)
sh deploy/update.sh                                   # primeira subida, para ver funcionando
sudo sh deploy/install-timer.sh                       # liga o timer
```

O usuário precisa estar no grupo `docker`. Ver o que aconteceu: `journalctl -u plany-update -e`.
Parar de atualizar: `sudo systemctl disable --now plany-update.timer`. Fixar uma versão: `PLANY_TAG=<commit>`
no ambiente da unit (`systemctl edit plany-update.service`).

## Variáveis do `update.sh`

`REGISTRY`, `REGISTRY_OWNER`, `PLANY_TAG` (`latest`), `PLANY_REPLICAS` (2), `WAIT_TIMEOUT` (120),
`PLANY_STATE_DIR` (`./.deploy-state`), `UPDATE_GIT` (1: faz `git pull --ff-only` antes, para trazer mudanças
nos compose).

## Testes

`sh deploy/test_update.sh`: roda o `update.sh` contra um `docker` falso e cobre versão igual, nova, doente
(rollback), repetida, corrigida, sem rede, primeira instalação, atualização concorrente e as units do systemd.
