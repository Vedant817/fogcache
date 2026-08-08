# Regenerates the deterministic seed payloads (seed/fixtures/v1/payloads).
#
# Bytes are derived from the object id via repeated SHA-256, so output is
# byte-identical across machines and runs (idempotent by construction).
# Re-running this script over a committed tree must produce zero diff.

$ErrorActionPreference = 'Stop'
$version = 'v1'
$root = Join-Path $PSScriptRoot '..\fixtures'
$payloadDir = Join-Path $root "$version\payloads"
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

function Get-DeterministicBytes {
    param([string]$ObjectId, [int]$Size)
    $blocks = [Math]::Ceiling($Size / 32.0)
    $ms = New-Object System.IO.MemoryStream
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        for ($i = 0; $i -lt $blocks; $i++) {
            $hash = $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes("$ObjectId`_$i"))
            $ms.Write($hash, 0, $hash.Length)
        }
    } finally {
        $sha.Dispose()
    }
    $bytes = $ms.ToArray()
    if ($bytes.Length -gt $Size) {
        $out = New-Object byte[] $Size
        [Array]::Copy($bytes, $out, $Size)
        return $out
    }
    return $bytes
}

function Write-Payload {
    param([string]$ObjectId, [byte[]]$Bytes)
    $path = Join-Path $payloadDir "$ObjectId.bin"
    [System.IO.File]::WriteAllBytes($path, $Bytes)
    Write-Host "wrote $ObjectId.bin ($($Bytes.Length) bytes)"
}

# --- Text/JSON/HTML objects (fixed literal content) ---
$helloText = "hello from fogcache seed fixture`n"
Write-Payload 'object-hello' ([System.Text.Encoding]::UTF8.GetBytes($helloText))

Write-Payload 'object-config' ([System.Text.Encoding]::UTF8.GetBytes(
    @'
{"region":"us-east-1","tier":"standard","ttl":60,"cacheable":true}
'@))

$html = @"
<!DOCTYPE html>
<html><head><title>FogCache demo page</title></head>
<body><h1>FogCache deterministic fixture</h1>
<p>This page is generated deterministically for local demos.</p></body></html>
"@
Write-Payload 'object-page' ([System.Text.Encoding]::UTF8.GetBytes($html))

# --- Binary objects (deterministic pseudo-content) ---
Write-Payload 'object-image' (Get-DeterministicBytes 'object-image' (256 * 1024))
Write-Payload 'object-large' (Get-DeterministicBytes 'object-large' (1024 * 1024))

# --- Boundary: zero bytes ---
Write-Payload 'object-empty' ([byte[]]@())

# --- Invalid / negative fixtures ---
# object-invalid-utf8: bytes that are not valid UTF-8 (0xFF octets).
$bad = New-Object byte[] 16
$bad[0] = 0xFF; $bad[1] = 0xFE
for ($i = 2; $i -lt $bad.Length; $i++) { $bad[$i] = [byte](0x80 + ($i % 127)) }
Write-Payload 'object-invalid-utf8' $bad

# object-corrupt: payload whose manifest checksum is intentionally wrong
# (declared sha256 is for different content) -> must fail verification.
Write-Payload 'object-corrupt' (Get-DeterministicBytes 'object-corrupt' 128)

# object-over-quota: larger than tenant-quota-small (64 KiB).
Write-Payload 'object-over-quota' (Get-DeterministicBytes 'object-over-quota' (128 * 1024))

Write-Host "`nDone. Tree under $payloadDir"
