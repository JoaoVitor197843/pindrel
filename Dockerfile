# syntax=docker/dockerfile:1
# RAM budget: ceiling 512 MB, recommended 256 MB per instance, database included (see compose.yml).
# Build tools never reach the final image: only the stripped Go binary and the static web build.
# Multi-arch (amd64 + arm64) from a single machine WITHOUT emulation: the build stages always run on the
# build machine ($BUILDPLATFORM) and Go cross-compiles; the final stage has no RUN, so nothing executes
# as the target architecture.

FROM --platform=$BUILDPLATFORM node:24-alpine AS frontend-builder
WORKDIR /app/frontend
COPY web/package.json web/yarn.lock web/.yarnrc.yml ./
RUN --mount=type=cache,target=/root/.yarn/berry/cache yarn install --immutable
COPY web/ .
RUN yarn build

FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS backend-builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /app/backend
COPY backend/go.mod backend/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY backend/ .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o server ./cmd/api

FROM alpine:3.24
WORKDIR /app
COPY --from=backend-builder /app/backend/server .
COPY --from=frontend-builder /app/frontend/dist ./public
# numeric non-root user: no adduser, which would be a RUN as the target architecture
USER 10001:10001
# Go soft memory limit, below the 128m container limit set in compose.yml
ENV GOMEMLIMIT=100MiB
EXPOSE 8080
# start-interval: while starting (start-period) it probes every 1 s instead of the default 5 s, so a new replica is
# seen healthy as soon as it answers (it speeds up rolling updates). The start-period is generous because, once it ends,
# the next probe is --interval (30 s) away: a slow device that took longer than the period would wait that long.
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --start-interval=1s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-8080}/" || exit 1
CMD ["./server"]
