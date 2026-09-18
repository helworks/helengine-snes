[CmdletBinding()]
param(
    [string]$RomPath = '',
    [string]$MesenPath = 'C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe',
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($RomPath)) { $RomPath = Join-Path $root 'helengine_snes.sfc' }
$rom = (Resolve-Path -LiteralPath $RomPath).Path
if ((Get-Item -LiteralPath $rom).Length -le 0) { throw "ROM artifact is empty: $rom" }
if ([System.IO.Path]::GetExtension($rom) -ine '.sfc') { throw "Expected a .sfc artifact: $rom" }

$mesen = (Resolve-Path -LiteralPath $MesenPath).Path
$portableSettings = Join-Path (Split-Path -Parent $mesen) 'settings.json'
if (-not (Test-Path -LiteralPath $portableSettings)) {
    throw "MesenCE needs a portable settings.json next to Mesen.exe or its first-run wizard blocks test-runner mode. Create '$portableSettings' containing {} and retry."
}

# Resolve the frame counter's WRAM address from the linker map so the Lua
# check can prove the VBlank NMI is firing. The symbol must be found; a
# missing map or symbol means the check cannot prove anything, so it is fatal.
$mapPath = Join-Path $root 'build\helengine_snes.map'
if (-not (Test-Path -LiteralPath $mapPath)) {
    throw "Linker map not found: $mapPath; run the build first."
}
$counterAddress = 0
foreach ($line in Get-Content -LiteralPath $mapPath) {
    if ($line -match '^\s*([0-9a-fA-F]+)\s+[0-9a-fA-F]+\s+[0-9a-fA-F]+\s+\d+\s+HelengineSnesFrameCounter\s*$') {
        $counterAddress = [Convert]::ToInt32($Matches[1], 16)
        break
    }
}
if ($counterAddress -eq 0) {
    throw "Frame counter symbol HelengineSnesFrameCounter not found in $mapPath; run the build first."
}

$template = Get-Content -LiteralPath (Join-Path $root 'tools\mesen\red_square_check.lua') -Raw
$generatedDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$generatedLua = Join-Path $generatedDir 'red_square_check.generated.lua'
[System.IO.File]::WriteAllText($generatedLua, $template.Replace('__FRAME_COUNTER_ADDRESS__', [string]$counterAddress), (New-Object System.Text.UTF8Encoding($false)))

Write-Output "ROM=$rom"
Write-Output "FRAME_COUNTER_ADDRESS=0x$($counterAddress.ToString('X4'))"
$process = Start-Process -FilePath $mesen -ArgumentList @('--testrunner', "--timeout=$TimeoutSeconds", "`"$rom`"", "`"$generatedLua`"") -PassThru -Wait -WindowStyle Hidden
$code = $process.ExitCode
switch ($code) {
    0 { Write-Output 'RESULT=pass (red centre, black corners, frame counter advancing)' }
    2 { Write-Output 'RESULT=fail (Lua error inside the check)' }
    3 { Write-Output 'RESULT=fail (wrong colours)' }
    4 { Write-Output 'RESULT=fail (frame counter did not advance; NMI not firing)' }
    5 { Write-Output 'RESULT=fail (frame counter address unresolved)' }
    default { Write-Output "RESULT=fail (MesenCE exit code $code; timeout or ROM did not load)" }
}
exit $code
