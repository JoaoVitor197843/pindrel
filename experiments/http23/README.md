# Experimento: HTTP/2 e HTTP/3 com TLS

Branch `experiment/http2-http3-tls`. Responde: vale a pena o gateway falar TLS, HTTP/2 e HTTP/3? Não é para entrar na
`main` como está: o resultado e as pendências estão abaixo.

## O que foi feito

- `gateway/` ganhou duas features do Cargo, **desligadas por padrão** (o build normal não muda):
  - `tls`: porta extra `TLS_PORT` com HTTP/1.1 + HTTP/2 (ALPN), via `rustls` + `tokio-rustls`;
  - `http3`: o mesmo número de porta em UDP com HTTP/3 (`quinn` + `h3`), e `Alt-Svc` nas respostas TLS.
  - Variáveis: `TLS_PORT`, `TLS_CERT_FILE`, `TLS_KEY_FILE`, `HTTP3_ENABLED` (padrão `true`).
  - Mesmos limites do caminho HTTP/1.1: conexões totais e por IP, tempo de handshake, corpo máximo, limite de taxa.
    HTTP/2: 64 streams por conexão. HTTP/3: 64 streams bidirecionais, janelas de 256 KiB por stream e 1 MiB por conexão.
- `handle()` agora aceita qualquer corpo de requisição (antes só o `Incoming` do hyper).
- `tests/tls.rs` (8 testes, com certificado só de teste em `gateway/tests/tls/`): HTTP/2, HTTP/1.1 sobre TLS, 200 streams
  numa conexão, lixo e conexões mudas na porta TLS, certificado ilegível, HTTP/3, corpo grande demais, enxurrada, lixo UDP.
- `experiments/http23/`: `nginx.conf` (terminador de referência), `latproxy.mjs` (injeta RTT em TCP e UDP) e
  `pageload.mjs` (cargas a frio no Chrome por protocolo).

## WebSocket no gateway (segunda etapa)

`gateway/src/websocket.rs`: o `Upgrade` HTTP/1.1 é repassado a uma réplica e, no 101, as duas conexões são unidas byte a
byte (buffers de 4 KiB por sentido). Limites: `MAX_WEBSOCKETS` (1024), `MAX_WEBSOCKETS_PER_IP` (32, porque o túnel vive mais
que a conexão HTTP que as outras contagens enxergam), `WS_IDLE_SECS` (600), túneis fechados no desligamento. WebSocket
sobre HTTP/2 e HTTP/3 é recusado com 426 (nenhum navegador o oferece). 10 testes em `tests/websocket.rs` e 1 em `tests/tls.rs`.

## Como reproduzir

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 -keyout key.pem -out cert.pem \
      -subj "/CN=pindrel-test" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    cargo build --release --features http3
    GATEWAY_PORT=8103 TLS_PORT=8445 TLS_CERT_FILE=cert.pem TLS_KEY_FILE=key.pem UPSTREAMS=127.0.0.1:9000-9099 \
      RATE_LIMIT_ENABLED=false MDNS_ENABLED=false target/release/gateway
    node latproxy.mjs 150 9101:8101 9445:8445 9445:8445:udp &   # RTT de 150 ms
    SPKI=<sha256 base64 da chave pública> PORT_PLAIN=9101 PORT_TLS=9445 node pageload.mjs 1600 8

O throttling do DevTools limita só a banda, não as idas e voltas, que é justamente o que TLS e QUIC mudam; por isso o
`latproxy.mjs`.
