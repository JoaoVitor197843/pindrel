# Release job image: Docker CLI + buildx (they come in the official image) + node and git, which actions/checkout
# needs. The job talks to the PC's Docker through the socket (the runner only mounts it on that label, see .forgejo/README.md).
# Build it on the runner's PC:
#   docker build -f .forgejo/images/ci-docker.Dockerfile -t ci-docker:1 .forgejo/images
FROM docker:28-cli
RUN apk add --no-cache nodejs git
