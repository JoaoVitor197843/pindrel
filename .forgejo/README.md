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
