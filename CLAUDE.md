# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project priorities

1. **Absolute minimum RAM use.** Plany must run on weak devices (an old Raspberry Pi, an old phone). Target: **hard ceiling of 512 MB RAM**, **recommended 256 MB**, counting everything needed to run, database included. The limit applies **per instance**; behind a load balancer each API instance follows the same individual ceiling. In practice: prefer small dependencies, don't hold whole datasets in memory, cap connections and memory spikes (e.g. key derivation). Judge every new dependency against this.
2. **Cost split between client and server.** Neither side should absorb all the overhead for the other. Where overhead is unavoidable (security, cryptography) it takes priority, but balanced between the parties.

## Project

Plany is a self-hosted, Notion-style notes workspace (AGPL-3.0). Three clients-of-one-API and a gateway live in this monorepo:

- `backend/` — Go API (Go module name is `plany`, so imports look like `plany/internal/auth`)
- `gateway/` — Rust (the only Rust in the project): the front-facing process of a deployment. Load balancer over the API replicas, per-IP rate limits, mDNS announcement and LAN discovery (`GET /server/discover/`). Static binary of ~1.4 MB, ~2-5 MB of RAM; runs natively on Linux (x86/arm), Windows and macOS (only `cargo check` was run for the non-Linux targets) or as a `scratch` Docker image of ~2.5 MB. Nothing in the Go API depends on it.
- `web/` — Svelte 5 + Vite + Tailwind SPA (Yarn Berry with PnP SDKs in `web/.yarn`)
- `mobile/` — Flutter app (mobile + desktop), Flutter version pinned via FVM (`mobile/.fvmrc`)
- `shared/protos/` — Protobuf schema shared by all three

Only the auth routes are implemented so far. Notes, vault and bulk sync are planned.

**Client/server roles:** the Go API exists for authentication, cloud storage and sync. `mobile/` is fully self-sufficient (local storage, works without any server; the API is optional). `web/` ships embedded in the API image and depends on it for login, but is semi-self-sufficient: notes are kept in the browser's IndexedDB (`idb`). Both login screens will have a top tab to add another server: web **always defaults to the embedded server** (other servers found via mDNS are extra options; browsers cannot do mDNS, so the embedded backend does the discovery and hands the list to the web), mobile picks a random server found on the current network. mDNS (`_plany._tcp`) advertises the front-facing service, i.e. the gateway, never each API instance. The gateway side is implemented (see Gateway); the web and mobile login tabs are not.

**The API must be explicitly stateless** so it can run behind a load balancer: no session/cache/counter state in process memory; state lives in Postgres or the JWT; `JWT_SECRET` is shared across instances. The in-memory login/register limiters and the global `httprate` limit are per instance, so they are behind `IN_APP_RATE_LIMIT` (default `true`, for the single-instance setup); with the gateway overlay it is `false` and the gateway does the limiting instead.

## Commands

### Backend (run from `backend/`)

```bash
cp .env.example .env            # config.Load() fails if any required var is missing
go run ./cmd/api                # needs a reachable Postgres
go test ./...                   # integration tests: need Postgres + backend/.env
go test ./internal/auth -run TestDB_Service_Register_DuplicateEmail -v   # run a single test
sqlc generate                   # regenerate internal/database/db from queries/ + migrations/
swag init -g cmd/api/main.go    # regenerate docs/ (Swagger) from handler annotations
```

Tests are not unit tests with mocks. `setup_test.go` files load `../../.env` (i.e. `backend/.env`) and connect to the real database. They create dummy users and delete them in `t.Cleanup`. Start Postgres first, for example with `docker compose up postgres`, which exposes port 5432.

Migrations in `internal/database/migrations` use the golang-migrate naming scheme (`NNNNNN_name.up/down.sql`). The API applies them itself at startup (`database.Migrate`, `internal/database/migrate.go`): the `*.up.sql` files are embedded in the binary, applied in order, each in its own transaction with the `schema_migrations` bump (same table layout as golang-migrate, so a database migrated by hand with that tool carries on), under a Postgres advisory lock so replicas starting together do not race; a `dirty` database is refused. Migrations only go forward and the automatic rollback of a bad release (`deploy/update.sh`) does not undo them: write destructive changes in two releases. The tests (`TestDB_Migrate_*`) migrate throwaway schemas of the real database, so apply the migrations by running the API once (or `database.Migrate`) before running the other tests.

### Web (run from `web/`)

```bash
yarn install
yarn dev        # http://localhost:5173
yarn build
yarn check      # svelte-check + tsc
yarn vitest     # tests (*.test.ts next to sources); no "test" script is defined
```

### Mobile (run from `mobile/`)

```bash
fvm flutter pub get
fvm flutter run            # or: fvm flutter run -d linux
fvm flutter test
fvm flutter analyze        # flutter_lints
```

### Gateway (run from `gateway/`)

```bash
cargo test                     # unit + integration (fake replicas) + binary + mDNS; mDNS tests say so and pass without multicast
cargo fmt --check && cargo clippy --all-targets -- -D warnings
cargo build --release          # target/release/gateway
# 64-bit Raspberry Pi from another machine, no C toolchain (gateway/.cargo/config.toml sets rust-lld + crt-static + pic;
# without them the binary linked this way segfaulted at startup on a real Pi 4):
rustup target add aarch64-unknown-linux-musl && cargo build --release --target aarch64-unknown-linux-musl
UPSTREAMS=127.0.0.1:9101-9110 GATEWAY_PORT=8200 SERVER_NAME=Casa cargo run --release
```

Environment: `UPSTREAMS` (required, `ip:port[-port]` list, e.g. `127.0.0.1:9000-9099,10.0.0.5:8080`), `GATEWAY_PORT` (8080), `SERVER_NAME` (Plany), `MDNS_ENABLED` (true), `MDNS_INTERFACES`, `MDNS_REFRESH_SECS` (15; 0 = off), `KNOWN_PROBE_SECS` (15; 0 = off), `KNOWN_SERVERS_FILE` (unset = memory only), `RATE_LIMIT_ENABLED` (true), `PROBE_INTERVAL_SECS` (3), `MAX_CONNECTIONS` (1024), `MAX_BODY_BYTES` (1 MiB). The gateway protobuf (`ErrorHttp`, `DiscoveredServers`) is encoded by hand; `gateway/tests/golden/*.bin` are generated with `protoc --encode` and decoded by both the Rust tests and `backend/internal/api/golden_test.go`, and a test checks the field numbers against `shared/protos`. After changing `server.proto`/`auth.proto` regenerate them. Behaviour to keep: the gateway is the edge, so it replaces any client `X-Forwarded-For`; a failed *connection* is retried on the next replica even for POST (the replica never saw it), a timeout is not (504); no WebSocket upgrade support yet (needed for the planned `/ws/sync`).

### Protobuf (run from repo root)

```bash
make proto       # proto-go + proto-dart + proto-ts
make proto-go    # -> backend/internal/api/dto/*.pb.go (via go_package option)
make proto-ts    # -> web/src/types/shared/protos/*.ts (ts-proto)
```

`make proto-dart` writes exactly to `mobile/lib/shared/protos/` (it passes `-Ishared/protos` so the output is flat). It needs `protoc-gen-dart` on `PATH` (`~/.pub-cache/bin`).

### Docker

`compose.registry.yml` (third overlay, after `compose.lb.yml`) swaps `build:` for the released images `raspberry-joao.tail7a986c.ts.net/joao_vitor/{plany,plany-gateway}:${PLANY_TAG:-latest}`. Release: `.forgejo/workflows/release.yml` builds both images for amd64+arm64 on the PC's Forgejo runner (label `build`, Docker socket of the host, **no emulation**: the Dockerfiles run their build stages on `$BUILDPLATFORM` and cross-compile; the final stages have no `RUN`, and the app image uses the numeric user `10001:10001`) and pushes them to the Forgejo registry (over Tailscale HTTPS). The Raspberry Pi pulls: `deploy/update.sh` (systemd timer from `deploy/install-timer.sh`, every 5 min) does `compose pull` and a **rolling update** of the API replicas (a new replica next to the old ones, wait healthy, then stop one old one, repeat; if the new image is not healthy no old replica was touched), then recreates the gateway (the only cut, ~0.5 s, and only when its image changed); on failure it swaps back to the previous images and records the failed pair so it is not retried. It honours the host's own `COMPOSE_FILE` (the homelab Pi layers a `compose.pi.yml`). Details, tokens and one-time setup in `deploy/README.md`; tests with `sh deploy/test_update.sh`.

`docker compose -f compose.yml -f compose.lb.yml up -d --build --scale plany=2` adds the Rust `gateway` (`gateway/Dockerfile`, multi-stage to a `scratch` image, 16m cap, host network, healthcheck `/gateway healthcheck`) in front of the replicas, which stop publishing on the network and publish only on `127.0.0.1:9000-9099` (one port per replica, up to 100; widen both ranges for more) because the host network has no docker DNS. The replicas then run with `IN_APP_RATE_LIMIT=false` (the gateway limits). Measured with 2 replicas: gateway container 0.9 MiB (cgroup) / 1.8 MB RSS, API 43-63 MiB each (peaks after Argon2 logins), Postgres ~24 MiB. The real replica limit is Postgres (`max_connections=20`: with `DB_MAX_CONNS` pools, ~8 replicas at the default; more needs a smaller pool or PgBouncer). A plain `docker compose up` has no gateway and therefore no mDNS.

`docker compose up --build` builds one image (the `Dockerfile` builds both `web/` and the Go server) and runs it with `postgres:18-alpine`. The final image is a stripped static Go binary on Alpine, run as non-root with `GOMEMLIMIT=100MiB` and a `wget` healthcheck on `/`. The container always listens on 8080; compose's `PORT` only picks the host port. Compose reads `backend/.env` when present (optional) and also sets defaults inline. It enforces the RAM budget: `mem_limit` 128m for `plany` + 128m for `postgres` (= the recommended 256 MB), `GOMEMLIMIT=100MiB`, small Postgres buffers, and Postgres published on loopback only.

## Backend architecture

**Wire format is Protobuf, not JSON.** Request bodies are `proto.Unmarshal`ed into types from `internal/api/dto` (generated from `shared/protos/*.proto`). Responses go out as `application/x-protobuf` through `api.WriteResponse(w, status, msg)` and `api.WriteError(w, status, code, message)` in `internal/api/response_http.go`. To add or change a payload, edit the `.proto` file, run `make proto`, and update all three clients. The hand-written structs in `internal/auth/dto.go` are legacy (there is a TODO to remove them). Only `LoginResult` there is still used.

Request flow: `cmd/api/main.go` wires everything (config → pgx pool → `db.New(pool)` → service → handler). `internal/api/route/router.go` builds the chi router.

- Per domain package (`internal/auth`, and `internal/vault`, which is still empty stubs): `handler.go` (HTTP, proto decode/encode, maps sentinel errors to status codes and error-code strings) → `service.go` (business logic, returns `Err*` sentinel errors) → sqlc `*db.Queries` as the repository. No separate repository layer exists for auth.
- Input validation lives in `internal/validator` (ozzo-validation, operating on proto dto types). Handlers call it before the service.
- DB access: write SQL in `internal/database/queries/*.sql` with sqlc annotations, then run `sqlc generate`. Never edit `internal/database/db/` by hand. UUID columns map to `github.com/google/uuid.UUID`.
- mDNS is **not done by the Go API**; the Rust `gateway/` does it (`gateway/src/discovery.rs`, crate `mdns-sd`): it announces `_plany._tcp` named `SERVER_NAME` on the LAN interface only (the one holding the default route; `MDNS_INTERFACES` overrides), resolves name conflicts by renaming (`Plany (2)`; avahi renames to `Plany #2`), says goodbye on shutdown and keeps a live list of the other servers (itself hidden) served as protobuf `DiscoveredServers` at `GET /server/discover/` (the browser has no mDNS). The only Go piece is `GET /server/info/` (`internal/server`: `ServerInfo` with name and `registration_enabled`, built once at startup, so changing them needs a restart). mDNS only works on the host network: a bridge container cannot see the LAN, and Docker Desktop (Windows/macOS) runs containers in a VM, so there the gateway must run as a native binary pointing `UPSTREAMS` at published `localhost` ports (not tested). A second avahi on the same machine is fine for the gateway (tested: avahi renamed itself), unlike a second avahi, which loops on hostname conflicts. Verified on a real Raspberry Pi 4 (Debian 13, aarch64, avahi-daemon active) from another machine on the LAN: API replicas + gateway + Postgres worked (register 0.27 s / login 0.21 s with Argon2 on the Pi, gateway 1.6 MB RSS, API ~60 MB RSS each), and each side discovered the other. Multicast over Wi-Fi is lossy (measured 21-48% loss between two Wi-Fi machines on 2.4 GHz at -60 dBm; Wi-Fi power save was off on both), and the library resends its browse query with a delay that doubles up to an hour, so discovery used to take up to about a minute. The gateway therefore restarts the search every `MDNS_REFRESH_SECS` while it knows no other server (4x that once it does): calling `browse` again replaces the receiver, restarts the backoff at 1 s and replays the cache (`discovery::browse_loop`). A/B on the PC<->Pi pair, 4 trials each: discovery took about 1 s in most trials either way; the one bad trial without the restart took 63 s on both sides, the one slow trial with it recovered after 16 s (small sample, and the network was mostly good in that window). The gateway also remembers the servers it has seen (`gateway/src/known.rs`): one that stops being announced (a lost refresh on Wi-Fi, or a goodbye) is not dropped but checked with a plain TCP connection to its last addresses, right away and every `KNOWN_PROBE_SECS`, and stays listed while it answers and is forgotten when it does not; with `KNOWN_SERVERS_FILE` the memory is saved (atomically, as a protobuf `DiscoveredServers`) and loaded at start so a restarted gateway lists the others at once (verified on the Pi with mDNS off on both sides). Security: announcements are untrusted, so the gateway only connects to addresses in its own subnet (`Lan::allows`, from the interface netmask; never itself, loopback, another network or the internet) and ports from 1024, otherwise a device on the LAN could use it as a port scanner and read the result in `/server/discover/`; both tables are capped (256 announced, 64 remembered) and the file is parsed strictly (never panics). On shutdown the port is closed *before* the mDNS goodbye, so the others do not find it still open. Not implemented: a stable server id in the TXT record. Set `GOMEMLIMIT` below the RAM ceiling.
- Config: `internal/config/config.go` parses env vars with a generic `parseEnv` that collects every error before failing. A `nil` fallback means the variable is required. Add new settings there and to `backend/.env.example` and `compose.yml`.

Auth model:
- JWT HS256 (`internal/auth/jwt.go`) with a `user_id` claim and a random `jti`. Access and refresh tokens are the same kind of token with different expiries.
- The access token goes in the response body. The refresh token goes in an `HttpOnly` `refresh_token` cookie.
- Logout revokes tokens by inserting the `jti` into `revoked_tokens`. `ValidateToken` checks that table on every call.
- `middleware.AuthMiddleware` puts the user's UUID into the context under `pkg/context.UserIDKey`. Protected routes go inside the `r.Group(...)` in `router.go`.
- Passwords are hashed with Argon2id (`internal/auth/password.go`). A common-password blocklist is embedded from `internal/auth/data/`. Each Argon2 run keeps ~19 MiB alive, so only 2 run at once per instance (`SetArgonLimits`); the others wait up to 5 s and then get `503 server_busy` + `Retry-After`. Measured before the cap: 16 simultaneous logins = 330 MiB RSS, 64 = 1 GiB; `GOMEMLIMIT` does not help because the memory is live. Login also verifies a dummy hash when the e-mail does not exist, so response time does not reveal which accounts exist. Request bodies of `/auth/login/` and `/auth/register/` are capped at 16 KiB (413 `payload_too_large`).

Router details:
- Routes are registered **with trailing slashes** (`/auth/login/`).
- Login and register each have their own per-IP token-bucket limiter (`internal/middleware/ratelimit.go`, cleaned up by a goroutine in `main.go`). A global `httprate` limit of 100 requests per minute also applies.
- Swagger UI (`/swagger/*`) is mounted only when `DEBUG_MODE=true`. The swag `@Router` annotations in `internal/auth/handler.go` match the router (no `/api` prefix, trailing slashes), and `backend/docs/` has been regenerated to stay in sync.

Known gaps in the current code:
- CORS origins are hardcoded in `router.go`; there is no `ALLOWED_ORIGINS` setting.
- The web build in `./public` is served by `spaHandler` in `router.go` (`GET`/`HEAD /*`, registered after the API routes) with an **allowlist**, no blocklist, in three steps: (1) the path is a real file inside `./public` → serve it; (2) otherwise `isWebRoute(path)` is true → serve `index.html`; (3) anything else (`/api/auth/login/`, `/auth/nope/`, `/random`) → 404. `isWebRoute` currently allows `/`, `/login` and `/notes/:id` (one segment). **The web has no router yet**: `App.svelte` renders `routes/Login.svelte` (implemented, with tests) for every path, and `Dashboard`/`NotePage` in `web/src/routes/` are still empty placeholders. When you add or rename a web page route, update `isWebRoute` and its test (`internal/api/route/static_test.go`) in the same change. The API lives at the server root (no `/api` prefix) and the web calls it with relative paths (`/auth/...`). There is no `VITE_API_URL`, no `web/.env` and no `web/.env.example`; in dev, `web/vite.config.ts` proxies the API prefixes to `localhost:8080`.
- Email validation uses `is.EmailFormat` (syntax only, no DNS lookup).
- The `notes` table exists in the schema, but no queries or handlers use it yet. Blocks live inside `notes.content` (JSONB); there are no `pages`/`blocks` tables. Planned note and vault access goes through a single bulk endpoint, `POST /sync/bulk/`, built on `DocumentSyncRequest`/`DocumentSyncResponse` in the proto (revision-based conflict detection), not per-resource routes. Blocks are a flat list (no `children` yet), tags will be a `TEXT[]` column on `notes`, sharing is planned, and user settings live only on the device, never in Postgres.

## Mobile notes

- State management uses Riverpod. HTTP goes through `http`. Local notes use `sqlite3` (on-disk, not whole-in-RAM like Hive), and secrets use flutter_secure_storage. Client-side vault crypto uses `sodium` (v4 bundles libsodium itself; `sodium_libs` is discontinued). `dio`, `hive_flutter`, `google_fonts`, `lucide_icons`, `cupertino_icons` were removed for RAM/size.
- Much of `lib/core/` is still empty placeholders. Offline-first: notes live in SQLite on the device; `http` + `protobuf` are only for the optional cloud/sync server. Server discovery on the local network (`core/network/discovery`) uses `nsd` (Android/iOS/macOS/Windows) and `multicast_dns` (Linux; `nsd` has no Linux support), picked by `createPlatformDiscovery()`; permissions are in the Android manifest and the iOS/macOS `Info.plist`/entitlements. `features/auth/data/ServerListController` subscribes to the discovery once and exposes a broadcast `Stream<ServerListState>` (available servers, the selected one, whether it is still on the network); the selector button, the **open** menu and the desktop footer follow it with `StreamBuilder` (a plain `PopupMenuButton` builds its items only on open, so the menu is a single custom entry with its own `StreamBuilder`). A server that leaves the network is **not** dropped when it was the selected one: it stays selected, its status dot goes from pulsing green to pulsing red, and the menu shows it under "Desconectados" below "Disponíveis"; it goes back to green when announced again, and choosing another server drops it. Servers that were not selected just disappear. The dot (`PulsingDot`) is about one letter in diameter (`dotDiameterFor`), has a 10 px gap to the name, and stands still when the OS "reduce motion" setting is on (widget tests turn it on, otherwise `pumpAndSettle` never settles). The selector gets only the room left beside the brand (`AuthBrandAndServerRow.selectorWidthFor`; 156 px max on mobile, 260 on desktop). Do not run `dart format` on whole directories: it rewrites the empty placeholder files. The app has no web platform.
- **Folder structure is feature-first.** `mobile/lib/features/{auth,notes,vault}`, each with `data/` and `presentation/{providers,pages,widgets}`. `mobile/lib/core/` holds only `crypto`, `database`, `network`, `storage` and `theme`. Generated protobuf code stays in `lib/shared/protos/`. The current placeholders in `core/` (e.g. `storage/local_cache.dart`) predate this; new code follows the structure above (SQLite goes in `core/database`).
- **Native design system (zero RAM overhead).** No external fonts or icons (no font packages). Strict dark mode, **Editorial Dark Variant**: background `#141412` (deep warm charcoal); surfaces (header, inputs, dropdown menu) `#1E1E1B` with a 1px `#2E2E2A` border; primary text `#EAE6DF`, secondary text `#9A968E`; accent moss green `#4A5D44` (fill) and `#6B8E61` (border / active text); primary button cream `#F5F2EB` with dark text `#141412` and 10px corners. Typography is native: titles and brand (`Plany`, taglines, headings) use the system serif (`fontFamily: 'serif'`); badges and actions (`SELF-HOSTED`, `MOSTRAR`, `LAN`, `OU`) use the system monospace, uppercase with wide letter spacing. Define these once in `core/theme` (`app_colors.dart`, `app_theme.dart`). Do not use the generic Material 3 look: no heavy shadows, `const` constructors wherever possible, and `ListView.builder` for lists.
- The "secure vault" is zero-knowledge by design: content is encrypted on the device, and the server never sees the key. Do not add any server-side decryption or key recovery path.

## Web notes

- **Native design system, same as mobile:** no external fonts or icon libraries (system font stacks `serif`/`monospace`, inline SVG). Strict dark mode, **Editorial Dark Variant**: background `#141412` (deep warm charcoal); surfaces (header, inputs, dropdown menu) `#1E1E1B` with a 1px `#2E2E2A` border; primary text `#EAE6DF`, secondary text `#9A968E`; accent moss green `#4A5D44` (fill) and `#6B8E61` (border / active text); primary button cream `#F5F2EB` with dark text `#141412` and 10px corners. Typography is native: titles and brand (`Plany`, taglines, headings) use the system serif (`fontFamily: 'serif'`); badges and actions (`SELF-HOSTED`, `MOSTRAR`, `LAN`, `OU`) use the system monospace, uppercase with wide letter spacing. Define these once as Tailwind theme tokens in `src/app.css` and use only the tokens in components. No heavy shadows, no generic component-library look. Render long lists incrementally, not whole in the DOM. The tokens are in place in `src/app.css` (`bg`, `surface`, `line`, `fg`, `muted`, `accent`, `accent-line`, `cream`, `on-cream`, `font-serif`, `font-mono`). No component library (shadcn/bits-ui were judged unnecessary for RAM/bundle size): components are small hand-written Svelte files under `src/lib/components/`. The login screen is adaptive via `MediaQuery('min-width: 840px')` (header + form below, side panel + form above), mirroring the mobile `AuthPage`.
- **Other servers on the web (navigation, not cross-origin calls).** The page is always the embedded server's; the web calls only relative paths. The list of other servers comes from `GET /server/discover/` (the gateway; 404 without a gateway = no others), polled by `ServerDirectory` in `src/lib/stores/servers.svelte.ts` (5 s doubling to 60 s while empty, 15 s once there are others, paused on a hidden tab; a server missing from an answer stays 15 s; cap 64; names over 64 chars, bad ports and non-LAN-style IPv4 dropped; response over 64 KiB discarded). Choosing another server does **not** change local state: `selection.open` probes it (`fetch` with `mode: 'no-cors'` to `/server/info/`, 3 s; skipped when the page is https and the target http, since the browser blocks that fetch but not the navigation) and then `window.location.assign`s to it, so its own web/API/cookies stay same-origin (no CORS, `SameSite` or mixed-content problems, and credentials only go to the page that server itself serves). While `connecting` the form fades and is `inert`; if the probe fails it shows a toast and goes back. Servers the user types in ("+ Adicionar servidor...", for servers outside the LAN) are not implemented yet; they would be stored in `localStorage` and open the same way. A loading skeleton (plain HTML/CSS, no JS, same 840 px breakpoint) lives inside `#app` in `web/index.html` and `main.ts` clears it before mounting; it is what the user sees while the other server's page loads (cross-origin navigations cannot use View Transitions).

## Conventions

- **Tests are mandatory.** Every component or service created (Go, Rust, Web or Flutter) must ship with automated tests written together with the implementation, not afterwards.
- **Stress the system (concurrency and robustness tests).** When writing tests, also write concurrency and robustness tests wherever they apply, and try to break the system by every means: heavy load (floods of requests or connections, many source addresses, huge bodies, slow or never-finished requests, resource exhaustion), malformed or unexpected input, spoofed headers, injection. If something breaks, fix the code; do not weaken the test.
- **Break it like a confused person (careless-use tests).** Also write tests as if you were an elderly person or just a very random one, and try to break it that way too: wrong or repeated taps and clicks, doing things in an odd order, leaving halfway, empty, huge or strange text, stray spaces, a screen that is too small or too crowded, a bad connection. If something breaks, fix it.
- Log messages, comments, and some error strings mix Portuguese and English. Match the language of the surrounding code.
- **Go tests that need the real database are named `TestDB_*`** (e.g. `TestDB_Service_Register_DuplicateEmail`, `TestDB_Pool_...`). Anything that loads `backend/.env` (`godotenv.Load`) or opens a connection (`database.NewConnection`, `pgxpool.*`), directly or through a helper, must carry the prefix. Why: the CI runner (Raspberry Pi) has no Postgres and no `.env`, so `.forgejo/workflows/backend.yml` skips exactly `^TestDB_` (`go test ./... -skip '^TestDB_'`); a database test with another name passes locally and breaks the pipeline. Before this convention the workflow kept a list of name prefixes that people forgot to update. `internal/testnaming` enforces it: it parses every `_test.go`, follows helper calls inside a directory, and fails with the names to rename. `go test ./... -run TestDB_` runs only the database tests, `-skip TestDB_` only the ones that run without it (what the CI runs). `config.Load` alone does not count (the config tests set variables with `t.Setenv`).
- Go tests use external test packages (`package auth_test`) and compare protobuf messages with `go-cmp` + `protocmp`.
