# Build and stage the PLANK Windows host on vision.
#   usage: powershell -ExecutionPolicy Bypass -File C:\plank-build\build-host.ps1 -Revision 42
# Source comes from C:\plank-build\hostsrc.tgz (made by make-hostsrc.sh on wopr).
# Stops with an error, and does not stage, if the build fails or the version is wrong.
param([Parameter(Mandatory = $true)][int]$Revision)
$ErrorActionPreference = 'Stop'

$base = (Get-Content C:\plank-build\msi-src\packaging\VERSION -Raw).Trim()
$version = "$base.$Revision"
$commit = if (Test-Path C:\plank-build\hostsrc.commit) { (Get-Content C:\plank-build\hostsrc.commit -Raw).Trim() } else { 'unknown' }
Write-Output "=== building PLANK host $version from commit $commit ==="

Write-Output '=== [1/4] clean old source ==='
Remove-Item -Recurse -Force C:\plank-build\rebase\host\* -EA SilentlyContinue

if (Test-Path C:\plank-build\transportsrc.tgz) {
  Write-Output '=== [1b] install plank-transport source ==='
  $transportRoot = 'C:\plank-build\rebase\plank'
  $snapshot = 'C:\plank-build\rebase\plank.snapshot-0914'
  if ((Test-Path $transportRoot) -and -not (Test-Path $snapshot)) { Move-Item $transportRoot $snapshot }
  Remove-Item -Recurse -Force $transportRoot -EA SilentlyContinue
  New-Item -ItemType Directory -Force $transportRoot | Out-Null
  tar -xzf C:\plank-build\transportsrc.tgz -C $transportRoot
  if (-not (Test-Path "$transportRoot\protocol\plank-transport\Cargo.toml")) { throw "transport source did not unpack. Do NOT sign." }
  # The build compiles the transport with cargo --offline, so download its
  # locked dependencies first.
  $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
  Push-Location "$transportRoot\protocol\plank-transport"
  # Through cmd: cargo reports progress on stderr, which strict PowerShell
  # would treat as a failure.
  cmd /c "cargo fetch --locked 2>&1" | Select-Object -Last 2
  $fetchExit = $LASTEXITCODE
  Pop-Location
  if ($fetchExit -ne 0) { throw "cargo fetch failed for the transport. Do NOT sign." }
}

Write-Output '=== [2/4] extract + configure + build ==='
& C:\plank-build\hostrebuild.ps1 -Version $version

$exe = Get-Item C:\plank-build\rebase\host-build\sunshine.exe
Write-Output ("built sunshine.exe: {0}  {1}" -f $exe.VersionInfo.FileVersion, $exe.LastWriteTime)
if ($exe.LastWriteTime -lt (Get-Date).AddMinutes(-90)) {
  throw "sunshine.exe was not freshly built. The build likely FAILED; see C:\plank-build\rebase\host-build\build.log. Do NOT sign."
}
if ($exe.VersionInfo.FileVersion -ne $version) {
  throw ("built version is " + $exe.VersionInfo.FileVersion + ", expected " + $version + ". See reconfigure.log. Do NOT sign.")
}

Write-Output '=== [3/4] stage payload ==='
& C:\plank-build\packhost2.ps1

Write-Output '=== [4/4] check staged version ==='
$staged = (Get-Item C:\plank-build\rebase\plank-host-pkg\sunshine.exe).VersionInfo.FileVersion
if ($staged -ne $version) { throw ("staged version is " + $staged + ", expected " + $version + ". Do NOT sign.") }

Write-Output ''
Write-Output "BUILD + STAGE OK: PLANK host $version (commit $commit)"
Write-Output "NEXT:  powershell -ExecutionPolicy Bypass -File C:\plank-build\sign-host.ps1 -Revision $Revision"
