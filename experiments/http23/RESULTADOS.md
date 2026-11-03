# Resultados (segunda rodada: carga mista, perda de pacotes, Flutter, WebSocket, RAM)

Máquina de desenvolvimento, Chrome 156 headless, gateway Rust do branch, réplicas Go reais. Latência e perda vêm de
`latproxy.mjs` (TCP: perda vira atraso por timeout com a ordem mantida, ou seja, bloqueio de cabeça de fila, sem
colapso da janela de congestionamento, então o TCP aparece **otimista** sob perda; UDP: o datagrama é descartado).
Medianas de 6 a 8 cargas a frio; "tudo" = 4 logins (Argon2) + 30 chamadas pequenas + 2 scripts, todos ao mesmo tempo.

## Navegador: carga mista (tempo para tudo terminar)

| Rede | HTTP/1.1 sem TLS (hoje) | HTTP/1.1 + TLS | HTTP/2 | HTTP/3 |
|---|---|---|---|---|
| RTT 40 ms | 388 ms | 422 ms | 159 ms | 118 ms |
| RTT 40 ms, perda 2% | 599 ms | 589 ms | 331 ms | 153 ms |
| RTT 40 ms, perda 5% | 656 ms | 707 ms | 486 ms | 504 ms |
| RTT 150 ms | 1208 ms | 1311 ms | 436 ms | 418 ms |
| RTT 150 ms, perda 2% | 1505 ms | 1626 ms | 631 ms | 651 ms |
| RTT 150 ms, perda 5% | 1653 ms | 1780 ms | 910 ms | 1418 ms |

## Flutter / Dart (AOT, mesma carga, `dart:io` HttpClient e `package:http2`)

| Rede | h1 sem TLS | h1 + TLS | h2 (p95 de 1 pedido) | RAM de pico do processo (h1 / h1+TLS / h2) |
|---|---|---|---|---|
| RTT 40 ms | 143 ms | 192 ms | 138 ms | 17 / 27 / 13 MiB |
| RTT 150 ms (JIT) | 345 ms | 519 ms | 363 ms | n/a |

`dart:io` não fala HTTP/2 nem HTTP/3. Abre ~36 sockets em paralelo (sem o limite de 6 do navegador), por isso o h1 já é
rápido no app. HTTP/3 em Flutter exige plugin nativo (`cronet_http` no Android, `cupertino_http` no iOS/macOS); não testado.

## RAM dos terminadores de TLS

| | ocioso | 3000 pedidos (50 em paralelo) | 1000 WebSockets ociosos |
|---|---|---|---|
| gateway Rust com `tls`/`http3` (acréscimo) | +1,3 / +1,9 MiB | +0,1 / +2,9 MiB | sem suporte a WebSocket |
| nginx | 3,0 MiB | 3,5 MiB | 507 abertas (limite de 1024 conexões): +43 MiB |
| Caddy | 18 MiB | 30 a 36 MiB (fica em 33) | 1000 abertas: +96 MiB (e não devolve) |

## WebSocket (RTT 80 ms)

Abrir: 165 ms sem TLS, 288 ms com TLS (uma ida e volta a mais). Ida e volta de uma mensagem: 82 ms em todos (= a rede).
300 mensagens de uma vez: ~140 ms em todos. Mesmo com h2/h3 permitidos, o Chrome usou `HTTP/1.1 101` (log do Caddy);
nenhum terminador testado anuncia `SETTINGS_ENABLE_CONNECT_PROTOCOL` (RFC 8441), então o WebSocket segue HTTP/1.1.
O gateway atual não faz upgrade: `ws://` e `wss://` falham (também no Dart).

# Terceira rodada: WebSocket no gateway, HTTPS validado de verdade, imagens de produção

## HTTPS validado como um cliente real (`mkcert.sh`: CA local + certificado com `localhost`, `127.0.0.1` e o IP da LAN)

curl e Dart (`SecurityContext` só com a CA do teste): aceitam por `localhost`, `127.0.0.1` e pelo IP da LAN, em HTTP/1.1,
HTTP/2 e HTTP/3. Recusam (curl: código 60; Dart: `CERTIFICATE_VERIFY_FAILED`): sem a CA (`unable to get local issuer
certificate`), nome fora do certificado (`IP address mismatch`) e certificado vencido (`certificate has expired`).

## RAM (imagens Docker musl, as de produção; cgroup)

| | imagem | ocioso | após 3000 pedidos | 1000 WebSockets abertos | depois de fechar |
|---|---|---|---|---|---|
| gateway atual + WebSocket (sem TLS) | 3,8 MB | 0,4 MiB | 2,1 MiB | 22,8 MiB | 2,9 MiB |
| `--features http3` (TLS, h2, h3) | 7,2 MB | 0,7 MiB | 1,8 / 2,3 / 4,7 MiB (h1 / h2 / h3) | 28,2 MiB | 2,1 MiB |

No binário musl estático fora do Docker (RSS): 2,2 MiB ocioso, 16,2 MiB com 1000 WebSockets (~14 KB cada), 4,5 MiB depois,
igual em 3 rodadas. No glibc o RSS não volta (fica em 47 a 49 MiB depois de rajadas de 1000, sem vazar descritores:
é o alocador), por isso as medidas do build de produção são as da tabela. Para comparação, 1000 WebSockets em nginx
custaram +43 MiB (507 conexões) e em Caddy +96 MiB.

## WebSocket (RTT 80 ms, Chrome)

Pelo gateway: 165 ms para abrir sem TLS, 288 ms com TLS; ida e volta de 82 ms; 300 mensagens em ~140 ms. Idêntico a
nginx e Caddy: o gateway não soma latência mensurável.

## Carga mista, imagens de produção (tempo para tudo terminar)

| Rede | h1 sem TLS | h1 + TLS | h2 | h3 |
|---|---|---|---|---|
| RTT 40 ms | 436 ms | 441 ms | 222 ms | 145 ms |
| RTT 40 ms, perda 2% | 593 ms | 646 ms | 369 ms | 206 ms |
| RTT 150 ms | 1226 ms | 1321 ms | 453 ms | 414 ms |
| RTT 150 ms, perda 2% | 1454 ms | 1550 ms | 865 ms | 915 ms |

## Limites encontrados

- Docker abre contêineres com 1024 descritores: com 1000 WebSockets simultâneos só 14 abriram (os sockets de entrada
  consomem a tabela antes de o gateway conseguir abrir os da réplica). `compose.lb.yml` agora define `nofile: 8192` e o
  gateway avisa no início se o limite é baixo para as suas configurações.
- Compilar com TLS para `arm64` a partir de uma máquina amd64 (o pipeline de release) falha:
  `failed to find tool "aarch64-linux-musl-gcc"` (o `ring` precisa de compilador C). Para amd64 funciona.
- Descoberta de HTTP/3 por `Alt-Svc` sem forçar: o gateway envia `alt-svc: h3=":PORTA"; ma=86400` (coberto por teste), mas
  o Chrome headless ficou em HTTP/2 nas 5 visitas, mesmo com a CA confiável num NSS temporário e com nome de domínio.
  Não consegui confirmar a troca automática; com `--origin-to-force-quic-on` o HTTP/3 funciona.
