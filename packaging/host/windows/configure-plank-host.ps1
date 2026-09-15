<#
.SYNOPSIS
  Applies company settings to an installed PLANK Host.
  Meant for an Action1 "Run Script" automation (runs as SYSTEM).

.DESCRIPTION
  Fill in the settings in the Action1 script editor, never in source
  control: the DUO secret key must not be committed.

  - Writes the DUO keys, DUO API host and default domain into
    %ProgramData%\PLANK\host.conf through the installed
    plank-host-setup.ps1, which keeps every other setting, the
    certificate and the host ID.
  - Restarts PLANK Host when anything changed and no one is streaming.
  - Optionally sets display scaling to 100% for signed-in users and new
    profiles (4K display emulators default to 225%). Applies at next
    sign-in.

  Lines are kept short so copying through narrow editors cannot cut them.

  Exit codes: 0 success, 1 PLANK Host not installed,
  2 settings incomplete, 3 setup failed.
#>

# ---- Settings: edit in Action1 --------------------------------------
$DuoIntegrationKey  = 'XXXX'
$DuoSecretKey       = 'XXXX'
$DuoApiHost         = 'api-XXXX.duosecurity.com'
$DefaultDomain      = 'SKULLEYFX'
$SetDisplayScale100 = $true
# ----------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$tools = Join-Path $env:ProgramFiles 'PLANK Host\tools'
$setup = Join-Path $tools 'plank-host-setup.ps1'
$config = Join-Path $env:ProgramData 'PLANK\host.conf'

if (-not (Test-Path $setup)) {
  Write-Output 'PLANK Host is not installed.'
  exit 1
}

$duo = @($DuoIntegrationKey, $DuoSecretKey, $DuoApiHost)
$filled = @($duo | Where-Object { $_ })
if ($filled.Count -ne 0 -and $filled.Count -ne 3) {
  Write-Output 'Set all three DUO values, or none.'
  exit 2
}
if ($duo -match 'XXXX') {
  Write-Output 'Replace the XXXX placeholders first.'
  exit 2
}

$before = ''
if (Test-Path $config) {
  $before = (Get-FileHash $config).Hash
}

try {
  $output = & $setup `
    -DuoIntegrationKey $DuoIntegrationKey `
    -DuoSecretKey $DuoSecretKey `
    -DuoApiHost $DuoApiHost `
    -DefaultDomain $DefaultDomain
  $output | Write-Output
} catch {
  Write-Output "Setup failed: $($_.Exception.Message)"
  exit 3
}

$after = (Get-FileHash $config).Hash

$keys = 'duo_integration_key', 'duo_secret_key', 'duo_api_host'
foreach ($key in $keys) {
  $pattern = "^\s*$key\s*=\s*\S"
  if (-not (Select-String -Path $config -Pattern $pattern -Quiet)) {
    Write-Output "Warning: $key is not set."
    Write-Output 'DUO sign-ins will be refused.'
  }
}

if ($before -eq $after) {
  Write-Output 'Settings already current.'
} else {
  $active = Get-NetTCPConnection -LocalPort 28989 `
    -State Established -ErrorAction SilentlyContinue
  if ($active) {
    Write-Output 'Settings changed. Stream active.'
    Write-Output 'They apply at the next host restart.'
  } else {
    Restart-Service SunshineService
    Write-Output 'Settings changed. PLANK Host restarted.'
  }
}

if ($SetDisplayScale100) {
  # LogPixels 96 + Win8DpiScaling 1 = custom scaling at 100%.
  function Set-Scale100([string] $Key) {
    New-Item -Path $Key -Force | Out-Null
    Set-ItemProperty -Path $Key -Name LogPixels `
      -Type DWord -Value 96
    Set-ItemProperty -Path $Key -Name Win8DpiScaling `
      -Type DWord -Value 1
  }

  $hku = 'Registry::HKEY_USERS'
  $users = Get-ChildItem $hku | Where-Object {
    $_.PSChildName -match '^S-1-5-21-[\d-]+$'
  }
  foreach ($user in $users) {
    Set-Scale100 "$hku\$($user.PSChildName)\Control Panel\Desktop"
  }

  $hive = 'C:\Users\Default\NTUSER.DAT'
  if (Test-Path $hive) {
    & reg.exe load 'HKU\PlankDefault' $hive | Out-Null
    if ($LASTEXITCODE -eq 0) {
      try {
        Set-Scale100 "$hku\PlankDefault\Control Panel\Desktop"
      } finally {
        [GC]::Collect()
        & reg.exe unload 'HKU\PlankDefault' | Out-Null
      }
    }
  }
  $count = @($users).Count
  Write-Output "Display scale 100% set for $count user(s)."
  Write-Output 'It applies at next sign-in.'
}

Write-Output 'Done.'
exit 0
