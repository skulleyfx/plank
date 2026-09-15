<#
.SYNOPSIS
  Builds the PLANK Host and PLANK Client MSIs for Windows.

.EXAMPLE
  .\build-windows-msi.ps1 -HostPayload C:\build\plank-host-pkg `
      -ClientPayload C:\build\plank-client-pkg -Revision 1 -OutputDirectory C:\build\msi

  HostPayload holds sunshine.exe, tools\ and assets\. ClientPayload holds the
  deployed client (plank-client.exe and its Qt, FFmpeg and runtime DLLs).
  Requires WiX 5 (wix.exe) with the Util and Firewall extensions.
#>
param(
  [string] $HostPayload = '',
  [string] $ClientPayload = '',
  [Parameter(Mandatory)] [string] $OutputDirectory,
  [int] $Revision = 0,
  [string] $Wix = 'wix.exe'
)

$ErrorActionPreference = 'Stop'
$repository = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$upstreamVersion = (Get-Content (Join-Path $repository 'packaging\VERSION') -Raw).Trim()
if ($upstreamVersion -notmatch '^\d+\.\d+\.\d+$') { throw "packaging/VERSION is not x.y.z: $upstreamVersion" }
# Windows Installer compares the first three fields; the fourth is the
# Windows build revision of the same upstream version.
$version = "$upstreamVersion.$Revision"
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

function Invoke-Wix([string[]] $Arguments) {
  & $Wix @Arguments
  if ($LASTEXITCODE -ne 0) { throw "wix build failed ($LASTEXITCODE)" }
}

if ($HostPayload) {
  foreach ($required in 'sunshine.exe', 'tools\sunshinesvc.exe', 'assets') {
    if (-not (Test-Path (Join-Path $HostPayload $required))) { throw "host payload is missing $required" }
  }
  $hostMsi = Join-Path $OutputDirectory "plank-host-$version.msi"
  Invoke-Wix @('build', (Join-Path $repository 'packaging\host\windows\plank-host.wxs'),
    '-arch', 'x64', '-d', "Version=$version",
    '-ext', 'WixToolset.Util.wixext', '-ext', 'WixToolset.Firewall.wixext',
    '-bindpath', "payload=$HostPayload",
    '-bindpath', "setup=$(Join-Path $repository 'packaging\host\windows')",
    '-o', $hostMsi)
  Remove-Item ([IO.Path]::ChangeExtension($hostMsi, '.wixpdb')) -ErrorAction SilentlyContinue
  "built $hostMsi"
}

if ($ClientPayload) {
  if (-not (Test-Path (Join-Path $ClientPayload 'plank-client.exe'))) { throw 'client payload is missing plank-client.exe' }
  $clientMsi = Join-Path $OutputDirectory "plank-client-$version.msi"
  Invoke-Wix @('build', (Join-Path $repository 'packaging\client\windows\plank-client.wxs'),
    '-arch', 'x64', '-d', "Version=$version",
    '-bindpath', "client=$ClientPayload",
    '-bindpath', (Join-Path $repository 'packaging\client\windows'),
    '-o', $clientMsi)
  Remove-Item ([IO.Path]::ChangeExtension($clientMsi, '.wixpdb')) -ErrorAction SilentlyContinue
  "built $clientMsi"
}
