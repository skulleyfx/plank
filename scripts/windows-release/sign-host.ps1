# Sign the staged PLANK host and build its MSI. Run in your own (interactive)
# PowerShell on vision - signing needs your certificate.
#   usage: powershell -ExecutionPolicy Bypass -File C:\plank-build\sign-host.ps1 -Revision 42
param([Parameter(Mandatory = $true)][int]$Revision)
$ErrorActionPreference = 'Stop'
& 'C:\plank-build\msi-src\scripts\package\sign-windows-release.ps1' -Revision $Revision -HostOnly
