[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [string]$EmulatorPath = 'C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe',
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
$artifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
if ((Get-Item -LiteralPath $artifact).Length -le 0) { throw "ROM artifact is empty: $artifact" }
if ([System.IO.Path]::GetExtension($artifact) -ine '.sfc') { throw "Expected a .sfc artifact: $artifact" }

$emulator = (Resolve-Path -LiteralPath $EmulatorPath).Path
if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) { throw "Emulator executable does not exist: $emulator" }

# Both MesenCE and ares take the ROM path as their positional argument.
$windowStyle = if ($Visible) { 'Normal' } else { 'Minimized' }
Start-Process -FilePath $emulator -ArgumentList @("`"$artifact`"") -WindowStyle $windowStyle
Write-Output "EMULATOR=$emulator"
Write-Output "ARTIFACT=$artifact"
