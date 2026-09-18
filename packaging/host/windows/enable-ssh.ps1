<#
.SYNOPSIS
  Turns on OpenSSH Server for PLANK diagnostics on a workstation.

.DESCRIPTION
  Run from the Action1 console. The point is being able to read a host's own
  log when a stream misbehaves: a workstation is otherwise unreachable by any
  shell, and a refused layout or a black picture looks identical from outside.

  Access is restricted two ways: the firewall rule admits the office LAN only,
  never the internet, and the only key admitted is the build key held on the
  Linux box. Nothing here opens a path from outside the office, because only
  PLANK's own port is forwarded.

  Lines are kept short so copying through narrow editors cannot cut them.
#>
$ErrorActionPreference = 'Stop'

$Key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBCC/LfMpdTKVqb94qRRGFh7vw5hAn3MuEfg/SRq5e7T plank-windows-build'

# The key is the one line here that cannot be short. A truncated paste would
# otherwise be discovered later as an authentication failure with no cause.
if ($Key.Length -ne 100 -or -not $Key.EndsWith('plank-windows-build')) {
  throw "The key line was cut while pasting ($($Key.Length) of 100 characters). Paste the script again."
}

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
  Write-Output 'Installing OpenSSH Server...'
  Add-WindowsCapability -Online -Name $cap.Name | Out-Null
} else {
  Write-Output 'OpenSSH Server already installed.'
}

# Installing the capability returns before Windows registers the service, so
# on a slower machine the next line failed on a service that did not exist
# yet. Wait for it rather than assume.
$deadline = (Get-Date).AddSeconds(120)
while (-not (Get-Service sshd -EA SilentlyContinue) -and
       (Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
}
if (-not (Get-Service sshd -EA SilentlyContinue)) {
  throw ('OpenSSH installed but the sshd service has not appeared. ' +
         'This machine needs a reboot; run this again afterwards.')
}

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Output ('sshd: ' + (Get-Service sshd).Status)

# Administrators authenticate through this one file, not their profile.
$auth = 'C:\ProgramData\ssh\administrators_authorized_keys'
$existing = ''
if (Test-Path $auth) {
  $existing = Get-Content $auth -Raw
}
if ($existing -notmatch 'plank-windows-build') {
  Add-Content -Path $auth -Value $Key -Encoding ascii
  Write-Output 'Build key added.'
} else {
  Write-Output 'Build key already present.'
}

# Only Administrators and SYSTEM may read it, or sshd refuses the file.
icacls $auth /inheritance:r | Out-Null
icacls $auth /grant 'Administrators:F' | Out-Null
icacls $auth /grant 'SYSTEM:F' | Out-Null

$rule = Get-NetFirewallRule -Name 'PLANK-SSH' -ErrorAction SilentlyContinue
if (-not $rule) {
  New-NetFirewallRule -Name 'PLANK-SSH' `
    -DisplayName 'PLANK diagnostics (SSH 22, LAN only)' `
    -Enabled True -Direction Inbound -Protocol TCP `
    -LocalPort 22 -Action Allow -RemoteAddress LocalSubnet | Out-Null
  Write-Output 'Firewall rule added, office LAN only.'
} else {
  Write-Output 'Firewall rule already present.'
}

# PowerShell as the login shell, so remote commands behave as expected.
$reg = 'HKLM:\SOFTWARE\OpenSSH'
New-Item -Path $reg -Force | Out-Null
Set-ItemProperty -Path $reg -Name DefaultShell `
  -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

Write-Output 'Done.'
