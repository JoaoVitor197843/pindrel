# Medição de HTTPS, HTTP/2 e WebSocket do gateway

Ferramentas para medir o que o HTTPS (HTTP/1.1 e HTTP/2) e o WebSocket custam no gateway, em tempo de resposta e em RAM.
Não fazem parte do produto nem do CI: servem para repetir as medições de `RESULTADOS.md` quando algo mudar (uma nova versão
do `rustls`, outro limite, outra máquina).

O HTTP/3 foi medido e **removido** do gateway de propósito (ver o fim de `RESULTADOS.md`); os scripts que ainda falam em `h3`
(`pageload.mjs`, `mixed.mjs`, `nginx.conf`, `Caddyfile`) servem para comparar com outros servidores, não com o gateway.

## O que cada um faz

| Arquivo | Para quê |
|---|---|
| `latproxy.mjs` | Proxy que injeta latência e perda de pacotes (o throttling do DevTools limita só a banda, não as idas e voltas, que é o que TLS muda). |
| `pageload.mjs` | Cargas a frio da tela de login no Chrome, por protocolo, atrás do `latproxy`. |
| `mixed.mjs` | Página mais ocupada (4 logins com Argon2, 30 chamadas pequenas, 2 scripts) ao mesmo tempo. |
| `wstest.mjs`, `wsecho.mjs`, `wsload.mjs` | WebSocket: tempo de abertura, ida e volta, rajada, e muitos túneis abertos (RAM do gateway). |
| `h2ws.mjs` | Confere que o WebSocket sobre HTTP/2 é recusado (nenhum navegador o oferece). |
| `secure.mjs` | O Chrome falando com o gateway: avisos de certificado, CSP e o que muda quando a CA é confiável. |
| `bench.dart`, `ws.dart` | O mesmo, do Dart (`dart:io`, o que o app Flutter usa). Têm `pubspec.yaml` próprio: `dart pub get` e depois `dart run bench.dart`. |
| `mkcert.sh` | Uma CA local pequena e um certificado para esta máquina, para testar HTTPS como um cliente de verdade valida. |
| `nginx.conf`, `Caddyfile` | Terminadores TLS de referência, para comparar custo de RAM e tempo com o gateway. |

## Como rodar (exemplo)

Precisa de Node com `puppeteer` (os scripts `.mjs` o importam), Chrome e, para o gateway com TLS, o Docker da raiz:

    docker compose -f compose.yml -f compose.lb.yml -f compose.tls.yml up -d --build --scale pindrel=2
    node tools/https-bench/latproxy.mjs 150 9101:8086 9445:8443 &      # 150 ms de ida e volta
    PORT_PLAIN=9101 PORT_TLS=9445 node tools/https-bench/pageload.mjs 1600 8

A RAM do gateway sai de `docker stats` (cgroup); o RSS do processo muda entre glibc e musl, e a produção é musl estático.
