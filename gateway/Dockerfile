# syntax=docker/dockerfile:1
# The gateway image is just the static binary (about 1.5 MB): no shell, no libc, no package manager.
# Build context: ./gateway (see compose.lb.yml).

FROM rust:1-alpine AS builder
RUN apk add --no-cache musl-dev
# Static binary, so it runs on `scratch`. RUSTFLAGS only reaches the target (not the proc-macros
# and build scripts) because --target is explicit.
ENV RUSTFLAGS="-C target-feature=+crt-static"
WORKDIR /app
# dependencies first, so source changes do not rebuild them
COPY Cargo.toml Cargo.lock ./
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    mkdir src && echo '' > src/lib.rs && echo 'fn main() {}' > src/main.rs \
    && cargo build --release --locked --target "$(uname -m)-unknown-linux-musl" && rm -rf src
COPY src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    touch src/lib.rs src/main.rs && cargo build --release --locked --target "$(uname -m)-unknown-linux-musl" \
    && cp "target/$(uname -m)-unknown-linux-musl/release/gateway" /gateway

FROM scratch
COPY --from=builder /gateway /gateway
# non-root: the gateway only needs ports above 1024 and UDP multicast
USER 10001:10001
ENV GATEWAY_PORT=8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD ["/gateway", "healthcheck"]
ENTRYPOINT ["/gateway"]
