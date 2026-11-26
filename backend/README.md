# Pindrel — Backend

API em Go responsável por autenticação, arquivos enviados e, em desenvolvimento, sincronização de notas na nuvem. Serve a web (que vem junto na imagem Docker e no instalador do Windows) e, opcionalmente, o app mobile/desktop. O app mobile é autossuficiente e usa a API apenas para nuvem e sincronização; a web guarda as notas no navegador e usa a API para login e sincronização.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Pindrel deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

No backend: `GOMEMLIMIT` fica abaixo do teto (a imagem usa `64MiB`), o pool do pgx e o `max_connections` do Postgres ficam pequenos, só 2 hashes Argon2id rodam ao mesmo tempo por instância e as tabelas dos limitadores por IP têm teto de 16 384 entradas.

## Stack

- **Go** — linguagem e runtime
- **PostgreSQL** — banco de dados, via [pgx](https://github.com/jackc/pgx); queries geradas com [sqlc](https://sqlc.dev); migrações com [golang-migrate](https://github.com/golang-migrate/migrate), aplicadas pela própria API ao iniciar
- **chi** — roteador HTTP
- **Protobuf** — formato de request/response (`application/x-protobuf`), definido em `shared/protos/`
- **JWT** — autenticação (access token no corpo, refresh token em cookie HttpOnly)

A descoberta na rede (mDNS) não é feita aqui: é do gateway em Rust (`gateway/`).

## Stateless

A API é **explicitamente stateless**, para rodar atrás de um load balancer com várias instâncias idênticas:

- nada de sessão, cache ou contador em memória do processo; o estado fica no PostgreSQL ou no JWT;
- qualquer instância atende qualquer requisição (refresh token em cookie + tabela `revoked_tokens` no banco, sem afinidade de sessão);
- o `JWT_SECRET` precisa ser o mesmo em todas as instâncias.

Os limitadores de requisições (por IP em `/auth/login/` e `/auth/register/`, o global de 100 por minuto e os de `/files/`) ficam na memória de cada instância e existem para quem roda **uma** instância sem gateway. Com o gateway na frente, `IN_APP_RATE_LIMIT=false` e quem limita é ele.

## Estrutura

```text
backend/
├── cmd/api/main.go            # ponto de entrada e opções de linha de comando
├── installer/windows/         # instalador (Inno Setup), script de início/parada e arquivos do portátil
├── internal/
│   ├── api/                   # WriteResponse/WriteError, DTOs gerados do proto, router
│   ├── auth/                  # registro, login, logout, refresh, me
│   ├── files/                 # arquivos enviados em pedaços, entregues por endereço assinado
│   ├── server/                # GET /server/info/
│   ├── clientip/              # quem é o cliente de uma requisição (para os limitadores)
│   ├── middleware/            # autenticação, limitadores e cabeçalhos de segurança
│   ├── validator/             # validação dos DTOs
│   ├── config/                # variáveis de ambiente e arquivo de configuração
│   ├── database/              # conexão, migrações, queries sqlc e código gerado
│   └── testnaming/            # garante que testes com banco se chamam TestDB_*
├── docs/                      # Swagger gerado (swag)
├── sqlc.yaml
└── go.mod
```

Cada domínio contém `handler.go` (HTTP), `service.go` (regra de negócio) e usa o `*db.Queries` gerado pelo sqlc como repositório. Testes ficam ao lado do arquivo testado (`_test.go`).

## Rodando localmente

Pré-requisitos: Go e um PostgreSQL acessível (por exemplo `docker compose up postgres` na raiz).

```bash
cp .env.example .env     # e edite
go run ./cmd/api         # aplica as migrações e sobe na PORT do .env
```

Opções do binário:

```text
--config <arquivo>   lê as configurações de um arquivo CHAVE=valor (também PINDREL_CONFIG); o ambiente real tem prioridade
--check              valida as configurações e sai (0 = tudo certo)
--check-db           valida, tenta conectar ao banco uma vez e sai (0 = conectou)
--new-secret         imprime um segredo aleatório novo (para JWT_SECRET ou senha do banco) e sai
```

Sem `--config`, um `.env` na pasta atual é lido se existir (desenvolvimento). O arquivo do `--config` segue as mesmas regras do gateway: `#` comenta, `export ` é aceito, um par de aspas em volta do valor é retirado e **nada é expandido** (`$` é só um caractere).

## Windows

Dois downloads em cada release, montados pelo GitHub Actions (`.github/workflows/release-desktop.yml`, job `server-windows`):

- **Instalador** (`pindrel-server_<versão>_windows_amd64_installer.exe`, Inno Setup, `installer/windows/pindrel-server.iss`): pergunta o nome e a porta do servidor, se usa o **PostgreSQL que vem junto** (recomendado) ou **um que já existe** (testa a conexão antes de seguir), se guarda os arquivos enviados, se aceita contas novas e se o Pindrel Gateway fica na frente no mesmo computador (aí o servidor escuta só em `127.0.0.1:9000`). Também inicia com o Windows, libera o Firewall (instalação para todos) e tem desinstalador, que pergunta antes de apagar os dados.
- **Portátil** (`pindrel-server_<versão>_windows_amd64_portable.zip`): `iniciar.cmd` cria a pasta `dados` na primeira vez e roda tudo na janela; `parar.cmd` para o banco se a janela foi fechada.

Os dois usam o mesmo `installer/windows/pindrel-server.ps1` (`-Action start|run|stop|init -Data <pasta>`): ele cria o banco na primeira vez (`initdb`, só em `127.0.0.1`, senha aleatória, o mesmo orçamento de memória do `compose.yml`), inicia o PostgreSQL com `pg_ctl` (que tira os direitos de administrador, que o PostgreSQL recusa) e depois o servidor, escondido, tentando de novo se ele cair logo ao subir. Os dados ficam em `%LOCALAPPDATA%\Pindrel Server` (ou `%ProgramData%\Pindrel Server` na instalação para todos): `server.env`, `pgdata\`, `files\`, `server.log` e `postgres.log`. Backup: pare o servidor e copie essa pasta.

O PostgreSQL embutido é o zip oficial da EnterpriseDB, com versão e checksum fixados no workflow. Uma troca de versão **principal** (18 → 19) exige `pg_upgrade` ou `pg_dump`/restauração dos bancos já criados: o script se recusa a abrir um banco de outra versão principal e explica o que fazer.

O CI do Windows roda os testes sem banco no próprio Windows e liga a pasta portátil de verdade (cria o banco, sobe o servidor, faz um cadastro pela API e para tudo) antes de empacotar. `installer/windows/installer_test.go` verifica em qualquer sistema a codificação dos arquivos (BOM, CRLF) e que toda configuração escrita pelo instalador e pelo portátil é conhecida e aceita pelo servidor.

## Variáveis de ambiente

Obrigatórias, a menos que haja valor padrão:

| Variável | Descrição | Padrão |
| --- | --- | --- |
| `PORT` | Porta em que a API escuta (1024–65535) | — |
| `LISTEN_HOST` | Endereço em que escuta (`127.0.0.1` = só esta máquina) | todas as interfaces |
| `SERVER_NAME` | Nome mostrado aos clientes | `Pindrel` |
| `DB_HOST` · `DB_PORT` | Endereço do PostgreSQL | — |
| `DB_USER` · `DB_PASSWORD` · `DB_NAME` | Credenciais e nome do banco | — |
| `SSL_MODE` | `disable`, `allow`, `prefer`, `require`, `verify-ca` ou `verify-full` | — |
| `DB_MAX_CONNS` | Conexões do pool por instância (1–100) | `4` |
| `JWT_SECRET` | Segredo que assina os tokens (longo e aleatório: `--new-secret`) | — |
| `JWT_ACCESS_EXPIRY` · `JWT_REFRESH_EXPIRY` | Validade dos tokens | — (ex.: `15m`, `720h`) |
| `REGISTRATION_ENABLED` | Permite ou bloqueia novos registros | `true` |
| `IN_APP_RATE_LIMIT` | Limitadores na memória da instância (desligue atrás do gateway) | `true` |
| `TRUSTED_PROXIES` · `CLIENT_IP_HEADER` | Proxies cujo cabeçalho de IP é aceito, e qual cabeçalho | vazio · `X-Forwarded-For` |
| `WEB_DIR` | Pasta da web servida | `./public` |
| `ALLOWED_ORIGINS` | Outros sites que podem chamar a API com o cookie (CORS) | nenhum |
| `FILES_DIR` | Pasta dos arquivos enviados (vazio desliga) | vazio |
| `FILE_*`, `FILES_MIN_FREE_BYTES` | Limites dos arquivos (ver `.env.example`) | |
| `DEBUG_MODE` | Habilita `/swagger/*` (com `-tags swagger`) | `false` |

> **Importante:** `JWT_SECRET` deve ser um valor longo e aleatório em produção. Nunca use o valor de exemplo do `.env.example`.

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados, escritos na mesma entrega e não depois.

Os testes que usam o banco se chamam `TestDB_*`, leem o `.env` do backend, usam um PostgreSQL real com as migrações aplicadas e criam/removem usuários de teste. Os outros rodam sem nada.

```bash
go test -p 1 ./...               # tudo
go test ./... -skip '^TestDB_'   # só os que não precisam de banco (o que a CI do Pi roda)
```

## Código gerado

```bash
sqlc generate                  # internal/database/db
swag init -g cmd/api/main.go   # docs/
make proto                     # (na raiz) DTOs do Protobuf
```

## Rotas

Rotas com nome de coleção terminam em barra; as que terminam num id, não.

```text
GET    /server/info/

POST   /auth/register/
POST   /auth/login/
POST   /auth/logout/
POST   /auth/refresh/
GET    /auth/me/

GET    /files/?cursor=              # com FILES_DIR
POST   /files/uploads/
GET    /files/uploads/{id}
PUT    /files/uploads/{id}/{n}
POST   /files/uploads/{id}/finish
DELETE /files/uploads/{id}
POST   /files/{id}/link
GET    /files/{id}?exp=&sig=        # também HEAD; endereço assinado, sem sessão
PUT    /files/{id}/orphan
DELETE /files/{id}/orphan
DELETE /files/{id}

GET    /*                           # arquivos de WEB_DIR; rotas da web recebem index.html; o resto é 404
GET    /swagger/*                   # apenas com DEBUG_MODE=true e -tags swagger
```

Planejado: `POST /sync/bulk/` — operação em lote para sincronizar notas e cofre.

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
