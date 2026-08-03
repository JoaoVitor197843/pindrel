# Plany

Plany é um workspace de notas e organização pessoal no estilo Notion, pensado para ser **self-hosted**: você roda no seu próprio servidor (homelab, VPS, ou máquina local) e mantém total controle sobre seus dados.

## Visão geral

O projeto é dividido em três partes independentes:

- **[`backend/`](./backend)** — API em Go, responsável por autenticação, persistência de notas e comunicação em tempo real.
- **[`frontend/`](./frontend)** — interface web em Svelte, consumindo a API do backend.
- **[`mobile/`](./mobile)** — aplicativo mobile (e desktop) em Flutter, consumindo a mesma API.

Cada parte tem seu próprio README com detalhes técnicos específicos.

## Stack

| Camada | Tecnologia |
| --- | --- |
| Backend | Go, MongoDB, WebSocket |
| Frontend | Svelte, Tailwind CSS, Vite |
| Mobile/Desktop | Flutter |
| Infraestrutura | Docker, Docker Compose |

## Rodando com Docker

Pré-requisitos: Docker e Docker Compose instalados.

```bash
git clone <url-do-repositorio>
cd plany
docker compose up --build
```

Isso sobe três serviços:

- `backend` — API em `http://localhost:8080`
- `frontend` — interface web em `http://localhost:3000`
- `mongo` — banco de dados

Por padrão, o projeto sobe com valores de configuração básicos (senhas e segredos de exemplo) — **suficiente para testar, mas não para uso real**. Para rodar em produção, copie os arquivos `.env.example` de cada pasta para `.env` e ajuste os valores:

```bash
cp .env.example .env
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
```

## Hardware com ARM antigo (Raspberry Pi 4 ou similar)

O MongoDB, a partir de certas versões, exige microarquitetura ARMv8.2-A ou superior. Por exemplo, Raspberry Pi 4 (Cortex-A72) usa ARMv8.0-A e **não roda versões recentes do MongoDB** — o sintoma é um erro do tipo `Illegal instruction (core dumped)`.

Se for esse o seu caso, edite o `compose.yml` e troque a imagem do serviço `mongo` para uma versão compatível:

```yaml
mongo:
  image: mongo:4.4.18
```

## Licença

Copyright (C) 2026 João Vitor

Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo sob os termos da GNU Affero General Public License, conforme publicada pela Free Software Foundation, na versão 3 da licença, ou (a seu critério) qualquer versão posterior.

Veja [LICENSE](./LICENSE) para o texto completo da licença.
