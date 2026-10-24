# Runner image for the mobile CI: ci-base + pinned Flutter (same version as mobile/.fvmrc).
# Build it on the Raspberry Pi (arm64), with the already existing base:
#   docker build -f ci-flutter.Dockerfile -t ci-flutter:1 .
# Then add the label `ci-flutter:docker://ci-flutter:1` to the runner (see .forgejo/README.md).
# If you change FLUTTER_VERSION here, change mobile/.fvmrc too (the workflow checks both).
FROM ci-base:1

ARG FLUTTER_VERSION=3.44.8
ENV FLUTTER_ROOT=/opt/flutter \
    PATH=/opt/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true

# Shallow clone at the pinned tag; the first `flutter` downloads the arm64 Dart SDK and the precache downloads
# the engine artifacts, so the jobs download nothing.
RUN git clone -q --depth 1 -b ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_ROOT} \
 && git config --system --add safe.directory ${FLUTTER_ROOT} \
 && flutter --version \
 && flutter precache --universal \
 && flutter --version | head -1
