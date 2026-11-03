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
