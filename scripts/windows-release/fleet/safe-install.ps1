param([string]$Msi)
$lines = Get-Content C:\ProgramData\PLANK\host.log -EA SilentlyContinue
$startIdx = 0
for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match 'PLANK Host version:') { $startIdx = $i; break } }
$tail = if ($lines) { $lines[$startIdx..($lines.Count - 1)] } else { @() }
$live = @($tail | Select-String 'New streaming session started').Count - @($tail | Select-String 'native endpoint ended').Count
if ($live -gt 0) { "SKIPPED: $live live PLANK session(s)"; exit }
& C:\Windows\Temp\install-host.ps1 -Msi $Msi
