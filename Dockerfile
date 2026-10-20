# syntax=docker/dockerfile:1
# RAM budget: ceiling 512 MB, recommended 256 MB per instance, database included (see compose.yml).
# Build tools never reach the final image: only the stripped Go binary and the static web build.

FROM node:24-alpine AS frontend-builder
WORKDIR /app/frontend
COPY web/package.json web/yarn.lock web/.yarnrc.yml ./
RUN --mount=type=cache,target=/root/.yarn/berry/cache yarn install --immutable
COPY web/ .
RUN yarn build

FROM golang:1.26-alpine AS backend-builder
WORKDIR /app/backend
COPY backend/go.mod backend/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY backend/ .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o server ./cmd/api

FROM alpine:3.24
RUN addgroup -S plany && adduser -S -G plany plany
WORKDIR /app
COPY --from=backend-builder /app/backend/server .
COPY --from=frontend-builder /app/frontend/dist ./public
USER plany
# Go soft memory limit, below the 128m container limit set in compose.yml
ENV GOMEMLIMIT=100MiB
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-8080}/" || exit 1
CMD ["./server"]
