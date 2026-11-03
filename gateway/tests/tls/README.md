Test-only certificate and key (self-signed, `localhost`, valid 100 years), used by `tests/tls.rs`. They protect nothing:
never use them outside the tests. Regenerate with:

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 36500 \
      -keyout key.pem -out cert.pem -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
      -addext "basicConstraints=critical,CA:FALSE" -addext "keyUsage=digitalSignature" -addext "extendedKeyUsage=serverAuth"
