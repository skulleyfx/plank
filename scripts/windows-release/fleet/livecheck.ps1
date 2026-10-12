# Count live PLANK sessions since the last service start: starts minus ends.
$lines = Get-Content C:\ProgramData\PLANK\host.log
$startIdx = 0
for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match 'PLANK Host version:') { $startIdx = $i; break } }
$tail = $lines[$startIdx..($lines.Count - 1)]
$starts = @($tail | Select-String 'New streaming session started').Count
$ends = @($tail | Select-String 'native endpoint ended').Count
"since service start: sessions started=$starts ended=$ends live=$($starts - $ends)"
$tail | Select-String 'New streaming session started|native endpoint ended|viewer .* (joined|left)' | Select -Last 4 | % { '  ' + $_.Line.Substring(0,[Math]::Min(120,$_.Line.Length)) }
