# Image for the jobs of release-tag.yml that build the apps: ci-flutter (Flutter + Android SDK + JDK) plus the
# Linux desktop toolchain (clang, cmake, ninja, GTK, libsecret). The `sodium` plugin builds libsodium from
# source, hence the C toolchain. Build it on the runner's PC, after ci-flutter:1:
#   docker build -f .forgejo/images/ci-release.Dockerfile -t ci-release:1 .forgejo/images
FROM ci-flutter:1
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang cmake ninja-build pkg-config build-essential autoconf automake libtool \
    libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev \
 && rm -rf /var/lib/apt/lists/* \
 && flutter config --enable-linux-desktop >/dev/null \
 && flutter precache --linux >/dev/null
