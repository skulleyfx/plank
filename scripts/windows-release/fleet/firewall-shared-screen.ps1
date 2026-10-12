$name = 'PLANK Host shared screen viewers (UDP 28990-28997)'
if (-not (Get-NetFirewallRule -DisplayName $name -EA SilentlyContinue)) {
  New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol UDP -LocalPort '28990-28997' -Program 'C:\Program Files\PLANK Host\sunshine.exe' -Profile Any | Out-Null
}
Get-NetFirewallRule -DisplayName $name | Select DisplayName,Enabled,Action | Format-List
Get-NetFirewallRule -DisplayName $name | Get-NetFirewallPortFilter | Select Protocol,LocalPort | Format-List
