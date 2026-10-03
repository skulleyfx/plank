# One-time setup on vision: freeze the libraries the signed 1.0.103.41 client
# shipped with, so later releases rebuild only plank-client.exe against the
# exact same Qt / FFmpeg / SDL / runtime set.
#   C:\plank-build\client-baseline\runtime  = the .41 payload (all DLLs, QML, plugins)
#   C:\plank-build\client-baseline\libs     = the build-time deps that produced it
$ErrorActionPreference = 'Stop'
$base = 'C:\plank-build\client-baseline'
if (Test-Path $base) { throw "$base already exists; remove it first to re-baseline" }
$payloadVersion = (Get-Item C:\plank-build\rebase\plank-client-pkg\plank-client.exe).VersionInfo.FileVersion
if ($payloadVersion -ne '1.0.103.41') { throw "expected the .41 payload, found $payloadVersion" }
New-Item -ItemType Directory -Force "$base\runtime", "$base\libs" | Out-Null
robocopy C:\plank-build\rebase\plank-client-pkg "$base\runtime" /E /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy C:\plank-build\client37\libs "$base\libs" /E /NFL /NDL /NJH /NJS /NP | Out-Null
Set-Content "$base\README.txt" "Frozen from the signed 1.0.103.41 client on $(Get-Date -Format yyyy-MM-dd). runtime = payload; libs = build deps (client37\libs)." -Encoding ascii
"runtime: {0} files   libs: {1} files" -f @(Get-ChildItem "$base\runtime" -Recurse -File).Count, @(Get-ChildItem "$base\libs" -Recurse -File).Count
