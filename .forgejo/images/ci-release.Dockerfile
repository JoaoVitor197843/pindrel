# Image for the jobs of release-tag.yml that build the apps: ci-flutter (Flutter + Android SDK + JDK) plus the
# Linux desktop toolchain (clang, cmake, ninja, GTK, libsecret). The `sodium` plugin builds libsodium from
# source, hence the C toolchain.
#
# It also carries the Android build caches (Gradle distribution and dependencies, NDK, CMake, pub packages), copied
# from a machine that already built the app. The PC's internet is slow (about 150 KB/s measured) and a job that
# downloaded all of that on every run took more than the 45 minutes it is allowed. Storage is cheap here, time is not.
#
# Build it on the runner's PC, after ci-flutter:1 and after one `flutter build apk --release` in mobile/ on that PC
# (which fills ~/.gradle and ~/Android/Sdk); the caches come in as named build contexts:
#   docker buildx build -f .forgejo/images/ci-release.Dockerfile -t ci-release:1 --load \
#     --build-context gradle-home=$HOME/.gradle --build-context android-sdk=$HOME/Android/Sdk \
#     --build-context pub-cache=$HOME/.pub-cache .forgejo/images
# The ndk/ and cmake/ versions below must match the ones the app asks for (the job log says "Install NDK ... v.X").
FROM ci-flutter:1
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang cmake ninja-build pkg-config build-essential autoconf automake libtool \
    libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev \
 && rm -rf /var/lib/apt/lists/* \
 && flutter config --enable-linux-desktop >/dev/null \
 && flutter precache --linux >/dev/null

COPY --from=gradle-home wrapper/dists /root/.gradle/wrapper/dists
COPY --from=gradle-home caches/modules-2 /root/.gradle/caches/modules-2
COPY --from=android-sdk ndk/28.2.13676358 /opt/android-sdk-linux/ndk/28.2.13676358
COPY --from=android-sdk cmake/3.22.1 /opt/android-sdk-linux/cmake/3.22.1
COPY --from=pub-cache hosted /root/.pub-cache/hosted
COPY --from=pub-cache hosted-hashes /root/.pub-cache/hosted-hashes
