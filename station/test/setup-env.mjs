// A test that needs a custom CA sets it itself. Host trust overrides must not leak into the fake agents' environments.
for (const key of ["SSL_CERT_FILE", "SSL_CERT_DIR", "CODEX_CA_CERTIFICATE"]) delete process.env[key];
