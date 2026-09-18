[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $root 'dependencies.json'
$deps = Join-Path $root '.deps'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$baseImage = $manifest.toolchain.baseImage
if ($baseImage -notmatch '^ubuntu@sha256:[0-9a-f]{64}$') {
    throw 'dependencies.json must contain an immutable Ubuntu base image digest.'
}
$package = $manifest.toolchain.package
if ([string]::IsNullOrWhiteSpace($package.url) -or [string]::IsNullOrWhiteSpace($package.fileName) -or $package.sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'dependencies.json must contain the toolchain package url, fileName and sha256.'
}

New-Item -ItemType Directory -Force -Path $deps | Out-Null
$packagePath = Join-Path $deps $package.fileName

if ($Force -or -not (Test-Path -LiteralPath $packagePath)) {
    Write-Output "Downloading $($package.url)"
    Invoke-WebRequest -Uri $package.url -OutFile $packagePath -UseBasicParsing
}

$actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $package.sha256) {
    Remove-Item -LiteralPath $packagePath -Force
    throw "Toolchain package hash mismatch: expected $($package.sha256), got $actualHash. The file was deleted."
}
Write-Output "Package hash verified: $actualHash"

$dockerArgs = @(
    'build',
    '--build-arg', "BASE_IMAGE=$baseImage",
    '--build-arg', "TOOLCHAIN_DEB=$($package.fileName)",
    '-t', 'helengine-snes-toolchain',
    '-f', (Join-Path $root 'Dockerfile'),
    $root
)
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) { throw 'SNES toolchain image build failed.' }

$toolchainImageId = (& docker image inspect helengine-snes-toolchain --format '{{.Id}}').Trim()
$compilerVersion = (& docker run --rm helengine-snes-toolchain mos-snes-clang++ --version | Select-Object -First 1).Trim()
if (-not $toolchainImageId -or -not $compilerVersion) {
    throw 'Toolchain image identity or compiler version could not be recorded.'
}

$manifest.toolchain.toolchainImage = $toolchainImageId
$manifest.toolchain.compilerVersion = $compilerVersion
[System.IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "toolchain image: $toolchainImageId"
Write-Output "compiler: $compilerVersion"
