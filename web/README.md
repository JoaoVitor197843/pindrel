# Pindrel — Web

Interface web do Pindrel, construída como SPA (Single Page Application) e servida como arquivos estáticos —
 sem SSR, sem runtime Node em produção.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Pindrel deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

## Stack

- **Svelte 5** — framework, com compilação em tempo de build
- **Vite** — build tool e dev server
- **Tailwind CSS** — estilização
- **libsodium-wrappers** — criptografia do cofre (inclui Argon2id; a derivação de chave usa memória no navegador, então os parâmetros precisam respeitar o teto)
- **idb** — wrapper tipado para IndexedDB, onde as notas ficam guardadas no navegador

## Estrutura

```text
web/
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

Os tipos Protobuf gerados ficam em `src/types/shared/protos/` (`make proto-ts` na raiz).
```

## Design system

Mesmo sistema visual do mobile, nativo e sem custo extra de RAM: **sem fontes nem ícones externos** (fonte do sistema e SVG inline, sem biblioteca de ícones). Modo escuro estrito, no estilo Linear/Vercel:

| Papel | Cor |
| --- | --- |
| Fundo | `#121214` |
| Cards | `#1A1A1E`, borda de 1px `#29292E` |
| Texto principal | `#E1E1E6` |
| Texto secundário | `#A8A8B3` |
| Destaque | `#8257E5` |

Cantos de 8px (`rounded-lg` no Tailwind). Sem sombras pesadas e sem visual de biblioteca de componentes genérica. As cores ficam definidas uma única vez, como tokens do tema do Tailwind em `src/app.css`, e os componentes só usam esses tokens. Listas longas devem ser renderizadas de forma incremental (virtualizadas ou paginadas), não inteiras no DOM.

## Dados e servidor

A web vem embutida na imagem do backend e depende da API para autenticação e sincronização. Mesmo assim ela é semi-autossuficiente: todas as notas ficam no próprio navegador (IndexedDB, via `idb`).

Na tela de login, uma aba superior permite adicionar um servidor novo, quando aplicável. O servidor padrão é **sempre o pré-embutido**, o mesmo que serve a página. Servidores encontrados na rede por mDNS aparecem como opções adicionais, nunca substituem o padrão. Como o navegador não faz mDNS, a lista vem do backend embutido, e o serviço anunciado é o que está na linha de frente (o load balancer, quando houver, e não cada instância da API).

## Rodando localmente

Pré-requisitos: Node.js e Yarn instalados.

```bash
yarn install
yarn dev
```

O servidor de desenvolvimento sobe em `http://localhost:5173` por padrão e repassa `/auth`, `/sync`, `/servers`, `/health` e `/swagger` para o backend em `http://localhost:8080` (proxy do Vite), então suba o backend antes. Outros comandos: `yarn build`, `yarn check` e `yarn vitest` (testes).

## Rotas de página

O servidor Go só entrega o `index.html` para as rotas de página listadas em `isWebRoute` (`backend/internal/api/route/router.go`): hoje `/`, `/login` e `/notes/:id`. Qualquer outro caminho que não seja um arquivo do build devolve 404. Ao criar ou renomear uma rota de página aqui, atualize essa lista no backend.

## Configuração da API

A web **não tem variáveis de ambiente nem `.env`**. As chamadas usam caminhos relativos direto na raiz do servidor (`/auth/login/`, `/auth/refresh/`, ...), sem prefixo `/api`, porque a página e a API são servidas pelo mesmo servidor embutido. Em desenvolvimento, o proxy do Vite em `vite.config.ts` faz o mesmo papel. Outro servidor, quando adicionado na tela de login, é guardado em tempo de execução, não no build.

## Build de produção

```bash
yarn build
```

Gera os arquivos estáticos em `dist/`, que o `Dockerfile` da raiz copia para `./public` na imagem do backend, onde o servidor Go os serve.

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados, escritos na mesma entrega e não depois. Vale para Go, Web e Flutter.

```bash
yarn vitest
```

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
