#!/usr/bin/env bash
# Generate a local certificate authority and a localhost server certificate
# for HTTPS/mTLS testing of the FogCache local platform.
#
#   Bash:        scripts/gen-certs.sh
#   PowerShell:  .\scripts\gen-certs.ps1
#
# Outputs (all committed-path ignored, local only):
#   config/certs/ca.key, ca.crt            -- local CA
#   config/certs/server.key, server.crt    -- localhost server certificate
#   config/certs/ca.crt                    -- add to OS/JVM trust store to test HTTPS
#
# Requires openssl on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="$SCRIPT_DIR/../config/certs"

if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl not found on PATH. Install it and retry." >&2
    exit 1
fi

mkdir -p "$CERTS_DIR"
cd "$CERTS_DIR"

# Local CA (10 years).
openssl genrsa -out ca.key 3072
openssl req -x509 -new -key ca.key -sha256 -days 3650 -out ca.crt \
    -subj "/CN=FogCache Local CA/O=FogCache Dev"

# Server certificate for localhost with the standard local SANs.
openssl genrsa -out server.key 3072
openssl req -new -key server.key -out server.csr \
    -subj "/CN=localhost/O=FogCache Dev"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 825 -sha256 \
    -extfile <(echo "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:::1")
rm -f server.csr

echo
echo "Certificates written to $CERTS_DIR"
echo
echo "Trust setup:"
echo "  Windows:  certutil -addstore Root \"$CERTS_DIR/ca.crt\"   (admin)"
echo "  macOS:    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"$CERTS_DIR/ca.crt\""
echo "  Linux:    sudo cp \"$CERTS_DIR/ca.crt\" /usr/local/share/ca-certificates/fogcache-ca.crt && sudo update-ca-certificates"
echo "  JVM:      keytool -importcert -noprompt -cacerts -alias fogcache-local-ca -file \"$CERTS_DIR/ca.crt\""
