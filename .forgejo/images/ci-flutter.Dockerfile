# Imagem do runner para o CI do mobile: ci-base + Flutter pinado (mesma versão do mobile/.fvmrc).
# Construir no Raspberry Pi (arm64), com a base já existente:
#   docker build -f ci-flutter.Dockerfile -t ci-flutter:1 .
# Depois adicionar o label `ci-flutter:docker://ci-flutter:1` ao runner (ver .forgejo/README.md).
# Se mudar o FLUTTER_VERSION aqui, mude também o mobile/.fvmrc (o workflow confere os dois).
FROM ci-base:1

ARG FLUTTER_VERSION=3.44.8
ENV FLUTTER_ROOT=/opt/flutter \
    PATH=/opt/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true

# Clone raso na tag pinada; o primeiro `flutter` baixa o Dart SDK arm64 e o precache baixa
# os artefatos do engine, para os jobs não baixarem nada.
RUN git clone -q --depth 1 -b ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_ROOT} \
 && git config --system --add safe.directory ${FLUTTER_ROOT} \
 && flutter --version \
 && flutter precache --universal \
 && flutter --version | head -1
