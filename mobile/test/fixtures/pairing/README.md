Test-only CAs and server certificates (valid 100 years, name-constrained to `localhost` and `.lan` like the gateway's CA),
used by `test/core/network/pairing_test.dart`. The CA keys were deleted after signing. They protect nothing.
Regenerate: EC P-256 CA with `nameConstraints=critical,permitted;DNS:localhost,permitted;DNS:lan`, server certificate with
`subjectAltName=DNS:localhost,IP:127.0.0.1`.
