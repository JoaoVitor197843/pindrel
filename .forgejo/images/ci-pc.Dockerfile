# Imagem dos jobs que rodam no PC (label `build`): Go + Rust (com clippy e rustfmt) + node (o actions/checkout
# precisa dele) + git. Serve ao gateway (cargo), aos testes do backend com banco (go) e a qualquer job que
# precise de várias linguagens (inclui o CLI golang-migrate, mesma versão do go.mod) sem baixar toolchain a cada execução (backend, web e gateway rodam nela). Construir no PC do runner:
#   docker build -f .forgejo/images/ci-pc.Dockerfile -t ci-pc:1 .forgejo/images
FROM golang:1.26-bookworm AS go
FROM node:24-bookworm AS node
FROM rust:1-bookworm
COPY --from=go /usr/local/go /usr/local/go
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH
# yarn (Berry) vem do corepack, que acompanha o node
# o web usa Yarn 4 (Berry), a mesma versão da imagem ci-base do Pi; baixada aqui para os jobs não baixarem
RUN ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && corepack enable && corepack prepare yarn@4.18.1 --activate \
 && go install -tags postgres github.com/golang-migrate/migrate/v4/cmd/migrate@v4.20.1 \
 && rustup component add clippy rustfmt && yarn --version && go version && node --version && cargo clippy --version && rustfmt --version && migrate -version
