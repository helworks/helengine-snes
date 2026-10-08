[CmdletBinding()]
param(
    [switch]$Clean,
    [string]$NativeObjectCacheRoot = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$image = 'helengine-snes-toolchain'
$buildPath = Join-Path $root 'build'
$romPath = Join-Path $root 'helengine_snes.sfc'
$elfPath = Join-Path $buildPath 'helengine_snes.elf'
$mapPath = Join-Path $buildPath 'helengine_snes.map'
$manifestPath = Join-Path $root 'dependencies.json'

function Get-TextSha256([string]$Text) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath (Join-Path $root ".deps\$($manifest.toolchain.package.fileName)"))) {
    throw 'Pinned toolchain package is missing. Run scripts/setup-toolchain.ps1 first.'
}
& docker image inspect $image --format '{{.Id}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker image '$image' is missing. Run scripts/setup-toolchain.ps1 first." }

$toolchainId = (& docker image inspect $image --format '{{.Id}}').Trim()
$cacheInputs = @(
    $toolchainId,
    (Get-FileHash -LiteralPath (Join-Path $root 'Makefile') -Algorithm SHA256).Hash.ToLowerInvariant(),
    (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
) -join "`n"
$cacheFingerprint = Get-TextSha256 $cacheInputs
$objectRoot = Join-Path (Join-Path $buildPath 'native') $cacheFingerprint
$objectRootArgument = "/workspace/build/native/$cacheFingerprint"
$mounts = @('-v', "${root}:/workspace")
if (-not [string]::IsNullOrWhiteSpace($NativeObjectCacheRoot)) {
    $NativeObjectCacheRoot = [IO.Path]::GetFullPath($NativeObjectCacheRoot)
    $repoPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($NativeObjectCacheRoot.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $NativeObjectCacheRoot.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "NativeObjectCacheRoot must be outside the source checkout: $NativeObjectCacheRoot"
    }
    $objectRoot = Join-Path (Join-Path $NativeObjectCacheRoot 'snes') $cacheFingerprint
    New-Item -ItemType Directory -Path $objectRoot -Force | Out-Null
    $mounts += @('-v', "${objectRoot}:/native-cache")
    $objectRootArgument = '/native-cache'
}
$makePrefix = @('run', '--rm') + $mounts + @('-w', '/workspace', $image, 'make', "OBJECT_ROOT=$objectRootArgument")
if ($Clean) {
    & docker @($makePrefix + @('clean'))
    if ($LASTEXITCODE -ne 0) { throw 'SNES clean failed.' }
}
& docker @makePrefix
if ($LASTEXITCODE -ne 0) { throw 'SNES ROM build failed.' }

foreach ($path in @($romPath, $elfPath, $mapPath)) {
    if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) {
        throw "Expected non-empty build artifact is missing: $path"
    }
}

& python (Join-Path $root 'tools\validate_rom.py') $romPath
if ($LASTEXITCODE -ne 0) { throw 'ROM validation failed on the host.' }

$hash = (Get-FileHash -LiteralPath $romPath -Algorithm SHA256).Hash.ToLowerInvariant()
$record = [ordered]@{
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    command = "docker run ... make$(if ($Clean) { ' clean && make' })"
    rom = [ordered]@{ path = 'helengine_snes.sfc'; sha256 = $hash; bytes = (Get-Item -LiteralPath $romPath).Length }
    elf = [ordered]@{ path = 'build/helengine_snes.elf'; bytes = (Get-Item -LiteralPath $elfPath).Length }
    map = [ordered]@{ path = 'build/helengine_snes.map'; bytes = (Get-Item -LiteralPath $mapPath).Length }
    docker = [ordered]@{ toolchainImage = $toolchainId }
    dependencies = $manifest.toolchain
    video = [ordered]@{ mode = 1; layers = 'BG1'; resolution = '256x224'; cartridge = 'LoROM SlowROM 32 KiB' }
}
[System.IO.File]::WriteAllText((Join-Path $buildPath 'build-record.json'), ($record | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "ROM SHA-256: $hash"
