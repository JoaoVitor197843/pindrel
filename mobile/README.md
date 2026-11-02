# Pindrel — Mobile

Aplicativo mobile (e desktop) do Pindrel, construído em Flutter. É **autossuficiente**: guarda e cifra tudo no dispositivo e funciona sem nenhum servidor. A API Go serve apenas para nuvem e sincronização, e é opcional.

## Prioridades do projeto

1. **Uso mínimo absoluto de RAM.** O Pindrel deve rodar em dispositivos fracos, como um Raspberry Pi antigo ou um celular antigo. Meta: **teto máximo de 512 MB de RAM** e **recomendado de 256 MB**, contando tudo o que é necessário para rodar, inclusive o banco de dados. O limite vale **por instância**; com load balancer, cada instância da API segue o mesmo teto individualmente. Na prática: preferir bibliotecas pequenas, evitar manter dados inteiros em memória, limitar conexões e picos de memória (por exemplo, derivação de chave).
2. **Custo dividido entre cliente e servidor.** Nenhum lado deve receber todo o overhead por conta do outro. Onde o overhead é inevitável (segurança e criptografia), ele é o foco, mas com equilíbrio entre as partes.

## Stack

- **Flutter** — framework, com suporte a Android, iOS, Linux, macOS e Windows a partir da mesma base de código
- **FVM** — gerenciamento de versão do Flutter, fixado por projeto
- **sqlite3** — armazenamento local das notas em SQLite; lê do disco sob demanda em vez de manter tudo em memória (a biblioteca anterior, Hive, carrega as caixas inteiras na RAM)
- **flutter_secure_storage** — chaves e segredos no cofre do sistema
- **sodium** — criptografia do cofre seguro
- **flutter_riverpod** — gerenciamento de estado
- **nsd** e **multicast_dns** — descoberta de servidores na rede por mDNS (`nsd` em Android, iOS e macOS; `multicast_dns` em Linux, onde o `nsd` não existe, e em Windows, onde o `nsd` perde os resultados porque os envia de uma thread que não é a da plataforma)
- **http**, **protobuf**, **fixnum** — comunicação opcional com o servidor de nuvem/sincronização (`http` no lugar do `dio`, bem menor)
- **path_provider**, **path** — localização do arquivo do banco

Fontes e ícones usam os do sistema e o Material Icons embutido; `google_fonts`, `lucide_icons` e `cupertino_icons` foram removidos.

## Estrutura

```text
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── crypto/          # criptografia client-side (cofre seguro)
│   │   ├── database/        # SQLite local
│   │   ├── network/         # cliente HTTP e descoberta de servidores
│   │   ├── storage/         # armazenamento seguro de chaves
│   │   └── theme/           # design system (cores, bordas, tipografia)
│   ├── features/
│   │   ├── auth/
│   │   ├── notes/
│   │   └── vault/           # cada feature: data/ e presentation/{providers,pages,widgets}
│   └── shared/protos/       # tipos Protobuf gerados
├── test/
├── android/
├── ios/
├── linux/
├── macos/
├── windows/
└── pubspec.yaml
```

A organização é **feature-first**: cada feature (`auth`, `notes`, `vault`) tem sua camada `data/` e sua `presentation/` com `providers`, `pages` e `widgets`. O que é transversal fica em `core/`.

## Design system

Sem fontes nem ícones externos, o visual é nativo e não consome RAM extra. Modo escuro estrito, no estilo Linear/Vercel:

| Papel | Cor |
| --- | --- |
| Fundo | `#121214` |
| Cards | `#1A1A1E`, borda de 1px `#29292E` |
| Texto principal | `#E1E1E6` |
| Texto secundário | `#A8A8B3` |
| Destaque | `#8257E5` |

Cantos de 8px (`BorderRadius.circular(8)`). É proibido o visual genérico do Material 3: sem sombras pesadas, construtores `const` sempre que possível e `ListView.builder` nas listas. As cores ficam centralizadas em `core/theme`.

## Rodando localmente

Pré-requisitos: [FVM](https://fvm.app/) instalado.

```bash
fvm use
fvm flutter pub get
fvm flutter run
```

Para rodar como aplicativo desktop:

```bash
fvm flutter run -d linux   # ou -d windows / -d macos
```

## Configuração

O app não depende de servidor nem de arquivo `.env` (não há `.env.example` no mobile).

Na tela de login, uma aba superior permite adicionar um servidor novo, quando aplicável. Por padrão o app escolhe aleatoriamente um dos servidores disponíveis na rede atual, descobertos por mDNS (`_pindrel._tcp`). O serviço anunciado é o que está na linha de frente, ou seja, o load balancer quando houver, e não cada instância da API. As bibliotecas já estão instaladas, mas a descoberta ainda não está implementada.

O app não tem plataforma web: os alvos são Android, iOS, Linux, macOS e Windows.

As configurações do usuário (lixeira, idioma, IA) ficam **apenas no dispositivo**; o servidor não as guarda.

## Cofre seguro

Notas marcadas como conteúdo sensível (senhas e afins) usam criptografia client-side no modelo zero-knowledge: o conteúdo é cifrado no dispositivo antes de ser enviado ao servidor, que nunca tem acesso à chave de decriptação. Não há recuperação de senha mestra do cofre — perdê-la significa perder o acesso ao conteúdo cifrado.

No desktop, o armazenamento seguro depende do `libsecret` (Linux) ou do cofre nativo do sistema operacional (Windows/macOS).

## Testes

Todo componente ou serviço novo deve ser criado junto com seus testes automatizados.

```bash
fvm flutter test
```

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
