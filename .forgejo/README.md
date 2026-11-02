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

Serviços ligados: Forgejo, runner, Vaultwarden e (quando hospedado) o Pindrel. Ferramentas de
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
| **Pindrel** (API + Postgres) | **512 MiB teto** (recomendado 256: 128 + 128, como no `compose.yml`) | — |

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
| `backend` / `test` | PC (`build`, imagem `ci-pc:1`) | gofmt, vet e **todos** os testes, os `TestDB_*` também, num Postgres descartável (`services:`), com o schema aplicado pelo CLI golang-migrate (`migrate ... up`, instalado na imagem `ci-pc`) |
| `web` | PC (`build`, imagem `ci-pc:1`) | `yarn check` e vitest |
| `gateway` | PC (`build`, imagem `ci-pc:1`) | rustfmt, clippy, `cargo test` (o Pi não tem Rust) |
| `mobile` | PC (`flutter`, imagem `ci-flutter:1` do PC) | `flutter analyze` e `flutter test` |
| `release` / `prebuild` | PC (`build`, imagem `ci-docker:1`) | compila as imagens sem publicar, **enquanto os testes rodam**, para o cache do buildkit estar quente |
| `release` / `images` | PC (`build`, imagem `ci-docker:1`) | só roda se todos acima passarem; empurra as camadas já prontas para o registry do Forgejo e, por último, copia as imagens (mesmo digest) para o Docker Hub (`joaovitor2753/pindrel` e `pindrel-gateway`; secret `DOCKERHUB_TOKEN`) |

Tudo roda no PC, em paralelo (`capacity: 4`). O runner do Pi (`ci`, `ci-flutter`) tem um slot só e era o gargalo:
backend (~5 min) + web (~2 min) + mobile (~6 min) rodavam em fila, ~13 min no total; no PC cada um leva segundos a
poucos minutos e começam juntos. O Pi segue disponível como alternativa (basta trocar o `runs-on`).

A imagem `ci-pc:1` (Go + Rust com clippy/rustfmt + node + yarn + CLI golang-migrate + git) se constrói no PC: Por cima dela vai uma camada com os caches do PC (`ci-pc-cache.Dockerfile`: módulos Go e registry do cargo, ~2,5 GB), porque o `proxy.golang.org` cortava os streams HTTP/2 do `go mod download` na rede lenta do PC e derrubou o backend três vezes; com o cache os jobs de backend e gateway não precisam de rede para as dependências. Construir: `docker tag ci-pc:1 ci-pc:base` (uma vez) e `docker buildx build -f .forgejo/images/ci-pc-cache.Dockerfile -t ci-pc:1 --load --build-context go-mod=$HOME/go/pkg/mod --build-context cargo-registry=$HOME/.cargo/registry .forgejo/images`. O `backend.yml` ainda tenta o download 3 vezes com HTTP/1.1, para quando o `go.mod` passar do cache.
`docker build -f .forgejo/images/ci-pc.Dockerfile -t ci-pc:1 .forgejo/images`. O runner do PC tem `capacity: 4` e os labels `build`, `flutter` e `apk`.

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

## Release versionada (tag `v*`)

`release.yml` publica as imagens a cada push na `main`; o `release-tag.yml` é o que gera a **release que o usuário baixa**.

```sh
git tag v1.2.0 && git push origin v1.2.0      # v1.2.0-rc1 vira pré-release
```

1. Roda os mesmos quatro workflows de teste. Se um falhar, nada é criado.
2. Cria a release como **rascunho** (`.forgejo/scripts/release.sh create`), com as notas geradas do `git log` desde a tag anterior.
3. Em paralelo no PC: `gateway` (binários estáticos musl `amd64` e `arm64`, `.tar.gz`), `linux` (bundle do app Flutter, amd64), `android` (APK assinado) e `docker-tags` (tags `1.2.0` e `1.2` nas imagens que o `release.yml` já publicou para o commit, no registry do Forgejo e no Docker Hub; sem `1.2` em pré-release).
4. Só quando todos terminam, `publish` tira o rascunho. Um build que falha deixa o rascunho invisível; basta rodar de novo (o upload substitui arquivos de mesmo nome) ou apagar o rascunho.

Cada arquivo sobe com o seu `.sha256`. O build number do app é a contagem de commits (só precisa crescer).

- **Imagem do job de app:** `ci-release:1` (ci-flutter + toolchain de desktop Linux: clang, cmake, ninja, GTK, libsecret; o plugin `sodium` compila a libsodium) **mais os caches do build Android** (distribuição e dependências do Gradle, NDK, CMake, pacotes do pub), copiados do próprio PC. A internet do PC é lenta (~150 KB/s medidos) e o job do Android, baixando tudo a cada run, estourou os 45 min; com os caches o build leva ~3 min. Para construir, rode antes um `flutter build apk --release` em `mobile/` no PC (isso enche `~/.gradle` e `~/Android/Sdk`) e depois, na raiz: `docker buildx build -f .forgejo/images/ci-release.Dockerfile -t ci-release:1 --load --build-context gradle-home=$HOME/.gradle --build-context android-sdk=$HOME/Android/Sdk --build-context pub-cache=$HOME/.pub-cache .forgejo/images`. Se o app passar a pedir outra versão do NDK ou do CMake, ajuste as versões no Dockerfile (o log do job diz `Install NDK ... v.X`). Os jobs a usam com `runs-on: build` + `container:`, então não é preciso mexer nos labels do runner.
- **Token:** o job tenta o token automático do Forgejo; se ele não puder criar releases, crie o secret `RELEASE_TOKEN` (token de acesso com `write:repository`).
- **A imagem do commit precisa existir:** `docker-tags` falha com uma mensagem clara se o commit marcado não gerou imagem (mudança fora dos caminhos do `release.yml`); rode o `release.yml` à mão na `main` e repita.
- **Testes do script da API:** `sh .forgejo/scripts/test_release.sh` (roda o `release.sh` contra uma API falsa do Forgejo; não está no CI, como o `deploy/test_update.sh`).
- **Assinatura do Android:** secrets `ANDROID_KEYSTORE_BASE64` (o `.jks` em base64) e `ANDROID_KEYSTORE_PASSWORD` (mesma senha para a loja e a chave; alias `plany`). **A mesma chave tem de assinar todas as versões**, senão quem já instalou não consegue atualizar: guarde um backup fora do PC. O job confere o certificado do APK e falha se for o de debug.

## Windows e macOS (GitHub)

O Flutter não compila para Windows nem macOS a partir do runner Linux do PC, então esses dois saem do **GitHub Actions**
(`.github/workflows/release-desktop.yml`; o Forgejo lê só `.forgejo/workflows`, o GitHub só `.github`). O repositório
público `JoaoVitor197843/pindrel` é um **espelho de push** do Forgejo: ele leva só o git (branches e tags), nunca issues, PRs nem releases.

1. Em push na `main` que mexe no app: o GitHub só compila Windows, macOS e iOS (sem assinatura), para pegar quebra cedo.
2. Em tag `v*`: o espelho leva a tag, o GitHub compila e publica `pindrel-app_<tag>_windows_amd64.zip` e `pindrel-app_<tag>_macos_universal.zip` numa release dele.
3. No Forgejo, o job `desktop` do `release-tag.yml` roda **depois** do `publish`, espera esses arquivos aparecerem (até 45 min cada) e os anexa à release (`github-assets.sh` + `release.sh upload`). Se o GitHub atrasar ou cair, só esse job falha (`continue-on-error`) e a release principal já está pública.
4. Sem assinatura: o Windows mostra o SmartScreen na primeira execução, e o macOS exige "Abrir" pelo menu de contexto. O iOS só compila; sem conta Apple paga não há o que instalar.

Configurar o espelho (uma vez, pelo navegador): Forgejo > repositório > Configurações > Repositório > **Espelhos de push**: URL
`https://github.com/JoaoVitor197843/pindrel.git`, usuário `JoaoVitor197843` e, como senha, um token do GitHub **restrito a este repositório** (fine-grained, só *Contents: Read and write*). Marcar "sincronizar ao fazer commit".

Testes do script que baixa do GitHub: `sh .forgejo/scripts/test_github_assets.sh` (contra um GitHub falso, sem rede).

## Downloads públicos (release do GitHub)

O Forgejo só é alcançável pela Tailscale, então a página pública de downloads é a **release do GitHub**. O job `github-release` do
`release-tag.yml` roda depois do `desktop` e **copia** a release do Forgejo para lá (mesmas notas, mesmos arquivos; os zips de
Windows e macOS já estão lá, vêm do próprio GitHub). O Forgejo continua sendo a fonte da verdade; o GitHub guarda uma cópia que um novo run só atualiza
(`.forgejo/scripts/github-release.sh`, testado com `sh .forgejo/scripts/test_github_release.sh`). A tag precisa já estar no GitHub (o espelho a leva),
porque criar uma release para uma tag inexistente faz o GitHub criar a tag a partir da branch padrão.

Precisa do secret **`GH_RELEASE_TOKEN`** no Forgejo (Configurações > Actions > Secrets): um token do GitHub *fine-grained* restrito ao repositório
`pindrel`, com **Contents: Read and write** (cobre releases e envio de arquivos). O nome não pode começar com `GITHUB_`. Se o secret faltar ou o GitHub cair,
só esse job falha (`continue-on-error`) e a release do Forgejo já está pública.

Além de compilar, o GitHub **abre o app** em cada plataforma: `.github/workflows/smoke.yml` roda o teste de integração
`mobile/integration_test/app_smoke_test.dart` no Windows, no macOS e num emulador Android (o Linux fica de fora: precisa de um chaveiro de
desktop que o runner sem tela não tem; eu o testo à mão). Ele roda a cada push na `main` que mexe no app e a cada tag, e **não segura a release**: um
smoke vermelho é um aviso para olhar. Localmente: `cd mobile && fvm flutter test integration_test/app_smoke_test.dart -d linux` (precisa de uma sessão gráfica).
