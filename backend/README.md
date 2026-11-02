# Pindrel — Backend

API em Go responsável por autenticação e, em desenvolvimento, sincronização de notas na nuvem. Serve a web (que vem embutida na imagem) e, opcionalmente, o app mobile/desktop. O app mobile é autossuficiente e usa a API apenas para nuvem e sincronização; a web guarda as notas no navegador e usa a API para login e sincronização.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Pindrel deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

No backend: `GOMEMLIMIT` deve ser definido abaixo do teto (por exemplo `GOMEMLIMIT=200MiB`), o pool do pgx e o `max_connections` do Postgres ficam pequenos, e o hash Argon2id de senha consome memória por login simultâneo.

## Stack

- **Go** — linguagem e runtime
- **PostgreSQL** — banco de dados, via [pgx](https://github.com/jackc/pgx) e queries geradas com [sqlc](https://sqlc.dev)
- **chi** — roteador HTTP
- **Protobuf** — formato de request/response (`application/x-protobuf`), definido em `shared/protos/`
- **mDNS** (planejado) — [`github.com/libp2p/zeroconf/v2`](https://github.com/libp2p/zeroconf), mantida, anuncia e procura serviços, e só depende de `miekg/dns` e `x/net`. Será adicionada ao `go.mod` quando for usada
- **JWT** — autenticação (access token no corpo, refresh token em cookie HttpOnly)

## Stateless

A API deve ser **explicitamente stateless**, para rodar atrás de um load balancer com várias instâncias idênticas. Regras:

- nada de sessão, cache ou contador em memória do processo; o estado fica no PostgreSQL ou no JWT;
- qualquer instância atende qualquer requisição (refresh token em cookie + tabela `revoked_tokens` no banco, sem afinidade de sessão);
- o `JWT_SECRET` precisa ser o mesmo em todas as instâncias.

> **Lacuna atual:** os rate limiters (por IP em `/auth/login/` e `/auth/register/`, e o limite global do `httprate`) guardam contadores na memória de cada instância. Com várias instâncias o limite efetivo se multiplica; é preciso movê-los para o load balancer ou para um armazenamento compartilhado.

## Descoberta na rede (planejado)

A instância embutida na web usa mDNS para encontrar outros servidores Pindrel na rede e repassa a lista à web (navegadores não fazem mDNS). O padrão da web continua sendo sempre o servidor embutido. O serviço anunciado (`_pindrel._tcp`) é o que está na linha de frente: o load balancer, quando houver, e não cada instância da API.

## Estrutura

```text
backend/
├── cmd/api/main.go            # ponto de entrada
├── internal/
│   ├── api/                   # WriteResponse/WriteError, DTOs gerados do proto, router
│   ├── auth/                  # registro, login, logout, refresh, me
│   ├── vault/                 # cofre (ainda vazio)
│   ├── middleware/            # autenticação e rate limit
│   ├── validator/             # validação dos DTOs
│   ├── config/                # leitura e validação das variáveis de ambiente
│   └── database/              # conexão, migrações, queries sqlc e código gerado
├── docs/                      # Swagger gerado (swag)
├── sqlc.yaml
└── go.mod
```

Cada domínio contém `handler.go` (HTTP), `service.go` (regra de negócio) e usa o `*db.Queries` gerado pelo sqlc como repositório. Testes ficam ao lado do arquivo testado (`_test.go`).

## Rodando localmente

Pré-requisitos: Go e um PostgreSQL acessível (por exemplo `docker compose up postgres` na raiz).

```bash
cp .env.example .env
# edite o .env com suas configurações
# aplique as migrações de internal/database/migrations no banco
go mod download
go run ./cmd/api
```

## Variáveis de ambiente

Obrigatórias, a menos que haja valor padrão:

| Variável | Descrição | Padrão |
| --- | --- | --- |
| `PORT` | Porta em que a API escuta (1024–65535) | — |
| `DB_HOST` · `DB_PORT` | Endereço do PostgreSQL | — |
| `DB_USER` · `DB_PASSWORD` · `DB_NAME` | Credenciais e nome do banco | — |
| `SSL_MODE` | `disable`, `allow`, `prefer`, `require`, `verify-ca` ou `verify-full` | — |
| `JWT_SECRET` | Segredo usado para assinar os tokens JWT | — |
| `JWT_ACCESS_EXPIRY` | Validade do access token | — (ex.: `15m`) |
| `JWT_REFRESH_EXPIRY` | Validade do refresh token | — (ex.: `720h`) |
| `REGISTRATION_ENABLED` | Permite ou bloqueia novos registros | `true` |
| `DEBUG_MODE` | Habilita `/swagger/*` | `false` |

> **Importante:** `JWT_SECRET` deve ser um valor longo e aleatório em produção. Nunca use o valor de exemplo do `.env.example`.

As origens permitidas de CORS ainda estão fixas em `internal/api/route/router.go`.

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados, escritos na mesma entrega e não depois. Vale para Go, Web e Flutter.

Os testes são de integração: usam o `.env` do backend e um PostgreSQL real, e criam/removem usuários de teste.

```bash
go test ./...
```

## Código gerado

```bash
sqlc generate                  # internal/database/db
swag init -g cmd/api/main.go   # docs/
make proto                     # (na raiz) DTOs do Protobuf
```

## Rotas

Todas com barra final.

```text
GET    /*                  # arquivos de ./public; fallback para index.html (SPA)

POST   /auth/register/
POST   /auth/login/
POST   /auth/logout/
POST   /auth/refresh/
GET    /auth/me/

GET    /swagger/*          # apenas com DEBUG_MODE=true
```

Planejado: `POST /sync/bulk/` — operação em lote para sincronizar notas e cofre.

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
