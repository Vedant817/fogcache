<#
.SYNOPSIS
Documentation smoke test: verifies that commands and links used in the
developer docs resolve to real things.

Checks:
  1. Every `fogcache.ps1 <command>` example is a valid script command.
  2. Every `traffic-gen.py --scenario <name>` example is a valid scenario.
  3. Every relative markdown link under docs/ points to an existing file.

Exit code 0 = all good; 1 = at least one stale reference.
Run from the repository root:  pwsh docs/tools/check-docs.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
Set-Location $root

$docFiles = @(
    'docs/onboarding.md',
    'docs/development.md'
)

$fogcacheCommands = @('bootstrap', 'up', 'status', 'smoke', 'reset', 'teardown', 'down')
$trafficScenarios = @('uniform', 'zipfian', 'burst', 'sequential', 'regional', 'invalidation', 'origin-fault')

$failures = @()

foreach ($file in $docFiles) {
    $text = Get-Content $file -Raw

    # 1. fogcache.ps1 command examples (also catches the sh shim, which uses
    #    the same command set).
    foreach ($m in [regex]::Matches($text, 'fogcache(?:\.ps1|\.sh)\s+([a-z]+)')) {
        if ($fogcacheCommands -notcontains $m.Groups[1].Value) {
            $failures += "$file`: unknown fogcache command '$($m.Groups[1].Value)'"
        }
    }

    # 2. traffic-gen scenario examples.
    foreach ($m in [regex]::Matches($text, 'traffic-gen\.py --scenario\s+([a-z-]+)')) {
        if ($trafficScenarios -notcontains $m.Groups[1].Value) {
            $failures += "$file`: unknown traffic scenario '$($m.Groups[1].Value)'"
        }
    }
}

# 3. Relative markdown links in every docs file (docs/**/*.md) must resolve.
Get-ChildItem docs -Recurse -Filter '*.md' | ForEach-Object {
    $file = $_
    $dir = $file.DirectoryName
    foreach ($m in [regex]::Matches((Get-Content $file.FullName -Raw), '\]\(([^)]+)\)')) {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?://|#|mailto:)') { continue }
        $path = ($target -split '#')[0]
        if (-not $path) { continue }
        $resolved = Join-Path $dir $path
        if (-not (Test-Path -LiteralPath $resolved)) {
            $failures += "$($file.FullName.Substring($root.Length + 1)): broken link '$target'"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'DOCS CHECK FAILED:'
    $failures | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'DOCS CHECK PASSED: fogcache commands, traffic scenarios, and markdown links all resolve.'
