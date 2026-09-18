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
  [string] $Thumbprint = '',
  # Ship a client without rebuilding the host: the host keeps the revision it
  # was built with, so no host MSI is produced with a version its binary does
  # not carry.
  [switch] $ClientOnly,
  # The mirror of -ClientOnly: ship a host fix without reissuing the client.
  [switch] $HostOnly
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

if ($ClientOnly -and $HostOnly) { throw 'Pass one of -ClientOnly or -HostOnly, not both' }
if ($ClientOnly) { $HostPayload = '' }
if ($HostOnly) { $ClientPayload = '' }
$programs = @()
if ($ClientPayload) {
  $programs += (Join-Path $ClientPayload 'plank-client.exe')
}
if ($HostPayload) {
  $programs += (Join-Path $HostPayload 'sunshine.exe')
  $programs += (Join-Path $HostPayload 'tools\sunshinesvc.exe')
}
# A payload left over from an earlier build carries an earlier version, and
# signing it produces an installer whose number its program does not have.
# Both numbers are known here, so refuse rather than ship the confusion.
$upstream = (Get-Content (Join-Path $PSScriptRoot '..\..\packaging\VERSION') -Raw).Trim()
foreach ($program in $programs) {
  if (-not (Test-Path $program)) { throw "Payload is missing $program" }
  $built = (Get-Item $program).VersionInfo.FileVersion
  # sunshinesvc.exe carries no version resource of its own.
  if ([string]::IsNullOrWhiteSpace($built)) { continue }
  if ($built -ne "$upstream.$Revision") {
    throw ("$(Split-Path $program -Leaf) is version $built, not $upstream.$Revision. " +
           'Stage the payload from the build you mean to sign.')
  }
}

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
$msis = @()
if ($ClientPayload) {
  $msis += (Join-Path $OutputDirectory "plank-client-$version.$Revision.msi")
}
if ($HostPayload) {
  $msis = @((Join-Path $OutputDirectory "plank-host-$version.$Revision.msi")) + $msis
}
Write-Output '== Signing MSIs'
Invoke-Sign $msis

Write-Output '== Result'
foreach ($file in $programs + $msis) {
  $signature = Get-AuthenticodeSignature $file
  Write-Output ("{0,-10} {1}" -f $signature.Status, (Split-Path $file -Leaf))
}
