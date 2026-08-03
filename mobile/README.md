# Plany — Mobile

Aplicativo mobile (e desktop) do Plany, construído em Flutter. Consome a mesma API usada pelo frontend web, sem nenhuma lógica exclusiva de plataforma na camada de negócio.

## Stack

- **Flutter** — framework, com suporte a Android, iOS, Linux, macOS e Windows a partir da mesma base de código
- **FVM** — gerenciamento de versão do Flutter, fixado por projeto

## Estrutura

```text
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── api/            # chamadas HTTP ao backend, por domínio
│   │   ├── storage/         # cache local e armazenamento seguro
│   │   └── crypto/          # criptografia client-side (cofre seguro)
│   ├── models/
│   ├── providers/            # gerenciamento de estado
│   ├── screens/               # telas da aplicação
│   └── widgets/                # componentes reutilizáveis
├── test/
├── android/
├── ios/
├── linux/
├── macos/
├── windows/
└── pubspec.yaml
```

## Rodando localmente

Pré-requisitos: [FVM](https://fvm.app/) instalado.

```bash
cp .env.example .env
fvm use stable
fvm flutter pub get
fvm flutter run
```

Para rodar como aplicativo desktop:

```bash
fvm flutter run -d linux   # ou -d windows / -d macos
```

## Variáveis de ambiente

| Variável | Descrição | Padrão |
| --- | --- | --- |
| `API_URL` | URL da API do backend | `http://localhost:8080` |

## Cofre seguro

Notas marcadas como conteúdo sensível (senhas e afins) usam criptografia client-side no modelo zero-knowledge: o conteúdo é cifrado no dispositivo antes de ser enviado ao servidor, que nunca tem acesso à chave de decriptação. Não há recuperação de senha mestra do cofre — perdê-la significa perder o acesso ao conteúdo cifrado.

No desktop, o armazenamento seguro depende do `libsecret` (Linux) ou do cofre nativo do sistema operacional (Windows/macOS).

## Testes

```bash
fvm flutter test
```

## Licença

Este projeto é licenciado sob a GNU Affero General Public License v3.0. Veja [LICENSE](../LICENSE) na raiz do repositório.
