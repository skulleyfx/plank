<#
.SYNOPSIS
  Applies company settings to an installed PLANK Host. Meant for an Action1
  "Run Script" automation, which runs as SYSTEM.

.DESCRIPTION
  Fill in the settings below in the Action1 script editor, not in source
  control: the DUO secret key must never be committed.

  - Writes the DUO keys, DUO API host and default domain into
    %ProgramData%\PLANK\host.conf through the installed plank-host-setup.ps1,
    which keeps every other setting, the certificate and the host ID.
  - Restarts the PLANK Host service when anything changed and no one is
    streaming (otherwise the new settings apply at the next restart).
  - Optionally sets Windows display scaling to 100% for signed-in users and
    for new user profiles. Workstations with 4K display emulators default to
    225%, which makes a 2560x1440 stream look low resolution. Takes effect
    at each user's next sign-in.

  Exit codes: 0 success, 1 PLANK Host not installed, 2 settings incomplete,
  3 setup failed.
#>

# ---- Settings: edit in Action1 -------------------------------------------------
$DuoIntegrationKey = ''
$DuoSecretKey      = ''
$DuoApiHost        = ''          # api-XXXXXXXX.duosecurity.com
$DefaultDomain     = 'SKULLEYFX'
$SetDisplayScale100 = $true
# --------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$setup = Join-Path $env:ProgramFiles 'PLANK Host\tools\plank-host-setup.ps1'
$config = Join-Path $env:ProgramData 'PLANK\host.conf'

if (-not (Test-Path $setup)) {
  Write-Output 'PLANK Host is not installed; nothing to configure.'
  exit 1
}
$duoValues = @($DuoIntegrationKey, $DuoSecretKey, $DuoApiHost) | Where-Object { $_ }
if ($duoValues.Count -ne 0 -and $duoValues.Count -ne 3) {
  Write-Output 'Set all three DUO values (integration key, secret key, API host) or none.'
  exit 2
}

$before = if (Test-Path $config) { (Get-FileHash $config).Hash } else { '' }
try {
  & $setup -DuoIntegrationKey $DuoIntegrationKey -DuoSecretKey $DuoSecretKey `
           -DuoApiHost $DuoApiHost -DefaultDomain $DefaultDomain |
    Where-Object { $_ -notmatch 'duo_secret_key' }
} catch {
  Write-Output "plank-host-setup.ps1 failed: $($_.Exception.Message)"
  exit 3
}
$after = (Get-FileHash $config).Hash

$missing = @('duo_integration_key', 'duo_secret_key', 'duo_api_host') | Where-Object {
  -not (Select-String -Path $config -Pattern "^\s*$_\s*=\s*\S" -Quiet)
}
if ($missing) {
  Write-Output "Warning: host.conf has no $($missing -join ', '); DUO sign-ins will be refused."
}

if ($before -ne $after) {
  $streaming = Get-NetTCPConnection -LocalPort 28989 -State Established -ErrorAction SilentlyContinue
  if ($streaming) {
    Write-Output 'Settings changed; a stream is active, so the service will pick them up at its next restart.'
  } else {
    Restart-Service SunshineService
    Write-Output 'Settings changed; PLANK Host restarted.'
  }
} else {
  Write-Output 'Settings already current.'
}

if ($SetDisplayScale100) {
  # LogPixels 96 with Win8DpiScaling 1 is Windows' "custom scaling" at 100%,
  # applied to every monitor of that user.
  function Set-Scale100([string] $DesktopKey) {
    New-Item -Path $DesktopKey -Force | Out-Null
    Set-ItemProperty -Path $DesktopKey -Name LogPixels -Type DWord -Value 96
    Set-ItemProperty -Path $DesktopKey -Name Win8DpiScaling -Type DWord -Value 1
  }
  $users = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' }
  foreach ($user in $users) {
    Set-Scale100 "Registry::HKEY_USERS\$($user.PSChildName)\Control Panel\Desktop"
  }
  $defaultHive = 'C:\Users\Default\NTUSER.DAT'
  if (Test-Path $defaultHive) {
    & reg.exe load 'HKU\PlankDefaultProfile' $defaultHive | Out-Null
    if ($LASTEXITCODE -eq 0) {
      try {
        Set-Scale100 'Registry::HKEY_USERS\PlankDefaultProfile\Control Panel\Desktop'
      } finally {
        [GC]::Collect()
        & reg.exe unload 'HKU\PlankDefaultProfile' | Out-Null
      }
    }
  }
  Write-Output "Display scale set to 100% for $($users.Count) signed-in user(s) and new profiles; applies at next sign-in."
}
exit 0
