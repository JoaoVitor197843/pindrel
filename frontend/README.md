# Plany — Frontend

Interface web do Plany, construída como SPA (Single Page Application) e servida como arquivos estáticos —
 sem SSR, sem runtime Node em produção.

## Stack

- **Svelte 5** — framework, com compilação em tempo de build
- **Vite** — build tool e dev server
- **Tailwind CSS** — estilização
- **shadcn-svelte** — componentes de UI (copiados para o projeto conforme necessário, não instalados como dependência)

## Estrutura

```text
frontend/
├── src/
│   ├── lib/
│   │   ├── api/            # chamadas HTTP ao backend, por domínio
│   │   ├── components/     # componentes reutilizáveis
│   │   ├── stores/         # estado global (auth, etc.)
│   │   └── types/          # tipos TypeScript compartilhados
│   ├── routes/             # telas da aplicação
│   ├── App.svelte          # componente raiz
│   ├── main.ts             # ponto de entrada
│   └── app.css
├── index.html
├── vite.config.ts
└── package.json
```

## Rodando localmente

Pré-requisitos: Node.js e Yarn instalados.

```bash
cp .env.example .env
yarn install
yarn dev
```

O servidor de desenvolvimento sobe em `http://localhost:5173` por padrão.

## Variáveis de ambiente

| Variável | Descrição | Padrão |
| --- | --- | --- |
| `VITE_API_URL` | URL da API do backend | `http://localhost:8080` |

> **Atenção:** variáveis com prefixo `VITE_` são embutidas no JavaScript no momento do build. Alterar `VITE_API_URL` depois de gerar o build exige recompilar — não basta trocar a variável e reiniciar o container.

## Build de produção

```bash
yarn build
```

Gera os arquivos estáticos em `dist/`, prontos para serem servidos por qualquer servidor HTTP (nginx, Caddy, etc.) — é isso que o `Dockerfile` deste diretório faz.

## Testes

```bash
yarn test
```

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
