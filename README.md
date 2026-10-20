# Plany

Plany é um workspace de notas e organização pessoal no estilo Notion, pensado para ser **self-hosted**: você roda no seu próprio servidor (homelab, VPS, ou máquina local) e mantém total controle sobre seus dados.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Plany deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

## Visão geral

O projeto é dividido em três partes independentes:

- **[`backend/`](./backend)** — API em Go, responsável por autenticação e (em desenvolvimento) sincronização de notas na nuvem.
- **[`web/`](./web)** — interface web em Svelte, embutida na imagem do backend. Depende da API, mas é semi-autossuficiente: guarda as notas no próprio navegador (IndexedDB).
- **[`mobile/`](./mobile)** — aplicativo mobile (e desktop) em Flutter, **autossuficiente**: funciona sem nenhuma API. O servidor só entra para nuvem e sincronização, e é opcional.

O contrato de mensagens entre as três fica em [`shared/protos/`](./shared/protos) (Protobuf).

### Servidores

Na tela de login, os dois clientes têm uma aba superior para adicionar um servidor novo, quando aplicável:

- **Web:** o servidor padrão **é sempre o pré-embutido** (o mesmo que serve a página). Outros servidores da rede, encontrados por mDNS, só aparecem como opções adicionais. Como navegadores não fazem mDNS, a descoberta é feita pelo próprio backend embutido, que repassa a lista à web.
- **Mobile:** escolhe aleatoriamente um dos servidores disponíveis na rede atual, descobertos por mDNS direto no app (`nsd` e `multicast_dns`).

**mDNS e load balancer:** quando existe um load balancer, ele é o serviço na linha de frente e é **ele** quem deve ser anunciado na rede (serviço `_plany._tcp`), não cada instância da API. Sem load balancer, a única instância faz o anúncio. Descoberta e anúncio ainda não estão implementados.

### API stateless

A API deve ser **explicitamente stateless**, para poder rodar atrás de um load balancer com várias instâncias. Nenhum dado de sessão ou de requisição pode ficar na memória do processo: o estado vive no PostgreSQL (por exemplo, tokens revogados) ou no próprio token (JWT).

> **Estado atual:** apenas a autenticação está ativa no servidor. Notas, cofre e sincronização em lote estão planejados.

## Stack

| Camada | Tecnologia |
| --- | --- |
| Backend | Go, PostgreSQL (pgx + sqlc), Protobuf |
| Web | Svelte 5, Tailwind CSS, Vite, IndexedDB (`idb`) |
| Mobile/Desktop | Flutter, SQLite (armazenamento local) |
| Infraestrutura | Docker, Docker Compose |

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados, escritos na mesma entrega e não depois. Vale para Go, Web e Flutter.

## Rodando com Docker

Pré-requisitos: Docker e Docker Compose instalados.

```bash
git clone <url-do-repositorio>
cd plany
docker compose up --build
```

Isso sobe dois serviços:

- `plany` — API, que também serve o build da web (copiado para `./public` na imagem) em `http://localhost:8080`
- `postgres` — banco de dados (PostgreSQL 18)

Por padrão, o projeto sobe com valores de configuração básicos (senhas e segredos de exemplo) — **suficiente para testar, mas não para uso real**. Para produção, copie os arquivos `.env.example` e ajuste os valores:

```bash
cp .env.example .env
cp backend/.env.example backend/.env
```

O `compose.yml` aplica o orçamento de RAM do projeto: 128 MB para a API e 128 MB para o Postgres (256 MB no total, o recomendado), com `GOMEMLIMIT=100MiB` na API. O Postgres só é publicado em `127.0.0.1`. Ele lê `backend/.env` e aceita as variáveis do `.env` da raiz como sobrescrita.

> **Atenção:** o schema do banco ainda não é aplicado automaticamente. As migrações em `backend/internal/database/migrations` precisam ser aplicadas manualmente (por exemplo com `golang-migrate`).

## Licença

Copyright (C) 2026 João Vitor

Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo sob os termos da GNU Affero General Public License, conforme publicada pela Free Software Foundation, na versão 3 da licença, ou (a seu critério) qualquer versão posterior.

Veja [LICENSE](./LICENSE) para o texto completo da licença.
