# Plany Gateway

A porta de entrada de uma instalação do Plany. Fica na frente das réplicas da API e faz quatro coisas:

1. **Balanceia** as requisições entre as réplicas que estão de pé (rodízio), com nova tentativa quando uma réplica recusa a conexão.
2. **Limita** as requisições por IP (login, cadastro e geral), para que a API fique sem estado e possa ter várias réplicas.
3. **Anuncia** o servidor na rede local por mDNS (`_plany._tcp`), para os aplicativos o acharem sozinhos.
4. **Lista** os outros servidores Plany da rede em `GET /server/discover/`, porque o navegador não sabe fazer mDNS.

É o **único código em Rust** do projeto, escrito para gastar o mínimo de RAM: um binário estático de ~1,4 MB que usa de ~1 a 5 MB de memória (medido; veja [Consumo](#consumo)) e roda em Linux (x86 e ARM), Windows e macOS.

> A API em Go não depende do gateway: um `docker compose up` simples continua funcionando, só sem balanceamento, sem limite na entrada e sem anúncio na rede.

## Como funciona

```
 cliente ──► gateway ──┬─► API (réplica 1) ──┐
 (app, web)  (porta     ├─► API (réplica 2) ──┼─► PostgreSQL
              8080)     └─► API (réplica N) ──┘
                 │
                 └─ mDNS: anuncia "Plany" e acha os outros servidores da LAN
```

- **Rodízio com teste de saúde.** A cada 3 s o gateway tenta abrir conexão com cada réplica possível (`UPSTREAMS`) e só envia tráfego às que respondem.
- **Falha de conexão é refeita na próxima réplica, até em `POST`**: se a conexão nem abriu, a réplica nunca viu a requisição, então repetir é seguro. Já um **timeout** vira `504` e **não** é repetido (a réplica pode ter processado).
- **O gateway é a borda.** Ele troca qualquer `X-Forwarded-For` que o cliente mandar pelo endereço real de quem conectou, para ninguém forjar o próprio IP.
- **Erros no mesmo formato da API**: o corpo é o protobuf `ErrorHttp` (`code`, `message`), nunca HTML.

| Situação | Status | `code` |
| --- | --- | --- |
| Limite de requisições estourado | 429 | `rate_limited` |
| Nenhuma réplica disponível | 502 | `bad_gateway` |
| Réplica demorou demais | 504 | `gateway_timeout` |
| Corpo maior que `MAX_BODY_BYTES` | 413 | `payload_too_large` |
| Corpo da requisição não chegou a tempo | 408 | `request_timeout` |
| Requisição inválida | 400 | `bad_request` |

### Limites por IP

| Limite | Taxa | Rajada |
| --- | --- | --- |
| `POST /auth/login/` | 5 por minuto | 5 |
| `POST /auth/register/` | 5 por minuto | 5 |
| Qualquer requisição | 100 por minuto | 20 |

Um IPv6 conta pelo **prefixo /64** (quem tem a faixa inteira não burla o limite trocando de endereço). A conta (GCRA, um horário por cliente) e o relógio vêm da crate `governor`; a tabela de clientes é nossa e tem **teto de 16 384 entradas por limite** (~60 bytes cada, 3 limites cabem em ~2-3 MB, folgado para o contêiner de 16 MiB). Cheia, ela primeiro esquece quem já está com o balde cheio de novo; se continuar cheia, o cliente **novo** é recusado (os que já estão na tabela seguem sendo limitados um a um, não bloqueados em bloco). Medido com 30 000 origens distintas em `POST /auth/login/`: 16 384 passam, 13 616 recebem 429, e a memória sobe 2,3 MB e para.

Toda resposta 429 traz `Retry-After` (segundos inteiros, arredondados para cima, de 1 a 3600): o tempo até o balde ter uma requisição de volta.

### Atrás de um proxy (Cloudflare Tunnel, `tailscale serve`...)

Sem configuração o cliente é quem abriu a conexão, e qualquer `X-Forwarded-For` que ele mande é descartado (o gateway é a borda). Atrás de um túnel todo mundo chegaria de `127.0.0.1` e compartilharia **um** balde. Com `TRUSTED_PROXIES` o gateway passa a acreditar no cabeçalho `CLIENT_IP_HEADER`, mas só quando a conexão veio de um desses proxies:

| Situação | Configuração |
| --- | --- |
| `cloudflared` no mesmo host | `TRUSTED_PROXIES=127.0.0.1,::1` e `CLIENT_IP_HEADER=cf-connecting-ip` (o Cloudflare sempre sobrescreve esse cabeçalho: o cliente não o forja) |
| `tailscale serve` / outro proxy comum | `TRUSTED_PROXIES=127.0.0.1,::1` (usa `x-forwarded-for`) |
| Balanceador em outra máquina | `TRUSTED_PROXIES=10.0.0.5` (ou a faixa) |

Regras: só o cabeçalho configurado é lido (um `Forwarded` ou `X-Real-IP` mandado pelo cliente não vale); várias linhas do mesmo cabeçalho são uma lista, lida **da direita para a esquerda** (o que o cliente escreveu à esquerda nunca é usado); cabeçalho inválido, com bytes que não são texto ou maior que 2 KiB é ignorado inteiro e o cliente passa a ser o próprio proxy (limite mais apertado, nunca mais frouxo). O cliente real vale para os três limites, para o prefixo /64 do IPv6 e para o `X-Forwarded-For` que a API recebe; `Forwarded`, `X-Real-IP`, `CF-Connecting-IP` e `True-Client-IP` não chegam à API.

Com `127.0.0.1` na lista, qualquer processo local que fale com o gateway pela loopback pode escolher o próprio endereço: use uma faixa menor se isso importar.

### Proteções

Timeout de 10 s para ler os cabeçalhos (derruba conexão lenta ou que nunca termina), 10 s para o corpo e 30 s para a réplica responder; teto de conexões abertas (`MAX_CONNECTIONS`); corpo limitado; encerramento gracioso (termina as requisições em andamento, até 5 s).

## mDNS e descoberta

O gateway anuncia `_plany._tcp` com o `SERVER_NAME` **só na interface de rede local** (a que tem a rota padrão, ou as de `MDNS_INTERFACES`), nunca nas pontes do Docker ou em VPNs, que anunciariam endereços inalcançáveis. Se o nome já existe na rede, ele se renomeia (`Plany (2)`); ao sair, avisa a rede. Não é necessário ter nem tirar o `avahi-daemon` do host: os dois convivem.

Pontos que importam na prática:

- **Precisa estar na rede do host.** Um container em rede *bridge* não enxerga a LAN. No Docker Desktop (Windows/macOS) os containers rodam numa VM; lá rode o gateway como binário nativo, apontando `UPSTREAMS` para `localhost`.
- **O Wi-Fi perde pacotes multicast** (medimos de 21% a 48% de perda entre duas máquinas em Wi-Fi 2,4 GHz), e a biblioteca espaça cada vez mais as buscas. Por isso, enquanto o gateway não conhece nenhum outro servidor, ele **reinicia a busca** a cada `MDNS_REFRESH_SECS` (e a cada 4× isso depois que acha algum).
- **Ele lembra dos servidores que já viu.** Um servidor que deixa de ser anunciado não some na hora: o gateway tenta uma conexão TCP nos últimos endereços dele, logo e a cada `KNOWN_PROBE_SECS`, e o mantém na lista enquanto responder. Com `KNOWN_SERVERS_FILE` essa memória é gravada em arquivo (de forma atômica) e lida ao iniciar, então um gateway reiniciado já lista os outros.

### Segurança da descoberta

Um anúncio mDNS é anônimo: qualquer aparelho da rede pode anunciar qualquer endereço. Se o gateway conectasse em tudo que lhe anunciam, ele viraria um escaneador de portas cujo resultado qualquer um leria em `/server/discover/`. Por isso ele **só conecta em endereços da própria sub-rede** (pela máscara da interface; nunca em si mesmo, loopback, outra rede ou a internet) e **em portas a partir de 1024**. As tabelas têm teto (256 servidores anunciados, 64 lembrados) e o arquivo de memória é lido de forma estrita: nunca causa pânico, seja qual for o conteúdo.

## Configuração

Tudo por variáveis de ambiente.

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `UPSTREAMS` | *(obrigatória)* | Réplicas possíveis, `ip:porta` ou `ip:porta-porta`, separadas por vírgula. Ex.: `127.0.0.1:9000-9099,10.0.0.5:8080` |
| `GATEWAY_PORT` | `8080` | Porta em que o gateway escuta |
| `SERVER_NAME` | `Plany` | Nome anunciado na rede (o que o app mostra) |
| `MDNS_ENABLED` | `true` | Liga o anúncio e a descoberta |
| `MDNS_INTERFACES` | *(a da rota padrão)* | Interfaces em que anunciar, separadas por vírgula (ex.: `eth0,wlan0`) |
| `MDNS_REFRESH_SECS` | `15` | De quanto em quanto tempo reinicia a busca enquanto não achou ninguém. `0` desliga |
| `KNOWN_PROBE_SECS` | `15` | De quanto em quanto tempo testa os servidores lembrados que não são mais anunciados. `0` desliga |
| `KNOWN_SERVERS_FILE` | *(sem arquivo)* | Onde guardar os servidores lembrados entre execuções |
| `RATE_LIMIT_ENABLED` | `true` | Liga os limites por IP |
| `PROBE_INTERVAL_SECS` | `3` | De quanto em quanto tempo testa as réplicas |
| `MAX_CONNECTIONS` | `1024` | Conexões abertas ao mesmo tempo |
| `MAX_BODY_BYTES` | `1048576` | Tamanho máximo do corpo de uma requisição |
| `TRUSTED_PROXIES` | vazio | Proxies em que se confia para dizer quem é o cliente (`127.0.0.1,10.0.0.0/8`); vazio = o cliente é quem conectou |
| `CLIENT_IP_HEADER` | `x-forwarded-for` | O único cabeçalho lido (só quando quem conectou está em `TRUSTED_PROXIES`): `x-forwarded-for`, `forwarded` (RFC 7239) ou um de endereço único como `cf-connecting-ip` |

Todos os erros de configuração são mostrados de uma vez, e o gateway não sobe com valor inválido. Os timeouts (10 s, 10 s, 30 s) são fixos no código.

## Rodando

### Com Docker (junto da API)

Pelo `compose.lb.yml` da raiz do repositório, que sobe o gateway na rede do host e põe as réplicas da API atrás dele (veja o [README principal](../README.md#várias-réplicas-atrás-do-gateway)):

```bash
docker compose -f compose.yml -f compose.lb.yml up -d --build --scale plany=2
```

A imagem (`gateway/Dockerfile`) é feita em dois estágios e termina em `scratch`, com só o binário (~2,5 MB), rodando sem root. O `HEALTHCHECK` usa o próprio binário: `/gateway healthcheck`.

### Nativo

```bash
cd gateway
UPSTREAMS=127.0.0.1:9101-9110 GATEWAY_PORT=8200 SERVER_NAME="Minha Casa" cargo run --release
```

Para só testar a descoberta, `UPSTREAMS` pode apontar para qualquer porta (ex.: `127.0.0.1:1`): o gateway anuncia e lista os outros servidores mesmo sem réplica.

### Para um Raspberry Pi de 64 bits, a partir de outra máquina

Sem toolchain C: o `rust-lld` faz o link do binário estático (as flags já estão em `.cargo/config.toml`).

```bash
rustup target add aarch64-unknown-linux-musl
cargo build --release --target aarch64-unknown-linux-musl
# resultado: target/aarch64-unknown-linux-musl/release/gateway
```

> As flags `+crt-static` e `relocation-model=pic` do `.cargo/config.toml` são necessárias: sem elas o binário gerado desse jeito dava falha de segmentação ao iniciar, antes do `main`, num Pi 4 de verdade.

### Plataformas

| Plataforma | Estado |
| --- | --- |
| Linux x86-64 | testado (testes, Docker, rede real) |
| Linux ARM64 (Raspberry Pi 4) | testado no hardware (rede real, Docker, mDNS com `avahi-daemon` ativo) |
| Linux ARM 32 bits, Windows, macOS | só compilação (`cargo check`); não foi executado |

## Consumo

Medido com o gateway balanceando duas réplicas da API:

| Situação | Memória |
| --- | --- |
| Container Docker em repouso | ~0,5 a 1 MiB (cgroup), ~1,8 MB de RSS |
| Processo nativo, 3 000 requisições (30 em paralelo) | ~2 MB (musl) a ~5 MB (glibc) de RSS |
| Pico com 20 corpos de 512 kB em paralelo | ~10 MB (musl) a ~15 MB (glibc), e volta ao normal em seguida |

Para comparar, a API em Go mediu de ~20 a ~65 MiB por réplica (o pico vem do Argon2 no login).

## Testes

```bash
cargo test                                          # tudo
cargo fmt --check && cargo clippy --all-targets -- -D warnings
```

| Camada | O que cobre |
| --- | --- |
| Unitários (`src/`) | configuração, leitura de `UPSTREAMS`, rodízio, limites por IP (rajada, recarga, IPv6, teto da tabela), memória e regras de sub-rede, leitura do protobuf (truncado, tamanhos absurdos, bytes aleatórios) |
| Integração (`tests/gateway.rs`) | o servidor inteiro contra réplicas falsas: rodízio, `X-Forwarded-For` forjado, réplica que morre (inclusive com `POST`), 413/429/502/504, conexão lenta ou que nunca termina, teto de conexões, encerramento que espera as requisições em andamento |
| Memória (`tests/known.rs`) | servidor que continua respondendo, que some, que volta; gravar e ler o arquivo; arquivo corrompido; endereços fora da sub-rede que **não** podem ser testados |
| Binário (`tests/binary.rs`) | configuração inválida, `healthcheck`, `SIGTERM` |
| mDNS real (`tests/mdns.rs`) | dois gateways se achando, conflito de nome, aviso de saída. Sem multicast no ambiente, avisam e passam |

Os arquivos de `tests/golden/*.bin` são mensagens protobuf geradas pelo `protoc` de verdade. O gateway escreve esse protobuf à mão (sem `prost` em produção, para economizar tamanho), então os mesmos arquivos são lidos pelos testes do Rust **e** pelos testes do Go (`backend/internal/api/golden_test.go`), e um teste confere os números dos campos contra `shared/protos`. Se mudar `server.proto` ou `auth.proto`, regenere-os:

```bash
printf 'code: "rate_limited"\nmessage: "too many requests, try again later"\n' \
  | protoc -I../shared/protos --encode=sync.ErrorHttp ../shared/protos/auth.proto > tests/golden/rate_limited.bin
```

O outro arquivo, `discovered.bin`, é gerado do mesmo jeito com `--encode=sync.DiscoveredServers ../shared/protos/server.proto`, a partir da mensagem em texto que está descrita no teste `golden_files_match_the_encoder` (`src/proto.rs`).

## Código

| Arquivo | Responsabilidade |
| --- | --- |
| `src/config.rs` | variáveis de ambiente |
| `src/pool.rs` | quais réplicas estão de pé e em que ordem tentá-las |
| `src/handler.rs` | limites, `GET /server/discover/` e o proxy para as réplicas |
| `src/limiter.rs` | limites por IP |
| `src/discovery.rs` | mDNS: anúncio, busca, lista dos servidores e regras de sub-rede |
| `src/known.rs` | memória dos servidores vistos (teste de endereço e arquivo) |
| `src/proto.rs` | protobuf escrito à mão (`ErrorHttp`, `DiscoveredServers`) |
| `src/server.rs` | liga tudo: porta, tarefas em segundo plano, encerramento |

## Limitações

- **Não repassa WebSocket** (`Upgrade`); será necessário para a sincronização em tempo real planejada.
- Não faz TLS: use um proxy na frente, ou rede confiável.
- O mDNS é só IPv4.
- Um servidor remoto só é achado se estiver na mesma sub-rede; o gateway não faz descoberta entre redes.
