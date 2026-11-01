# Plany

**Um workspace de notas self-hosted que cabe em 256 MB de RAM.**

O Plany é um espaço de notas e organização no estilo Notion que você roda no seu próprio servidor (um Raspberry Pi, um homelab, uma VPS ou a sua máquina) e no celular, com controle total sobre os seus dados. Ele foi pensado como os jogos de consoles antigos: tem um **orçamento de memória** e cada recurso precisa caber nele, sem abrir mão de funcionalidade nem de segurança.

> **Estado atual: alpha.** Hoje funcionam a autenticação, o gateway (balanceamento, limites por IP e anúncio na rede) e a descoberta de servidores no app. **Notas, cofre e sincronização ainda estão em desenvolvimento**, então não há uma versão estável para uso diário.

## Por que o Plany

- **Leve de propósito.** Meta de no máximo **512 MB de RAM** e recomendado de **256 MB**, contando tudo, inclusive o banco de dados. Num Raspberry Pi 4, cada réplica da API usa cerca de 60 MB e o gateway cerca de 1,6 MB.
- **O app funciona sozinho.** O aplicativo (Android, iOS, Windows, macOS e Linux, feito em Flutter) guarda as notas no próprio aparelho e não precisa de servidor. O servidor só entra para nuvem e sincronização, e é opcional.
- **O servidor se acha sozinho.** Ligou o servidor na rede? O app o encontra pela rede local (mDNS), sem digitar IP.
- **Cofre zero-knowledge, opcional.** Para os itens sensíveis, o conteúdo é cifrado no aparelho e o servidor nunca vê a chave. *(planejado)*
- **Software livre** sob a AGPL v3.

## Como as partes se encaixam

O projeto é dividido em partes independentes:

- **[`backend/`](./backend)**: API em Go, responsável por autenticação e (em desenvolvimento) sincronização de notas na nuvem.
- **[`gateway/`](./gateway)**: a porta de entrada de uma instalação, em Rust. Balanceia as réplicas da API, limita requisições por IP, anuncia o servidor na rede (mDNS) e lista os outros servidores da rede. É um binário estático de ~1,4 MB. Veja o [README do gateway](./gateway/README.md).
- **[`web/`](./web)**: interface web em Svelte, embutida na imagem do backend. Depende da API, mas guarda as notas no próprio navegador (IndexedDB).
- **[`mobile/`](./mobile)**: aplicativo mobile e desktop em Flutter, **autossuficiente**.

O contrato de mensagens entre as partes fica em [`shared/protos/`](./shared/protos) (Protobuf).

### Servidores

Na tela de login, os dois clientes têm uma aba superior para escolher (e, no futuro, adicionar) um servidor:

- **Mobile:** descobre sozinho, por mDNS (`_plany._tcp`), os servidores da rede atual e sorteia um deles, testando se ele responde antes de entrar. A lista acompanha a rede **ao vivo**. Se o servidor escolhido sai da rede, ele **não some**: continua escolhido, a bolinha ao lado do nome passa de verde para vermelha, e ele aparece em "Desconectados". Quando volta, a bolinha volta a ser verde. Com o app em segundo plano, a busca é pausada.
- **Web:** o servidor padrão **é sempre o embutido** (o mesmo que serve a página). Como navegadores não fazem mDNS, a lista dos outros servidores da rede vem do **gateway**, em `GET /server/discover/`. A aba da web ainda não foi implementada.

**mDNS e gateway:** quem anuncia o servidor na rede é o **gateway**, e não cada instância da API. Ele anuncia só na interface da rede local, resolve conflito de nomes (`Plany`, `Plany (2)`...), avisa quando sai e, como o Wi-Fi perde muitos pacotes multicast, refaz a busca de tempos em tempos e **lembra** dos servidores já vistos. Sem o gateway (um `docker compose up` simples) não há anúncio na rede. O mDNS só funciona com o gateway na **rede do host**: um container em rede bridge não enxerga a LAN.

### API stateless

A API é **explicitamente stateless**, para poder rodar atrás de um load balancer com várias instâncias: o estado vive no PostgreSQL (por exemplo, tokens revogados) ou no próprio token (JWT). Os limites de requisição por IP da própria API ficam na memória de cada instância; atrás do gateway, que passa a limitar na entrada, eles são desligados com `IN_APP_RATE_LIMIT=false`.

## Stack

| Camada | Tecnologia |
| --- | --- |
| Backend | Go, PostgreSQL (pgx + sqlc), Protobuf |
| Gateway | Rust (hyper + tokio, `mdns-sd`), Protobuf |
| Web | Svelte 5, Tailwind CSS, Vite, IndexedDB (`idb`) |
| Mobile/Desktop | Flutter, Riverpod, SQLite (armazenamento local), mDNS (`nsd`, `multicast_dns`) |
| Infraestrutura | Docker, Docker Compose |

## Rodando com Docker

Pré-requisitos: Docker e Docker Compose instalados.

```bash
git clone https://github.com/JoaoVitor197843/plany.git
cd plany
cp .env.example .env
# edite o .env: DB_PASSWORD e JWT_SECRET são obrigatórios
docker compose up --build
```

Isso sobe dois serviços:

- `plany`: a API, que também serve o build da web em `http://localhost:8080`
- `postgres`: o banco de dados (PostgreSQL 18)

Por segurança, a senha do banco (`DB_PASSWORD`) e o segredo dos tokens (`JWT_SECRET`) **são obrigatórios e não têm valor padrão**: o compose não sobe enquanto não estiverem definidos no `.env`. Use valores longos e aleatórios (por exemplo, `openssl rand -base64 48`). As demais variáveis têm padrões seguros para uso inicial e podem ser ajustadas no mesmo arquivo. O banco é criado e atualizado sozinho: a API aplica as migrações ao iniciar.

As imagens prontas (amd64 e arm64, também para Raspberry Pi) estão no Docker Hub: `joaovitor2753/plany` e `joaovitor2753/plany-gateway`.

O `compose.yml` aplica o orçamento de RAM do projeto: 128 MB para a API e 128 MB para o Postgres (256 MB no total, o recomendado), com `GOMEMLIMIT=100MiB` na API. O Postgres só é publicado em `127.0.0.1`.

Para rodar o backend fora do Docker, copie também o exemplo dele: `cp backend/.env.example backend/.env`.

### Várias réplicas atrás do gateway

Para rodar mais de uma instância da API com balanceamento, limite de requisições por IP e anúncio na rede, junte o overlay do gateway ao `compose.yml` (o `.env` continua obrigatório):

```bash
docker compose -f compose.yml -f compose.lb.yml up -d --build --scale plany=2
```

O que muda com o overlay:

- O **gateway** (imagem `scratch` de ~2,5 MB, limite de 16 MB de RAM) fica na **rede do host**, porque o mDNS precisa enxergar a LAN, e escuta na porta `PORT` (padrão 8080).
- As réplicas da API deixam de publicar a porta na rede e publicam só em `127.0.0.1:9000-9099` (uma porta por réplica, até 100).
- As réplicas passam a rodar com `IN_APP_RATE_LIMIT=false`: quem limita é o gateway.
- O limite real de réplicas é o Postgres (`max_connections=20`): com o pool padrão (`DB_MAX_CONNS=4`) cabem cerca de 8 réplicas.

No Docker Desktop (Windows e macOS) os containers rodam numa VM e não enxergam a LAN; lá o gateway deve rodar como binário nativo (veja o [README do gateway](./gateway/README.md)).

## Desenvolvimento

O desenvolvimento acontece num repositório próprio; **este repositório do GitHub é um espelho**. Pull requests ainda não são aceitos aqui (o espelho sobrescreve o que não vem do repositório principal), mas **issues são bem-vindas** para relatar problemas e sugerir ideias.

Duas prioridades guiam as decisões do projeto:

1. **Uso mínimo absoluto de RAM.** O Plany deve rodar em dispositivos fracos, como um Raspberry Pi ou um celular antigo, e o limite vale **por instância**. Na prática: bibliotecas pequenas, nada de manter dados inteiros em memória, conexões e picos de memória (como a derivação de chave) limitados. O espaço em disco importa bem menos que a RAM.
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde ele é inevitável (segurança e criptografia), é o foco, com equilíbrio entre as partes.

Todo componente novo nasce com testes automatizados, inclusive os que tentam quebrar o sistema de propósito: inundação de requisições, corpos enormes, entradas hostis e uso descuidado (toques repetidos, textos vazios ou gigantes).

| Parte | Comando | Observação |
| --- | --- | --- |
| Backend (Go) | `cd backend && go test ./...` | usa um Postgres de verdade (`backend/.env`); veja o `CLAUDE.md` |
| Gateway (Rust) | `cd gateway && cargo test` | unitários, integração, binário e mDNS (sem multicast, os de mDNS avisam e passam) |
| Web | `cd web && yarn vitest run && yarn check` | |
| Mobile (Flutter) | `cd mobile && fvm flutter test && fvm flutter analyze` | |

O [`CLAUDE.md`](./CLAUDE.md) reúne o detalhamento técnico (arquitetura, convenções, release) usado pelo mantenedor e pelo Claude Code.

## Licença

O Plany é software livre, licenciado sob a **GNU Affero General Public License, versão 3** (ou, a seu critério, qualquer versão posterior). Na prática: você pode usar, estudar, modificar e redistribuir o Plany; se rodar uma versão modificada como serviço acessível pela rede, precisa oferecer o código-fonte dela aos usuários desse serviço.

O texto completo está em [LICENSE](./LICENSE).

Copyright (C) 2026 João Vitor
