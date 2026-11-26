# Image for the jobs that run on the PC (label `build`): Go + Rust (with clippy and rustfmt) + zig + node (actions/checkout
# needs it) + git. Serves the gateway (cargo), the backend tests with a database (go) and any job that
# needs several languages (includes the golang-migrate CLI, same version as go.mod) without downloading a toolchain on every run (backend, web and gateway run on it). Build it on the runner's PC:
#   docker build -f .forgejo/images/ci-pc.Dockerfile -t ci-pc:1 .forgejo/images
FROM golang:1.26-bookworm AS go
FROM node:24-bookworm AS node
FROM rust:1-bookworm
COPY --from=go /usr/local/go /usr/local/go
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH
# yarn (Berry) comes from corepack, which ships with node
# the web uses Yarn 4 (Berry), the same version as the Pi's ci-base image; downloaded here so the jobs do not download it
RUN ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && corepack enable && corepack prepare yarn@4.18.1 --activate \
 && go install -tags postgres github.com/golang-migrate/migrate/v4/cmd/migrate@v4.20.1 \
 && rustup component add clippy rustfmt && cargo install cargo-audit cargo-deny cargo-fuzz --locked && rustup toolchain install nightly --profile minimal && yarn --version && go version && node --version && cargo audit --version && cargo deny --version && cargo +nightly fuzz --help >/dev/null && cargo clippy --version && rustfmt --version && migrate -version
# zig is the C compiler of the gateway's release binaries (amd64 and arm64 musl with HTTPS: `ring` has C parts; see
# gateway/cross/zigcc). The same version Alpine gives the gateway's Dockerfile, so both builds compile ring alike.
# Its own layer, last, so adding it reuses the layers above.
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
RUN curl -fsSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
 && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz \
 && ln -s /opt/zig/zig /usr/local/bin/zig && zig version
