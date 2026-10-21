# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project priorities

1. **Absolute minimum RAM use.** Plany must run on weak devices (an old Raspberry Pi, an old phone). Target: **hard ceiling of 512 MB RAM**, **recommended 256 MB**, counting everything needed to run, database included. The limit applies **per instance**; behind a load balancer each API instance follows the same individual ceiling. In practice: prefer small dependencies, don't hold whole datasets in memory, cap connections and memory spikes (e.g. key derivation). Judge every new dependency against this.
2. **Cost split between client and server.** Neither side should absorb all the overhead for the other. Where overhead is unavoidable (security, cryptography) it takes priority, but balanced between the parties.

## Project

Plany is a self-hosted, Notion-style notes workspace (AGPL-3.0). Three clients-of-one-API live in this monorepo:

- `backend/` — Go API (Go module name is `plany`, so imports look like `plany/internal/auth`)
- `web/` — Svelte 5 + Vite + Tailwind SPA (Yarn Berry with PnP SDKs in `web/.yarn`)
- `mobile/` — Flutter app (mobile + desktop), Flutter version pinned via FVM (`mobile/.fvmrc`)
- `shared/protos/` — Protobuf schema shared by all three

Only the auth routes are implemented so far. Notes, vault and bulk sync are planned.

**Client/server roles:** the Go API exists for authentication, cloud storage and sync. `mobile/` is fully self-sufficient (local storage, works without any server; the API is optional). `web/` ships embedded in the API image and depends on it for login, but is semi-self-sufficient: notes are kept in the browser's IndexedDB (`idb`). Both login screens will have a top tab to add another server: web **always defaults to the embedded server** (other servers found via mDNS are extra options; browsers cannot do mDNS, so the embedded backend does the discovery and hands the list to the web), mobile picks a random server found on the current network. mDNS (`_plany._tcp`) advertises the front-facing service, i.e. the load balancer when there is one, never each API instance. All planned, not implemented.

**The API must be explicitly stateless** so it can run behind a load balancer: no session/cache/counter state in process memory; state lives in Postgres or the JWT; `JWT_SECRET` is shared across instances. Current violation: the login/register IP rate limiters (`main.go`) and the global `httprate` limit keep counters in memory per instance.

## Commands

### Backend (run from `backend/`)

```bash
cp .env.example .env            # config.Load() fails if any required var is missing
go run ./cmd/api                # needs a reachable Postgres
go test ./...                   # integration tests: need Postgres + backend/.env
go test ./internal/auth -run TestService_Register_DuplicateEmail -v   # run a single test
sqlc generate                   # regenerate internal/database/db from queries/ + migrations/
swag init -g cmd/api/main.go    # regenerate docs/ (Swagger) from handler annotations
```

Tests are not unit tests with mocks. `setup_test.go` files load `../../.env` (i.e. `backend/.env`) and connect to the real database. They create dummy users and delete them in `t.Cleanup`. Start Postgres first, for example with `docker compose up postgres`, which exposes port 5432.

Migrations in `internal/database/migrations` use the golang-migrate naming scheme (`NNNNNN_name.up/down.sql`). Nothing in the codebase runs them automatically, so apply them to the database yourself before running the server or the tests.

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

### Protobuf (run from repo root)

```bash
make proto       # proto-go + proto-dart + proto-ts
make proto-go    # -> backend/internal/api/dto/*.pb.go (via go_package option)
make proto-ts    # -> web/src/types/shared/protos/*.ts (ts-proto)
```

`make proto-dart` writes exactly to `mobile/lib/shared/protos/` (it passes `-Ishared/protos` so the output is flat). It needs `protoc-gen-dart` on `PATH` (`~/.pub-cache/bin`).

### Docker

`docker compose up --build` builds one image (the `Dockerfile` builds both `web/` and the Go server) and runs it with `postgres:18-alpine`. The final image is a stripped static Go binary on Alpine, run as non-root with `GOMEMLIMIT=100MiB` and a `wget` healthcheck on `/`. The container always listens on 8080; compose's `PORT` only picks the host port. Compose reads `backend/.env` when present (optional) and also sets defaults inline. It enforces the RAM budget: `mem_limit` 128m for `plany` + 128m for `postgres` (= the recommended 256 MB), `GOMEMLIMIT=100MiB`, small Postgres buffers, and Postgres published on loopback only.

## Backend architecture

**Wire format is Protobuf, not JSON.** Request bodies are `proto.Unmarshal`ed into types from `internal/api/dto` (generated from `shared/protos/*.proto`). Responses go out as `application/x-protobuf` through `api.WriteResponse(w, status, msg)` and `api.WriteError(w, status, code, message)` in `internal/api/response_http.go`. To add or change a payload, edit the `.proto` file, run `make proto`, and update all three clients. The hand-written structs in `internal/auth/dto.go` are legacy (there is a TODO to remove them). Only `LoginResult` there is still used.

Request flow: `cmd/api/main.go` wires everything (config → pgx pool → `db.New(pool)` → service → handler). `internal/api/route/router.go` builds the chi router.

- Per domain package (`internal/auth`, and `internal/vault`, which is still empty stubs): `handler.go` (HTTP, proto decode/encode, maps sentinel errors to status codes and error-code strings) → `service.go` (business logic, returns `Err*` sentinel errors) → sqlc `*db.Queries` as the repository. No separate repository layer exists for auth.
- Input validation lives in `internal/validator` (ozzo-validation, operating on proto dto types). Handlers call it before the service.
- DB access: write SQL in `internal/database/queries/*.sql` with sqlc annotations, then run `sqlc generate`. Never edit `internal/database/db/` by hand. UUID columns map to `github.com/google/uuid.UUID`.
- Chosen (not yet added) Go mDNS library: `github.com/libp2p/zeroconf/v2`. Set `GOMEMLIMIT` below the RAM ceiling.
- Config: `internal/config/config.go` parses env vars with a generic `parseEnv` that collects every error before failing. A `nil` fallback means the variable is required. Add new settings there and to `backend/.env.example` and `compose.yml`.

Auth model:
- JWT HS256 (`internal/auth/jwt.go`) with a `user_id` claim and a random `jti`. Access and refresh tokens are the same kind of token with different expiries.
- The access token goes in the response body. The refresh token goes in an `HttpOnly` `refresh_token` cookie.
- Logout revokes tokens by inserting the `jti` into `revoked_tokens`. `ValidateToken` checks that table on every call.
- `middleware.AuthMiddleware` puts the user's UUID into the context under `pkg/context.UserIDKey`. Protected routes go inside the `r.Group(...)` in `router.go`.
- Passwords are hashed with Argon2id (`internal/auth/password.go`). A common-password blocklist is embedded from `internal/auth/data/`.

Router details:
- Routes are registered **with trailing slashes** (`/auth/login/`).
- Login and register each have their own per-IP token-bucket limiter (`internal/middleware/ratelimit.go`, cleaned up by a goroutine in `main.go`). A global `httprate` limit of 100 requests per minute also applies.
- Swagger UI (`/swagger/*`) is mounted only when `DEBUG_MODE=true`. The swag `@Router` annotations in `internal/auth/handler.go` match the router (no `/api` prefix, trailing slashes), and `backend/docs/` has been regenerated to stay in sync.

Known gaps in the current code:
- CORS origins are hardcoded in `router.go`; there is no `ALLOWED_ORIGINS` setting.
- The web build in `./public` is served by `spaHandler` in `router.go` (`GET`/`HEAD /*`, registered after the API routes) with an **allowlist**, no blocklist, in three steps: (1) the path is a real file inside `./public` → serve it; (2) otherwise `isWebRoute(path)` is true → serve `index.html`; (3) anything else (`/api/auth/login/`, `/auth/nope/`, `/random`) → 404. `isWebRoute` currently allows `/`, `/login` and `/notes/:id` (one segment). **The web has no router yet**; those come from the placeholder screens in `web/src/routes/` (`Dashboard`, `Login`, `NotePage`). When you add or rename a web page route, update `isWebRoute` and its test (`internal/api/route/static_test.go`) in the same change. The API lives at the server root (no `/api` prefix) and the web calls it with relative paths (`/auth/...`). There is no `VITE_API_URL`, no `web/.env` and no `web/.env.example`; in dev, `web/vite.config.ts` proxies the API prefixes to `localhost:8080`.
- Email validation uses `is.EmailFormat` (syntax only, no DNS lookup).
- The `notes` table exists in the schema, but no queries or handlers use it yet. Blocks live inside `notes.content` (JSONB); there are no `pages`/`blocks` tables. Planned note and vault access goes through a single bulk endpoint, `POST /sync/bulk/`, built on `DocumentSyncRequest`/`DocumentSyncResponse` in the proto (revision-based conflict detection), not per-resource routes. Blocks are a flat list (no `children` yet), tags will be a `TEXT[]` column on `notes`, sharing is planned, and user settings live only on the device, never in Postgres.

## Mobile notes

- State management uses Riverpod. HTTP goes through `http`. Local notes use `sqlite3` (on-disk, not whole-in-RAM like Hive), and secrets use flutter_secure_storage. Client-side vault crypto uses `sodium` (v4 bundles libsodium itself; `sodium_libs` is discontinued). `dio`, `hive_flutter`, `google_fonts`, `lucide_icons`, `cupertino_icons` were removed for RAM/size.
- Much of `lib/core/` is still empty placeholders. Offline-first: notes live in SQLite on the device; `http` + `protobuf` are only for the optional cloud/sync server. Server discovery on the local network uses `nsd` (Android/iOS/macOS/Windows) and `multicast_dns` (Linux; `nsd` has no Linux support) — installed, not yet used. The app has no web platform.
- **Folder structure is feature-first.** `mobile/lib/features/{auth,notes,vault}`, each with `data/` and `presentation/{providers,pages,widgets}`. `mobile/lib/core/` holds only `crypto`, `database`, `network`, `storage` and `theme`. Generated protobuf code stays in `lib/shared/protos/`. The current placeholders in `core/` (e.g. `storage/local_cache.dart`) predate this; new code follows the structure above (SQLite goes in `core/database`).
- **Native design system (zero RAM overhead).** No external fonts or icons (no font packages). Strict dark mode, **Editorial Dark Variant**: background `#141412` (deep warm charcoal); surfaces (header, inputs, dropdown menu) `#1E1E1B` with a 1px `#2E2E2A` border; primary text `#EAE6DF`, secondary text `#9A968E`; accent moss green `#4A5D44` (fill) and `#6B8E61` (border / active text); primary button cream `#F5F2EB` with dark text `#141412` and 10px corners. Typography is native: titles and brand (`Plany`, taglines, headings) use the system serif (`fontFamily: 'serif'`); badges and actions (`SELF-HOSTED`, `MOSTRAR`, `LAN`, `OU`) use the system monospace, uppercase with wide letter spacing. Define these once in `core/theme` (`app_colors.dart`, `app_theme.dart`). Do not use the generic Material 3 look: no heavy shadows, `const` constructors wherever possible, and `ListView.builder` for lists.
- The "secure vault" is zero-knowledge by design: content is encrypted on the device, and the server never sees the key. Do not add any server-side decryption or key recovery path.

## Web notes

- **Native design system, same as mobile:** no external fonts or icon libraries (system font stacks `serif`/`monospace`, inline SVG). Strict dark mode, **Editorial Dark Variant**: background `#141412` (deep warm charcoal); surfaces (header, inputs, dropdown menu) `#1E1E1B` with a 1px `#2E2E2A` border; primary text `#EAE6DF`, secondary text `#9A968E`; accent moss green `#4A5D44` (fill) and `#6B8E61` (border / active text); primary button cream `#F5F2EB` with dark text `#141412` and 10px corners. Typography is native: titles and brand (`Plany`, taglines, headings) use the system serif (`fontFamily: 'serif'`); badges and actions (`SELF-HOSTED`, `MOSTRAR`, `LAN`, `OU`) use the system monospace, uppercase with wide letter spacing. Define these once as Tailwind theme tokens in `src/app.css` and use only the tokens in components. No heavy shadows, no generic component-library look. Render long lists incrementally, not whole in the DOM. (The web has not been migrated to this palette yet.)

## Conventions

- **Tests are mandatory.** Every component or service created (Go, Web or Flutter) must ship with automated tests written together with the implementation, not afterwards.
- Log messages, comments, and some error strings mix Portuguese and English. Match the language of the surrounding code.
- Go tests use external test packages (`package auth_test`) and compare protobuf messages with `go-cmp` + `protocmp`.
