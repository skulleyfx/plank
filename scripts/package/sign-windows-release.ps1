<#
.SYNOPSIS
  Signs the PLANK Windows programs, builds the MSIs, then signs the MSIs.

.DESCRIPTION
  Run in an interactive session of the account that holds the code signing
  certificate: Windows only unlocks its private key there, not over SSH.

  1. Signs plank-client.exe, sunshine.exe and sunshinesvc.exe in the
     payload folders, so the installed programs are signed too.
  2. Builds both MSIs with build-windows-msi.ps1.
  3. Signs the MSIs and verifies every signature.

  Signatures are timestamped, so they stay valid after the certificate
  expires. Only a hash of each file is sent to the timestamp server.

.EXAMPLE
  .\sign-windows-release.ps1 -Revision 6
#>
param(
  [Parameter(Mandatory)] [int] $Revision,
  [string] $HostPayload = 'C:\plank-build\rebase\plank-host-pkg',
  [string] $ClientPayload = 'C:\plank-build\rebase\plank-client-pkg',
  [string] $OutputDirectory = 'C:\plank-build\msi',
  [string] $Wix = 'C:\plank-build\tools\wix\wix.exe',
  [string] $TimestampUrl = 'http://timestamp.digicert.com',
  [string] $Thumbprint = ''
)

$ErrorActionPreference = 'Stop'

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
  -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
  Where-Object FullName -match '\\x64\\' |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signtool) { throw 'signtool.exe not found (Windows SDK)' }

$now = Get-Date
$certificates = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
  Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt $now })
if ($Thumbprint) {
  $certificates = @($certificates | Where-Object Thumbprint -eq $Thumbprint)
}
if ($certificates.Count -ne 1) {
  $certificates | Format-Table Subject, Issuer, NotAfter, Thumbprint
  throw "Expected exactly one code signing certificate, found $($certificates.Count). Pass -Thumbprint."
}
$certificate = $certificates[0]
Write-Output "Signing with: $($certificate.Subject)"
Write-Output "Issuer:       $($certificate.Issuer)"
Write-Output "Expires:      $($certificate.NotAfter)"

function Invoke-Sign([string[]] $Files) {
  & $signtool.FullName sign /sha1 $certificate.Thumbprint /fd SHA256 `
    /tr $TimestampUrl /td SHA256 /d 'PLANK' $Files
  if ($LASTEXITCODE -ne 0) { throw "signtool sign failed ($LASTEXITCODE)" }
  & $signtool.FullName verify /pa /q $Files
  if ($LASTEXITCODE -ne 0) { throw "signtool verify failed ($LASTEXITCODE)" }
}

$programs = @(
  (Join-Path $ClientPayload 'plank-client.exe'),
  (Join-Path $HostPayload 'sunshine.exe'),
  (Join-Path $HostPayload 'tools\sunshinesvc.exe')
)
Write-Output '== Signing programs'
Invoke-Sign $programs

Write-Output '== Building MSIs'
$dotnet = Join-Path (Split-Path (Split-Path $Wix)) 'dotnet'
if (Test-Path (Join-Path $dotnet 'dotnet.exe')) {
  # wix.exe is a .NET tool; point it at the private runtime.
  $env:DOTNET_ROOT = $dotnet
  $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
}
$build = Join-Path $PSScriptRoot 'build-windows-msi.ps1'
& $build -HostPayload $HostPayload -ClientPayload $ClientPayload `
  -Revision $Revision -OutputDirectory $OutputDirectory -Wix $Wix

$version = (Get-Content (Join-Path $PSScriptRoot '..\..\packaging\VERSION') -Raw).Trim()
$msis = @(
  (Join-Path $OutputDirectory "plank-host-$version.$Revision.msi"),
  (Join-Path $OutputDirectory "plank-client-$version.$Revision.msi")
)
Write-Output '== Signing MSIs'
Invoke-Sign $msis

Write-Output '== Result'
foreach ($file in $programs + $msis) {
  $signature = Get-AuthenticodeSignature $file
  Write-Output ("{0,-10} {1}" -f $signature.Status, (Split-Path $file -Leaf))
}
