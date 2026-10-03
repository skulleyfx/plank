# Sign the staged PLANK client and build its MSI. Run in your own (interactive)
# PowerShell on vision - signing needs your certificate.
#   usage: powershell -ExecutionPolicy Bypass -File C:\plank-build\sign-client.ps1 -Revision 42
param([Parameter(Mandatory = $true)][int]$Revision)
$ErrorActionPreference = 'Stop'
& 'C:\plank-build\msi-src\scripts\package\sign-windows-release.ps1' -Revision $Revision -ClientOnly
