# CI (Forgejo Actions)

Um workflow por projeto, cada um só dispara quando os caminhos que ele cobre mudam:

| Workflow | Cobre | Label | Análise | Testes |
|---|---|---|---|---|
| `backend.yml` | `backend/**`, `shared/protos/**` | `ci` | `gofmt`, `go vet` | `go test` sem os que usam Postgres |
| `web.yml` | `web/**`, `shared/protos/**` | `ci` | `yarn check` (svelte-check + tsc) | `vitest` (jsdom) |
| `mobile.yml` | `mobile/**`, `shared/protos/**` | `ci-flutter` | `flutter analyze` | `flutter test` sem o que chama o servidor |

## Testes que dependem do servidor (não rodam no CI)

- Go: `TestHandler_*`, `TestService_*`, `TestJwtToken_*`, `TestPostgresConnection` (filtro `-skip` no `backend.yml`).
- Flutter: `Testa a chamada de api para o go` (filtro `--name` no `mobile.yml`).

Se criar um teste novo que use banco/servidor, ajuste o filtro (ou prefira marcá-lo com build tag / `@Tags`).
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
