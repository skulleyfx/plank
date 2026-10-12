$exe = 'C:\Program Files\PLANK Host\tools\plank-ndi.exe'
"helper exists: " + (Test-Path $exe)
foreach ($p in 'TCP','UDP') {
  $name = "PLANK NDI helper ($p)"
  if (-not (Get-NetFirewallRule -DisplayName $name -EA SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol $p -Program $exe -Profile Domain,Private | Out-Null
  }
}
Get-NetFirewallRule -DisplayName 'PLANK NDI helper*' | Select DisplayName,Enabled,Profile | Format-Table -HideTableHeaders
"network profile: " + ((Get-NetConnectionProfile | % { $_.Name + '=' + $_.NetworkCategory }) -join ', ')
