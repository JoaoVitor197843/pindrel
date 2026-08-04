FROM node:26-alpine AS frontend-builder
ARG VITE_API_URL=/api
WORKDIR /app/frontend
COPY frontend/package.json frontend/yarn.lock ./
RUN yarn install --immutable
COPY frontend/ .
RUN yarn build

FROM golang:1.26-alpine AS backend-builder
WORKDIR /app/backend
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ .
RUN CGO_ENABLED=0 go build -o server ./cmd/api

FROM alpine:latest 
WORKDIR /app
COPY --from=backend-builder /app/backend/server .
COPY --from=frontend-builder /app/frontend/dist ./public
EXPOSE 8080
CMD ["./server"]