# syntax=docker/dockerfile:1
# The gateway image is just the static binary (about 1.5 MB): no shell, no libc, no package manager.
# Build context: ./gateway (see compose.lb.yml).
# Multi-arch (amd64 + arm64) from a single machine WITHOUT emulation: the builder always runs on the build
# machine ($BUILDPLATFORM) and cross-compiles to musl; rust-lld links the arm64 target (see .cargo/config.toml).

FROM --platform=$BUILDPLATFORM rust:1-alpine AS builder
ARG TARGETARCH
# What the gateway can do besides the plain proxy: `selfcert` is HTTPS with its own certificate authority (+ the pairing
# page), off until TLS_AUTO is set. `--build-arg FEATURES=` builds the plain gateway (no TLS code at all).
ARG FEATURES=selfcert
# `ring` (TLS) has C and assembly parts, so the TARGET needs a C compiler. zig carries the musl headers and libraries of
# every target, which lets the arm64 build (a Raspberry Pi) run on the amd64 builder with no emulation and no cross gcc.
RUN apk add --no-cache musl-dev zig
ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global ZIG_LOCAL_CACHE_DIR=/tmp/zig-local
# The compiler and archiver the arm64 build uses (see cross/zigcc-aarch64).
COPY cross/zigcc-aarch64 cross/zigar /usr/local/bin/
ENV CC_aarch64_unknown_linux_musl=/usr/local/bin/zigcc-aarch64 AR_aarch64_unknown_linux_musl=/usr/local/bin/zigar
WORKDIR /app
# .cargo/config.toml carries the flags of the aarch64 target (static + pic + rust-lld). The x86_64 target gets
# the same static flag through the environment; RUSTFLAGS is NOT set globally because it would override the
# config file and the arm64 binary linked without them segfaulted on a real Pi 4.
COPY .cargo ./.cargo
RUN case "$TARGETARCH" in \
      amd64) echo x86_64-unknown-linux-musl ;; \
      arm64) echo aarch64-unknown-linux-musl ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac > /rust-target \
 && rustup target add "$(cat /rust-target)"
ENV CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_RUSTFLAGS="-C target-feature=+crt-static"
# dependencies first, so source changes do not rebuild them
COPY Cargo.toml Cargo.lock ./
# One registry cache per target: buildx builds amd64 and arm64 at the same time, and two cargo processes unpacking the same crate
# into one shared cache failed with "failed to unpack package ... .cargo-ok: File exists" (GitHub run 41782918100).
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry-${TARGETARCH} \
    mkdir src && echo '' > src/lib.rs && echo 'fn main() {}' > src/main.rs \
    && cargo build --release --locked --target "$(cat /rust-target)" ${FEATURES:+--features "$FEATURES"} && rm -rf src
COPY src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry-${TARGETARCH} \
    touch src/lib.rs src/main.rs && cargo build --release --locked --target "$(cat /rust-target)" ${FEATURES:+--features "$FEATURES"} \
    && cp "target/$(cat /rust-target)/release/gateway" /gateway

# /data holds the id of this server (and the servers it remembers) between restarts; the volume mounted there starts
# with this owner, so the non-root user can write it (scratch has no mkdir)
RUN mkdir /data && chown 10001:10001 /data

FROM scratch
COPY --from=builder /gateway /gateway
COPY --from=builder --chown=10001:10001 /data /data
# non-root: the gateway only needs ports above 1024 and UDP multicast
USER 10001:10001
ENV GATEWAY_PORT=8080
# start-interval: probes every 1 s during the start-period (default 5 s), so recreating the gateway cuts for less time
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --start-interval=1s --retries=3 CMD ["/gateway", "healthcheck"]
ENTRYPOINT ["/gateway"]
