param([Parameter(Mandatory = $true)][string]$Msi)
$ErrorActionPreference = 'Stop'
$exe  = 'C:\Program Files\PLANK Host\sunshine.exe'
$conf = 'C:\ProgramData\PLANK\host.conf'
Write-Output ("host before: " + (Get-Item $exe).VersionInfo.FileVersion + "   MSI signature: " + (Get-AuthenticodeSignature $Msi).Status)
$hashBefore = (Get-FileHash $conf).Hash
Copy-Item $conf ($conf + '.pre-' + (Get-Date -Format yyyyMMdd-HHmm) + '.bak') -Force
$p = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $Msi + '"'), '/qn', '/norestart', '/L*v', '"C:\Windows\Temp\plank-host-install.log"') -Wait -PassThru
Write-Output ("msiexec exit: " + $p.ExitCode)
Write-Output ("host after: " + (Get-Item $exe).VersionInfo.FileVersion)
Write-Output ("host.conf: " + $(if ((Get-FileHash $conf).Hash -eq $hashBefore) { 'preserved' } else { 'CHANGED (backup kept)' }))
if ((Get-Service SunshineService).Status -ne 'Running') { Start-Service SunshineService }
Start-Sleep 20
Write-Output ("service: " + (Get-Service SunshineService).Status)
Get-Content 'C:\ProgramData\PLANK\host.log' -Tail 400 | Select-String 'PLANK Host version|Found HEVC encoder|PAM authentication active|capture source probe' | Select-Object -Last 4 | ForEach-Object { $_.Line }
