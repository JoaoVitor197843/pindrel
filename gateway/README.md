# Pindrel Gateway

A porta de entrada de uma instalação do Pindrel. Fica na frente das réplicas da API e:

1. **Balanceia** as requisições entre as réplicas que estão de pé (rodízio), com nova tentativa quando uma réplica recusa a conexão.
2. **Limita** as requisições por IP (login, cadastro, arquivos e geral), para que a API fique sem estado e possa ter várias réplicas.
3. **Anuncia** o servidor na rede local por mDNS (`_pindrel._tcp`), para os aplicativos o acharem sozinhos.
4. **Lista** os outros servidores Pindrel da rede em `GET /server/discover/`, porque o navegador não sabe fazer mDNS.
5. **Repassa WebSocket** (`Upgrade` do HTTP/1.1) para uma réplica, byte a byte.
6. Opcionalmente, **serve HTTPS** (HTTP/1.1 e HTTP/2) com uma autoridade certificadora própria e **pareia aparelhos** (seis dígitos numa sala ou código mestre). Detalhes em `CLAUDE.md`, seção "TLS".

É o **único código em Rust** do projeto, escrito para gastar o mínimo de RAM: um binário estático de ~1,4 MB que usa de ~1 a 5 MB de memória (medido; veja [Consumo](#consumo)) e roda em Linux (x86 e ARM), Windows e macOS.

> A API em Go não depende do gateway: um `docker compose up` simples continua funcionando, só sem balanceamento, sem limite na entrada e sem anúncio na rede.

## Como funciona

```
 cliente ──► gateway ──┬─► API (réplica 1) ──┐
 (app, web)  (porta     ├─► API (réplica 2) ──┼─► PostgreSQL
              8080)     └─► API (réplica N) ──┘
                 │
                 └─ mDNS: anuncia "Pindrel" e acha os outros servidores da LAN
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
| `/files/*` (pedaços de upload, downloads com Range) | 1200 por minuto | 120 |
| Qualquer outra requisição | 100 por minuto | 20 |

Um IPv6 conta pelo **prefixo /64** (quem tem a faixa inteira não burla o limite trocando de endereço). A conta (GCRA, um horário por cliente) e o relógio vêm da crate `governor`; a tabela de clientes é nossa e tem **teto de 16 384 entradas por limite** (algumas dezenas de bytes cada: os 4 limites cheios cabem em poucos MB, folgado para o contêiner de 48 MiB). Cheia, ela primeiro esquece quem já está com o balde cheio de novo; se continuar cheia, o cliente **novo** é recusado (os que já estão na tabela seguem sendo limitados um a um, não bloqueados em bloco). Medido com 30 000 origens distintas em `POST /auth/login/`: 16 384 passam, 13 616 recebem 429, e a memória sobe 2,3 MB e para.

Toda resposta 429 traz `Retry-After` (segundos inteiros, arredondados para cima, de 1 a 3600): o tempo até o balde ter uma requisição de volta.

### Atrás de um proxy (Cloudflare Tunnel, `tailscale serve`...)

Sem configuração o cliente é quem abriu a conexão, e qualquer `X-Forwarded-For` que ele mande é descartado (o gateway é a borda). Atrás de um túnel todo mundo chegaria de `127.0.0.1` e compartilharia **um** balde. Com `TRUSTED_PROXIES` o gateway passa a acreditar no cabeçalho `CLIENT_IP_HEADER`, mas só quando a conexão veio de um desses proxies:

| Situação | Configuração |
| --- | --- |
| `cloudflared` no mesmo host | `TRUSTED_PROXIES=127.0.0.1,::1` e `CLIENT_IP_HEADER=cf-connecting-ip` (o Cloudflare sempre sobrescreve esse cabeçalho: o cliente não o forja) |
| `tailscale serve` / outro proxy comum | `TRUSTED_PROXIES=127.0.0.1,::1` (usa `x-forwarded-for`) |
| Balanceador em outra máquina | `TRUSTED_PROXIES=10.0.0.5` (ou a faixa) |

Regras: só o cabeçalho configurado é lido (um `Forwarded` ou `X-Real-IP` mandado pelo cliente não vale); várias linhas do mesmo cabeçalho são uma lista, lida **da direita para a esquerda** (o que o cliente escreveu à esquerda nunca é usado); cabeçalho inválido, com bytes que não são texto ou maior que 2 KiB é ignorado inteiro e o cliente passa a ser o próprio proxy (limite mais apertado, nunca mais frouxo). O cliente real vale para os limites, para o prefixo /64 do IPv6 e para o `X-Forwarded-For` que a API recebe; `Forwarded`, `X-Real-IP`, `CF-Connecting-IP` e `True-Client-IP` não chegam à API.

Com `127.0.0.1` na lista, qualquer processo local que fale com o gateway pela loopback pode escolher o próprio endereço: use uma faixa menor se isso importar.

### Proteções

Timeout de 10 s para ler os cabeçalhos (derruba conexão lenta ou que nunca termina), 10 s para o corpo e 30 s para a réplica responder (um pedaço de arquivo tem `FILE_BODY_TIMEOUT_SECS` e o `POST /files/uploads/../finish` tem `FILE_FINISH_TIMEOUT_SECS`); teto de conexões abertas (`MAX_CONNECTIONS`) e por cliente (`MAX_CONNECTIONS_PER_IP`); corpo limitado e um orçamento de corpos guardados em memória ao mesmo tempo (`BODY_BUDGET_BYTES`; pedidos sem corpo e corpos de até 64 KiB não entram nele; sem espaço em 5 s: `503 server_busy`); encerramento gracioso (termina as requisições em andamento, até 5 s).

## mDNS e descoberta

O gateway anuncia `_pindrel._tcp` com o `SERVER_NAME` **só na interface de rede local** (a que tem a rota padrão, ou as de `MDNS_INTERFACES`), nunca nas pontes do Docker ou em VPNs, que anunciariam endereços inalcançáveis. Se o nome já existe na rede, ele se renomeia (`Pindrel (2)`); ao sair, avisa a rede. Não é necessário ter nem tirar o `avahi-daemon` do host: os dois convivem.

Pontos que importam na prática:

- **Precisa estar na rede do host.** Um container em rede *bridge* não enxerga a LAN. No Docker Desktop (Windows/macOS) os containers rodam numa VM; lá rode o gateway como binário nativo, apontando `UPSTREAMS` para `localhost`.
- **O Wi-Fi perde pacotes multicast** (medimos de 21% a 48% de perda entre duas máquinas em Wi-Fi 2,4 GHz), e a biblioteca espaça cada vez mais as buscas. Por isso, enquanto o gateway não conhece nenhum outro servidor, ele **reinicia a busca** a cada `MDNS_REFRESH_SECS` (e a cada 4× isso depois que acha algum).
- **Ele lembra dos servidores que já viu.** Um servidor que deixa de ser anunciado não some na hora: o gateway tenta uma conexão TCP nos últimos endereços dele, logo e a cada `KNOWN_PROBE_SECS`, e o mantém na lista enquanto responder. Com `KNOWN_SERVERS_FILE` essa memória é gravada em arquivo (de forma atômica) e lida ao iniciar, então um gateway reiniciado já lista os outros.

### Segurança da descoberta

Um anúncio mDNS é anônimo: qualquer aparelho da rede pode anunciar qualquer endereço. Se o gateway conectasse em tudo que lhe anunciam, ele viraria um escaneador de portas cujo resultado qualquer um leria em `/server/discover/`. Por isso ele **só conecta em endereços da própria sub-rede** (pela máscara da interface; nunca em si mesmo, loopback, outra rede ou a internet) e **em portas a partir de 1024**. As tabelas têm teto (256 servidores anunciados, 64 lembrados) e o arquivo de memória é lido de forma estrita: nunca causa pânico, seja qual for o conteúdo.

## Configuração

Por variáveis de ambiente ou por um arquivo de linhas `CHAVE=valor` (`--config <arquivo>` ou `GATEWAY_CONFIG`; uma variável de ambiente de verdade vence o arquivo). `gateway --check` só valida a configuração e sai. As principais:

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `UPSTREAMS` | *(obrigatória)* | Réplicas possíveis, `ip:porta` ou `ip:porta-porta`, separadas por vírgula. Ex.: `127.0.0.1:9000-9099,10.0.0.5:8080` |
| `GATEWAY_PORT` | `8080` | Porta em que o gateway escuta |
| `SERVER_NAME` | `Pindrel` | Nome anunciado na rede (o que o app mostra) |
| `MDNS_ENABLED` | `true` | Liga o anúncio e a descoberta |
| `MDNS_INTERFACES` | *(a da rota padrão)* | Interfaces em que anunciar, separadas por vírgula (ex.: `eth0,wlan0`) |
| `MDNS_REFRESH_SECS` | `15` | De quanto em quanto tempo reinicia a busca enquanto não achou ninguém. `0` desliga |
| `KNOWN_PROBE_SECS` | `15` | De quanto em quanto tempo testa os servidores lembrados que não são mais anunciados. `0` desliga |
| `KNOWN_SERVERS_FILE` | *(sem arquivo)* | Onde guardar os servidores lembrados entre execuções |
| `RATE_LIMIT_ENABLED` | `true` | Liga os limites por IP |
| `PROBE_INTERVAL_SECS` | `3` | De quanto em quanto tempo testa as réplicas |
| `SERVER_ID_FILE` | *(sem arquivo)* | Onde guardar o id deste servidor (sem arquivo, um id novo a cada início) |
| `MAX_CONNECTIONS` | `1024` | Conexões abertas ao mesmo tempo |
| `MAX_CONNECTIONS_PER_IP` | `64` | Conexões abertas de um mesmo cliente (proxies declarados não contam) |
| `MAX_BODY_BYTES` | `1048576` | Tamanho máximo do corpo de uma requisição |
| `BODY_BUDGET_BYTES` | `8388608` | Bytes de corpos guardados em memória ao mesmo tempo |
| `FILE_BODY_TIMEOUT_SECS` / `FILE_FINISH_TIMEOUT_SECS` | `60` / `600` | Prazo de um pedaço de arquivo chegar / de a réplica juntar o arquivo |
| `MAX_WEBSOCKETS` / `MAX_WEBSOCKETS_PER_IP` / `WS_IDLE_SECS` | `1024` / `32` / `600` | Túneis WebSocket no total, por cliente, e tempo parado até fechar |
| `WS_ALLOWED_ORIGINS` | vazio | Origens (além da própria) que podem abrir WebSocket por um navegador |
| `TLS_PORT` | *(desligado)* | Porta do HTTPS (precisa da build com `--features tls` ou `selfcert`; diferente de `GATEWAY_PORT`) |
| `TLS_AUTO` + `TLS_DIR` | `false` | CA própria guardada em `TLS_DIR` (feature `selfcert`); ou `TLS_CERT_FILE` + `TLS_KEY_FILE` |
| `TLS_SANS` / `TLS_REFRESH_SECS` | vazio / `3600` | Nomes extras do certificado / de quanto em quanto tempo o certificado é olhado de novo |
| `HTTP_MODE` | `full` | Com HTTPS ligado: `full` (a porta HTTP atende tudo) ou `redirect` (só as rotas de início; o resto vai para HTTPS) |
| `PAIRING_MAX_ROOMS` | `6` | Salas de pareamento abertas ao mesmo tempo (1 a 64) |
| `TRUSTED_PROXIES` | vazio | Proxies em que se confia para dizer quem é o cliente (`127.0.0.1,10.0.0.0/8`); vazio = o cliente é quem conectou |
| `CLIENT_IP_HEADER` | `x-forwarded-for` | O único cabeçalho lido (só quando quem conectou está em `TRUSTED_PROXIES`): `x-forwarded-for`, `forwarded` (RFC 7239) ou um de endereço único como `cf-connecting-ip` |

Todos os erros de configuração são mostrados de uma vez, e o gateway não sobe com valor inválido. Os timeouts (10 s, 10 s, 30 s) são fixos no código.

## Rodando

### Com Docker (junto da API)

Pelo `compose.lb.yml` da raiz do repositório, que sobe o gateway na rede do host e põe as réplicas da API atrás dele (veja o [README principal](../README.md#várias-réplicas-atrás-do-gateway)):

```bash
docker compose -f compose.yml -f compose.lb.yml up -d --build --scale pindrel=2
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

Esse é o gateway sem HTTPS. Com HTTPS (`--features selfcert`, como na imagem e nas releases) entra o `ring`, que tem partes em C e assembly e precisa de um compilador C para o alvo. O [zig](https://ziglang.org) faz esse papel para os dois alvos musl (`cross/zigcc`, o mesmo do `Dockerfile`):

```bash
export CC_aarch64_unknown_linux_musl=$PWD/cross/zigcc-aarch64 AR_aarch64_unknown_linux_musl=$PWD/cross/zigar
export CC_x86_64_unknown_linux_musl=$PWD/cross/zigcc-x86_64 AR_x86_64_unknown_linux_musl=$PWD/cross/zigar
cargo build --release --target aarch64-unknown-linux-musl --features selfcert
```

Um binário sem HTTPS recusa `TLS_PORT` já no `--check`. Antes ele aceitava a configuração e atendia só em HTTP.

### Instaladores

- **Linux** (`installer/linux/`, dentro do `.tar.gz` da release): `sudo ./install.sh` cria o serviço systemd com usuário próprio. Ele pergunta o nome, a porta, os endereços da API e se liga o HTTPS (por padrão liga: a CA fica em `/var/lib/pindrel-gateway/tls`). Também aceita `--no-https` e `--tls-port N`. Rodar de novo mantém o `gateway.env`; `sudo ./install.sh --https` acrescenta o HTTPS a uma configuração que ainda não tem. Testes: `sh installer/linux/test_install.sh`.
- **Windows** (`installer/windows/`, Inno Setup): a tarefa "Ativar HTTPS" também vale numa atualização. Nesse caso ela acrescenta o HTTPS ao `gateway.env` mantido, depois de conferir que a porta 8443 está livre. Se a configuração já tem HTTPS, a tarefa não aparece.

### Plataformas

| Plataforma | Estado |
| --- | --- |
| Linux x86-64 | testado (testes, Docker, rede real) |
| Linux ARM64 (Raspberry Pi 4) | testado no hardware (rede real, Docker, mDNS com `avahi-daemon` ativo) |
| Windows | testes e instalador executados à mão num Windows 11 |
| Linux ARM 32 bits, macOS | só compilação (`cargo check`); não foi executado |

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
cargo test --all-features                           # tudo (sem features, os testes de HTTPS e pareamento ficam de fora; a CI roda os dois)
cargo fmt --check && cargo clippy --all-targets --all-features -- -D warnings
```

| Camada | O que cobre |
| --- | --- |
| Unitários (`src/`) | configuração, leitura de `UPSTREAMS`, rodízio, limites por IP (rajada, recarga, IPv6, teto da tabela), memória e regras de sub-rede, leitura do protobuf (truncado, tamanhos absurdos, bytes aleatórios) |
| Integração (`tests/gateway.rs`) | o servidor inteiro contra réplicas falsas: rodízio, `X-Forwarded-For` forjado, réplica que morre (inclusive com `POST`), 413/429/502/504, conexão lenta ou que nunca termina, teto de conexões, encerramento que espera as requisições em andamento |
| Memória (`tests/known.rs`) | servidor que continua respondendo, que some, que volta; gravar e ler o arquivo; arquivo corrompido; endereços fora da sub-rede que **não** podem ser testados |
| Arquivos (`tests/files.rs`) | limite próprio de `/files/`, orçamento de corpos em memória, prazos longos de pedaço e de junção, Range/ETag, download em fluxo |
| WebSocket (`tests/websocket.rs`) | túnel nos dois sentidos, recusa da réplica, limites de túneis, tempo parado, encerramento |
| HTTPS (`tests/tls.rs`, `tests/selfcert.rs`, `tests/connect.rs`) | HTTP/1.1 e HTTP/2, `Host` no HTTP/2, CA própria (criação, renovação sem reiniciar, restrição de nomes), porta HTTP com HTTPS ligado, página de conexão e QR code, origem do WebSocket |
| Pareamento (`tests/pairing.rs`) | salas de seis dígitos, código mestre, bloqueios, inundação |
| Binário (`tests/binary.rs`) | configuração inválida, arquivo de configuração, `--check`, `healthcheck`, `SIGTERM` |
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
| `src/main.rs` | o programa: arquivo de configuração, `--check`, `healthcheck`, sinais |
| `src/config.rs` | variáveis de ambiente |
| `src/envfile.rs` | arquivo de configuração (`--config`) |
| `src/clientip.rs` | quem é o cliente atrás de um proxy declarado |
| `src/pool.rs` | quais réplicas estão de pé e em que ordem tentá-las |
| `src/handler.rs` | limites, `GET /server/discover/` e o proxy para as réplicas |
| `src/limiter.rs` | limites por IP |
| `src/discovery.rs` | mDNS: anúncio, busca, lista dos servidores e regras de sub-rede |
| `src/known.rs` | memória dos servidores vistos (teste de endereço e arquivo) |
| `src/proto.rs` | protobuf escrito à mão (`ErrorHttp`, `DiscoveredServers`) |
| `src/identity.rs` | id deste servidor |
| `src/websocket.rs` | túneis WebSocket |
| `src/tls.rs`, `src/certs.rs` | porta HTTPS e certificado trocável sem reiniciar (feature `tls`) |
| `src/selfcert.rs`, `src/connect.rs`, `src/pairing.rs` | CA própria, página de conexão, pareamento (feature `selfcert`) |
| `src/tray.rs` | ícone da bandeja do Windows (feature `tray`) |
| `src/server.rs` | liga tudo: porta, tarefas em segundo plano, encerramento |

## Limitações

- WebSocket só por `Upgrade` do HTTP/1.1: sobre HTTP/2 é recusado com 426 (nenhum navegador oferece).
- O HTTPS só existe nas builds com a feature `tls`/`selfcert` (a imagem Docker e a do Windows têm `selfcert`).
- O mDNS é só IPv4.
- Um servidor remoto só é achado se estiver na mesma sub-rede; o gateway não faz descoberta entre redes.
