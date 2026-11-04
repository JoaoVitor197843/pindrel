# Resultados (segunda rodada: carga mista, perda de pacotes, Flutter, WebSocket, RAM)

> Nota: o HTTP/3 medido aqui foi removido do gateway depois (decisão do dono: sem ganho que compense numa LAN). O código está no histórico do git (`gateway/src/h3.rs`, até o commit aae0cbd). Os scripts estão em `tools/https-bench/` (ver o README ao lado); os de `Alt-Svc` e de pareamento/pin desta fase foram apagados, porque o pareamento de verdade está em `gateway/src/pairing.rs` e no app.

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

# Quarta rodada: certificado sem domínio (opção 4 e comparação)

## Opção 4 (CA do próprio gateway), o que foi verificado

- **App (Dart, só com a CA do servidor, sem raízes do sistema):** pareia com o código certo; recusa o código com um caractere
  errado; recusa um impostor que responde no lugar do servidor (outra CA, mesmo código); depois de a CA ser trocada, o app
  pareado deixa de confiar até parear de novo; a renovação do certificado do servidor (mesma CA) passa sem novo pareamento.
- **Navegador (Chrome, NSS temporário):** `http://IP` não é contexto seguro (sem service worker, `crypto.subtle` nem área de
  transferência); `https://IP` sem a CA instalada não abre (`ERR_CERT_AUTHORITY_INVALID`); com a CA instalada tudo isso existe.
- **curl/OpenSSL:** HTTP/1.1, HTTP/2 e HTTP/3 com a CA própria.
- **Restrição de nomes da CA:** um certificado para `bank.example.com`, assinado de verdade com a chave da CA, é recusado
  (`permitted subtree violation`). Só nomes DNS são restritos: o BoringSSL do Dart recusa uma CA com restrição de IP
  (`unsupported name constraint type`), e um site público é alcançado por nome, não por endereço.
- Geração de CA + certificado: 19 ms (binário nativo, diretório vazio). Chaves privadas com modo 0600.

## Comparação das opções que não exigem domínio

| | Imagem/processo | RAM ociosa | RAM após 3000 pedidos | 1000 WebSockets | Renovação | App nativo | Navegador |
|---|---|---|---|---|---|---|---|
| **4. CA própria no gateway** | 7,4 MB | 0,7 MiB | 3,1 / 3,5 / 3,5 MiB (h1/h2/h3) | 28 MiB | automática (anual ou ao mudar o IP), sem reiniciar | pareia uma vez | instalar a CA uma vez por aparelho |
| 2. CA própria feita à mão (openssl/mkcert) + gateway | 7,2 MB | 0,7 MiB | 1,8 / 2,3 / 4,7 MiB | 28 MiB | manual; o gateway recarrega os arquivos | confiar na CA dentro do app | instalar a CA |
| 3. Autoassinado com fixação do certificado | 7,2 MB | 0,7 MiB | igual à 2 | igual à 2 | a fixação quebra a cada renovação ou mudança de IP | fixa o certificado, repete o pareamento | aviso a cada aparelho; sem service worker |
| nginx na frente (arquivos) | processo à parte | 3,0 MiB | 3,5 MiB | +43 MiB (só 507 abriram) | manual | como 2 | como 2 |
| Caddy `tls internal` | processo à parte | 18,7 MiB | 30,5 MiB | +96 MiB | automática (certificado de 12 h) | como 2 | como 2 |
| Nome DDNS grátis + Let's Encrypt (`lego`) + gateway | gateway + cliente ACME | 0,7 MiB + lego 10 a 12 MiB por ~1,3 s a cada ~60 dias | igual à 2 | igual à 2 | automática (cron do lego; o gateway recarrega) | confiável sem instalar nada | confiável sem instalar nada |

A última linha foi medida só até a emissão: `lego` contra o Pebble (servidor de teste do Let's Encrypt), com limite de
memória (OOM com 10 MB, ok com 12 MB) e 1,3 s por emissão. Não pedi um certificado real (depende de conta e serviço de terceiros).
