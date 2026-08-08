# Generate a local certificate authority and a localhost server certificate
# for HTTPS/mTLS testing of the FogCache local platform.
#
#   PowerShell:  .\scripts\gen-certs.ps1
#   Bash:        scripts/gen-certs.sh
#
# Outputs (all committed-path ignored, local only):
#   config/certs/ca.key, ca.crt            -- local CA
#   config/certs/server.key, server.crt    -- localhost server certificate
#   config/certs/ca.crt                    -- add to OS/JVM trust store to test HTTPS
#
# Requires openssl on PATH.

$ErrorActionPreference = "Stop"

$certsDir = Join-Path $PSScriptRoot "..\config\certs"

function Fail($message) {
    Write-Error $message
    exit 1
}

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    Fail "openssl not found on PATH. Install it (e.g. 'choco install openssl' on Windows, 'brew install openssl' on macOS) and retry."
}

New-Item -ItemType Directory -Force -Path $certsDir | Out-Null
Push-Location $certsDir
try {
    # Local CA (10 years).
    openssl genrsa -out ca.key 3072 2>$null
    openssl req -x509 -new -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=FogCache Local CA/O=FogCache Dev" 2>$null

    # Server certificate for localhost with the standard local SANs.
    openssl genrsa -out server.key 3072 2>$null
    openssl req -new -key server.key -out server.csr -subj "/CN=localhost/O=FogCache Dev" 2>$null
    $extFile = Join-Path $env:TEMP "fogcache-csr-ext.cnf"
    Set-Content -Path $extFile -Value "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:::1"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 825 -sha256 -extfile $extFile 2>$null
    Remove-Item server.csr, $extFile -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Certificates written to $certsDir"
    Write-Host ""
    Write-Host "Trust setup:"
    Write-Host "  Windows:  certutil -addstore Root ""$certsDir\ca.crt""   (admin)"
    Write-Host "  macOS:    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ""$certsDir\ca.crt"""
    Write-Host "  Linux:    sudo cp ""$certsDir\ca.crt"" /usr/local/share/ca-certificates/fogcache-ca.crt && sudo update-ca-certificates"
    Write-Host "  JVM:      keytool -importcert -noprompt -cacerts -alias fogcache-local-ca -file ""$certsDir\ca.crt"""
}
finally {
    Pop-Location
}
