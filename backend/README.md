# Plany — Backend

API em Go responsável por autenticação, persistência de notas e comunicação em tempo real. Serve tanto o frontend web quanto o app mobile/desktop, sem depender de nenhum dos dois.

## Stack

- **Go** — linguagem e runtime
- **MongoDB** — banco de dados (via [mongo-go-driver](https://github.com/mongodb/mongo-go-driver))
- **WebSocket** — comunicação em tempo real
- **JWT** — autenticação (access + refresh token)

## Estrutura

```text
backend/
├── cmd/
│   └── api/
│       └── main.go          # ponto de entrada
├── internal/
│   ├── auth/                # registro, login, logout, refresh
│   ├── notes/                # CRUD de notas/blocos
│   ├── middleware/           # auth, CORS
│   └── database/             # conexão com o Mongo
├── go.mod
└── go.sum
```

Cada domínio (`auth`, `notes`) contém seu próprio `handler.go` (rotas HTTP), `service.go` (regra de negócio) e `repository.go` (acesso ao banco). Testes ficam ao lado do arquivo que testam, com sufixo `_test.go`.

## Rodando localmente

Pré-requisitos: Go instalado, MongoDB acessível (local ou remoto).

```bash
cp .env.example .env
# edite o .env com suas configurações
go mod download
go run ./cmd/api
```

## Variáveis de ambiente

| Variável | Descrição | Padrão |
| --- | --- | --- |
| `PORT` | Porta em que a API escuta | `8080` |
| `POSTGRES_URI` | URI de conexão com o MongoDB | `mongodb://mongo:27017` |
| `POSTGRES_DB_NAME` | Nome do banco de dados | `plany` |
| `JWT_SECRET` | Segredo usado para assinar os tokens JWT | — |
| `JWT_ACCESS_EXPIRY` | Validade do access token | `15m` |
| `JWT_REFRESH_EXPIRY` | Validade do refresh token | `720h` |
| `REGISTRATION_ENABLED` | Permite ou bloqueia novos registros | `true` |
| `ALLOWED_ORIGINS` | Origens permitidas via CORS, separadas por vírgula | `http://localhost:3000` |

> **Importante:** `JWT_SECRET` deve ser um valor longo e aleatório em produção. Nunca use o valor de exemplo do `.env.example`.

## Testes

```bash
go test ./...
```

## Rotas principais

```text
POST   /auth/register
POST   /auth/login
POST   /auth/logout
POST   /auth/refresh
GET    /auth/me

GET    /notes
POST   /notes
GET    /notes/:id
PUT    /notes/:id
DELETE /notes/:id

GET    /health
```

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
