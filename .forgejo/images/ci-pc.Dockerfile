# Imagem dos jobs que rodam no PC (label `build`): Go + Rust (com clippy e rustfmt) + node (o actions/checkout
# precisa dele) + git. Serve ao gateway (cargo), aos testes do backend com banco (go) e a qualquer job que
# precise de várias linguagens sem baixar toolchain a cada execução. Construir no PC do runner:
#   docker build -f .forgejo/images/ci-pc.Dockerfile -t ci-pc:1 .forgejo/images
FROM golang:1.26-bookworm AS go
FROM node:24-bookworm AS node
FROM rust:1-bookworm
COPY --from=go /usr/local/go /usr/local/go
COPY --from=node /usr/local/bin/node /usr/local/bin/node
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH
RUN rustup component add clippy rustfmt && go version && node --version && cargo clippy --version && rustfmt --version
