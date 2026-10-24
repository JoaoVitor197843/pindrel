# CI (Forgejo Actions)

Um workflow por projeto, cada um só dispara quando os caminhos que ele cobre mudam:

| Workflow | Cobre | Label | Análise | Testes |
|---|---|---|---|---|
| `backend.yml` | `backend/**`, `shared/protos/**` | `ci` | `gofmt`, `go vet` | `go test` sem os que usam Postgres |
| `web.yml` | `web/**`, `shared/protos/**` | `ci` | `yarn check` (svelte-check + tsc) | `vitest` (jsdom) |
| `mobile.yml` | `mobile/**`, `shared/protos/**` | `ci-flutter` | `flutter analyze` | `flutter test` sem o que chama o servidor |
| `release.yml` | push na `main` (`backend/**`, `web/**`, `gateway/**`, `Dockerfile`) | `build` | — | monta e publica as imagens amd64+arm64 (ver `deploy/README.md`) |

## Testes que dependem do servidor (não rodam no CI)

- Go: todo teste que usa o banco se chama `TestDB_*` (filtro `-skip '^TestDB_'` no `backend.yml`). O teste `internal/testnaming` falha se algum teste que carrega o `.env` ou abre conexão não tiver esse prefixo.
- Flutter: `Testa a chamada de api para o go` (filtro `--name` no `mobile.yml`).

Se criar um teste novo que use banco/servidor, nomeie-o `TestDB_...` (Go) e ajuste o filtro do mobile; o filtro do Go não muda.
Arquivos de teste vazios (placeholders) são ignorados pelo CI até terem conteúdo.

## Orçamento de RAM do Raspberry Pi (3,8 GB)

Serviços ligados: Forgejo, runner, Vaultwarden e (quando hospedado) o Plany. Ferramentas de
diagnóstico e utilitários (prometheus, grafana, cadvisor, node-exporter, portainer, homepage,
it-tools, stirling-pdf) estão desligados e sem restart automático; os containers de sandbox
(parados) foram mantidos.

| Item | Limite | Uso observado |
|---|---|---|
| Sistema + Docker + Tailscale (sem limite, reserva) | ~600 MiB | ~545 MiB |
| Forgejo | 512 MiB | ~90 MiB |
| Vaultwarden | 256 MiB | ~13 MiB |
| Runner (daemon) | 128 MiB | ~16 MiB |
| Job de CI (um por vez, `capacity: 1`) | 1536 MiB | pico 1,0–1,5 GB (inclui cache) |
| **Plany** (API + Postgres) | **512 MiB teto** (recomendado 256: 128 + 128, como no `compose.yml`) | — |

Soma dos limites: ~3,5 GB de 3,8 GB, com 2 GB de swap de rede de segurança. Se subir outro
serviço, tire a folga daqui antes.

Religar uma ferramenta: `docker update --restart=unless-stopped <nome> && docker start <nome>`.
Os limites de Forgejo e runner estão no `compose.yml` do Forgejo no Pi (backup: `compose.yml.bak-pre-limites`).

## A release só acontece com tudo verde

Em push na `main` o `release.yml` **chama os quatro workflows de CI** (`uses: ./.forgejo/workflows/<x>.yml`; todos
têm `on: workflow_call`) e o job `images` tem `needs:` de todos. Se qualquer teste falhar, nada é publicado: a tag
`latest` não muda e o Pi continua na versão que já roda. O mesmo workflow roda em push na `dev`/PR (com filtro de
caminhos), e na `main` só pelo release (`branches-ignore: [main]` evita rodar em dobro).

| Job | Onde | O quê |
|---|---|---|
| `backend` / `analyze-and-test` | Pi (`ci`) | gofmt, vet e `go test -skip '^TestDB_'` |
| `backend` / `database-tests` | PC (`build`, imagem `ci-pc:1`) | **todos** os testes, os `TestDB_*` também, num Postgres descartável (`services:`), com o schema aplicado por `go run ./cmd/migrate` |
| `web` | Pi (`ci`) | `yarn check` e vitest |
| `gateway` | PC (`build`, imagem `ci-pc:1`) | rustfmt, clippy, `cargo test` (o Pi não tem Rust) |
| `mobile` | Pi (`ci-flutter`) | `flutter analyze` e `flutter test` |
| `images` | PC (`build`, imagem `ci-docker:1`) | só roda se todos acima passarem |

A imagem `ci-pc:1` (Go + Rust com clippy/rustfmt + node + git) se constrói no PC:
`docker build -f .forgejo/images/ci-pc.Dockerfile -t ci-pc:1 .forgejo/images`. O runner do PC tem `capacity: 2`
(o `database-tests` e o `gateway` rodam em paralelo com o resto).

Ler o log de um job: o Forgejo guarda em `/mnt/ssd-data/services/forgejo/data/gitea/actions_log/<dono>/<repo>/<id em hex>/<id>.log.zst`
no Pi (`zstd -dc`); o id da tarefa vem de `GET /api/v1/repos/<dono>/<repo>/actions/tasks`.

## Runner de release (PC)

O `release.yml` roda no runner do **PC** (`~/homelab`, contêiner `runner`), que tem o Docker do host. Uma vez:

1. Construir a imagem do job: `docker build -f .forgejo/images/ci-docker.Dockerfile -t ci-docker:1 .forgejo/images`
2. Em `~/homelab/data/config.yml` (fazer backup antes):
   ```yaml
   runner:
     labels:
       - apk:docker://ci-flutter:1
       - build:docker://ci-docker:1
   container:
     valid_volumes:
       - /var/run/docker.sock      # o job `release` monta o socket do Docker do PC
   ```
3. `cd ~/homelab && docker compose up -d --force-recreate runner`; o label `build` aparece no Forgejo
   (Administração > Runners).

O job monta o socket do Docker: quem consegue editar o `release.yml` na `main` controla o Docker do PC.
Mantenha a `main` protegida (só merge por revisão) e não registre este label em repositórios de terceiros.
