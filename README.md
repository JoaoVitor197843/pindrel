# Plany

Plany é um workspace de notas e organização pessoal no estilo Notion, pensado para ser **self-hosted**: você roda no seu próprio servidor (homelab, VPS, ou máquina local) e mantém total controle sobre seus dados.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Plany deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

## Visão geral

O projeto é dividido em quatro partes independentes:

- **[`backend/`](./backend)** — API em Go, responsável por autenticação e (em desenvolvimento) sincronização de notas na nuvem.
- **[`gateway/`](./gateway)** — a porta de entrada de uma instalação, em Rust: balanceia as réplicas da API, limita requisições por IP, anuncia o servidor na rede (mDNS) e lista os outros servidores da rede. Um binário estático de ~1,4 MB que usa poucos MB de RAM. Veja o [README do gateway](./gateway/README.md).
- **[`web/`](./web)** — interface web em Svelte, embutida na imagem do backend. Depende da API, mas é semi-autossuficiente: guarda as notas no próprio navegador (IndexedDB).
- **[`mobile/`](./mobile)** — aplicativo mobile (e desktop) em Flutter, **autossuficiente**: funciona sem nenhuma API. O servidor só entra para nuvem e sincronização, e é opcional.

O contrato de mensagens entre as partes fica em [`shared/protos/`](./shared/protos) (Protobuf).

### Servidores

Na tela de login, os dois clientes têm uma aba superior para escolher (e, no futuro, adicionar) um servidor:

- **Mobile:** descobre sozinho, por mDNS (`_plany._tcp`), os servidores da rede atual (`nsd` no Android, iOS, macOS e Windows; `multicast_dns` no Linux) e sorteia um deles. A lista acompanha a rede **ao vivo**, inclusive com o menu aberto. Se o servidor escolhido sai da rede, ele **não some**: continua escolhido, a bolinha ao lado do nome passa de verde pulsante para vermelha pulsante, e ele aparece em "Desconectados" abaixo dos "Disponíveis". Quando volta, a bolinha volta a ser verde. "Conectado" aqui quer dizer que o servidor está sendo anunciado na rede.
- **Web:** o servidor padrão **é sempre o pré-embutido** (o mesmo que serve a página). Como navegadores não fazem mDNS, a lista dos outros servidores da rede vem do **gateway**, em `GET /server/discover/`. A aba da web ainda não foi implementada.

**mDNS e gateway:** quem anuncia o servidor na rede é o **gateway**, e não cada instância da API. Ele anuncia só na interface da rede local, resolve conflito de nomes (`Plany`, `Plany (2)`...), avisa quando sai e, como o Wi-Fi perde muitos pacotes multicast, refaz a busca de tempos em tempos e **lembra** dos servidores já vistos, testando o endereço deles quando o anúncio some. Sem o gateway (um `docker compose up` simples) não há anúncio na rede. O mDNS só funciona com o gateway na **rede do host**: um container em rede bridge não enxerga a LAN.

### API stateless

A API deve ser **explicitamente stateless**, para poder rodar atrás de um load balancer com várias instâncias. Nenhum dado de sessão ou de requisição pode ficar na memória do processo: o estado vive no PostgreSQL (por exemplo, tokens revogados) ou no próprio token (JWT). Os limites de requisição por IP da própria API ficam na memória de cada instância; por isso, atrás do gateway (que passa a limitar na entrada), eles são desligados com `IN_APP_RATE_LIMIT=false`.

> **Estado atual:** a autenticação está ativa no servidor, o gateway (balanceamento, limites e mDNS) e a descoberta de servidores no app mobile estão implementados. Notas, cofre, sincronização em lote e as abas de servidor do login estão planejados.

## Stack

| Camada | Tecnologia |
| --- | --- |
| Backend | Go, PostgreSQL (pgx + sqlc), Protobuf |
| Gateway | Rust (hyper + tokio, `mdns-sd`), Protobuf |
| Web | Svelte 5, Tailwind CSS, Vite, IndexedDB (`idb`) |
| Mobile/Desktop | Flutter, Riverpod, SQLite (armazenamento local), mDNS (`nsd`, `multicast_dns`) |
| Infraestrutura | Docker, Docker Compose |

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados, escritos na mesma entrega e não depois. Vale para Go, Rust, Web e Flutter. Os testes também tentam quebrar o sistema de propósito: ataques (inundação de requisições ou conexões, corpos enormes, requisições lentas, entradas hostis) e uso descuidado (toques repetidos, ordem estranha, textos vazios ou gigantes).

| Parte | Comando | Observação |
| --- | --- | --- |
| Backend (Go) | `cd backend && go test ./...` | usa um Postgres de verdade (`backend/.env`); veja o `CLAUDE.md` |
| Gateway (Rust) | `cd gateway && cargo test` | unitários, integração, binário e mDNS (sem multicast, os de mDNS avisam e passam) |
| Web | `cd web && yarn vitest run && yarn check` | |
| Mobile (Flutter) | `cd mobile && fvm flutter test && fvm flutter analyze` | |

## Rodando com Docker

Pré-requisitos: Docker e Docker Compose instalados.

```bash
git clone <url-do-repositorio>
cd plany
cp .env.example .env
# edite o .env: DB_PASSWORD e JWT_SECRET são obrigatórios
docker compose up --build
```

Isso sobe dois serviços:

- `plany` — API, que também serve o build da web (copiado para `./public` na imagem) em `http://localhost:8080`
- `postgres` — banco de dados (PostgreSQL 18)

Por segurança, a senha do banco (`DB_PASSWORD`) e o segredo dos tokens (`JWT_SECRET`) **são obrigatórios e não têm valor padrão**: o compose não sobe enquanto não estiverem definidos no `.env`. Use valores longos e aleatórios (por exemplo, `openssl rand -base64 48`). As demais variáveis têm padrões seguros para uso inicial e podem ser ajustadas no mesmo arquivo.

Para rodar o backend fora do Docker, copie também o exemplo dele:

```bash
cp backend/.env.example backend/.env
```

O `compose.yml` aplica o orçamento de RAM do projeto: 128 MB para a API e 128 MB para o Postgres (256 MB no total, o recomendado), com `GOMEMLIMIT=100MiB` na API. O Postgres só é publicado em `127.0.0.1`. Ele lê `backend/.env` e aceita as variáveis do `.env` da raiz como sobrescrita.

> **Atenção:** o schema do banco ainda não é aplicado automaticamente. As migrações em `backend/internal/database/migrations` precisam ser aplicadas manualmente (por exemplo com `golang-migrate`).

### Várias réplicas atrás do gateway

Para rodar mais de uma instância da API com balanceamento, limite de requisições por IP e anúncio na rede, junte o overlay do gateway ao `compose.yml` (o `.env` com `DB_PASSWORD` e `JWT_SECRET` continua obrigatório):

```bash
docker compose -f compose.yml -f compose.lb.yml up -d --build --scale plany=2
```

O que muda com o overlay:

- O **gateway** (imagem `scratch` de ~2,5 MB, limite de 16 MB de RAM) fica na **rede do host**, porque o mDNS precisa enxergar a LAN, e escuta na porta `PORT` (padrão 8080).
- As réplicas da API deixam de publicar a porta na rede e publicam só em `127.0.0.1:9000-9099` (uma porta por réplica, até 100). Como a rede do host não tem DNS do Docker, o gateway acha as réplicas testando essas portas.
- As réplicas passam a rodar com `IN_APP_RATE_LIMIT=false`: quem limita é o gateway.
- O limite real de réplicas é o Postgres (`max_connections=20`): com o pool padrão (`DB_MAX_CONNS=4`) cabem cerca de 8 réplicas.

No Docker Desktop (Windows e macOS) os containers rodam numa VM e não enxergam a LAN; lá o gateway deve rodar como binário nativo (veja o [README do gateway](./gateway/README.md)).

## Licença

Copyright (C) 2026 João Vitor

Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo sob os termos da GNU Affero General Public License, conforme publicada pela Free Software Foundation, na versão 3 da licença, ou (a seu critério) qualquer versão posterior.

Veja [LICENSE](./LICENSE) para o texto completo da licença.
