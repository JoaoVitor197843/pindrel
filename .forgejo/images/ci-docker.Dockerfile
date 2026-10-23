# Imagem do job de release: Docker CLI + buildx (vêm na imagem oficial) + node e git, que o actions/checkout
# precisa. O job fala com o Docker do PC pelo socket (o runner só o monta nesse label, ver .forgejo/README.md).
# Construir no PC do runner:
#   docker build -f .forgejo/images/ci-docker.Dockerfile -t ci-docker:1 .forgejo/images
FROM docker:28-cli
RUN apk add --no-cache nodejs git
