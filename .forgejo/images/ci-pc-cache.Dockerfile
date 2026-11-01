# A layer over ci-pc with the Go module cache and the cargo registry of the PC that already built the backend and the
# gateway. The PC's internet is slow (about 150 KB/s measured) and proxy.golang.org kept cutting the HTTP/2 streams of
# `go mod download` ("stream error ... INTERNAL_ERROR"), which failed the backend job three times; with the modules in
# the image the jobs do not need the network for them. Storage is cheap here, failed releases are not.
#
# The result is tagged ci-pc:1 again, so the workflows do not change. ci-pc:base is the image without the caches
# (build it from ci-pc.Dockerfile, or tag the current one before the first time: docker tag ci-pc:1 ci-pc:base):
#   docker buildx build -f .forgejo/images/ci-pc-cache.Dockerfile -t ci-pc:1 --load \
#     --build-context go-mod=$HOME/go/pkg/mod --build-context cargo-registry=$HOME/.cargo/registry .forgejo/images
# Run `go mod download` in backend/ and `cargo fetch` in gateway/ on the PC first, so the caches are complete.
FROM ci-pc:base
COPY --from=go-mod . /root/go/pkg/mod
COPY --from=cargo-registry . /usr/local/cargo/registry
