# Fleet host scripts (Windows PLANK hosts)

Run on a host over SSH (PowerShell shell). Copy the script and the signed MSI to `C:\Windows\Temp` first, e.g.
`scp plank-host-1.0.103.51.msi safe-install.ps1 install-host.ps1 <user>@<host>:C:/Windows/Temp/`

- `livecheck.ps1` - prints sessions started / ended / live since the last service start (counts
  "New streaming session started" minus "native endpoint ended" after the last "PLANK Host version:" line).
  Run this before restarting the service by hand: a viewer leaving can look like the last event.
- `safe-install.ps1 -Msi C:\Windows\Temp\plank-host-1.0.103.N.msi` - skips the box ("SKIPPED: n live PLANK
  session(s)") if anyone is connected, otherwise runs install-host.ps1.
- `install-host.ps1 -Msi <msi>` - backs up host.conf, runs msiexec quietly (log C:\Windows\Temp\plank-host-install.log),
  checks host.conf was preserved, restarts SunshineService, prints version/encoder lines.
- `firewall-shared-screen.ps1` - adds "PLANK Host shared screen viewers (UDP 28990-28997)" for sunshine.exe.
  Needed when `shared_screen = on`.
- `firewall-ndi.ps1` - adds "PLANK NDI helper (TCP)" and "(UDP)" for tools\plank-ndi.exe (Domain, Private).
  Needed when `ndi_output` is `on` or `available`.

The MSI does not add these firewall rules yet (TODO).
