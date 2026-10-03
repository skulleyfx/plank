# Build and stage the PLANK Windows client on vision.
#   usage: powershell -ExecutionPolicy Bypass -File C:\plank-build\build-client.ps1 -Revision 42
# Source comes from C:\plank-build\clientsrc.tgz (made by make-clientsrc.sh on
# wopr). Only plank-client.exe is built; it is dropped into a copy of the frozen
# .41 library set in C:\plank-build\client-baseline (setup-client-baseline.ps1).
# Stops with an error, and does not stage, if the build fails or the version is wrong.
param([Parameter(Mandatory = $true)][int]$Revision)
$ErrorActionPreference = 'Stop'

$base = (Get-Content C:\plank-build\msi-src\packaging\VERSION -Raw).Trim()
$version = "$base.$Revision"
$commit = if (Test-Path C:\plank-build\clientsrc.commit) { (Get-Content C:\plank-build\clientsrc.commit -Raw).Trim() } else { 'unknown' }
$baseline = 'C:\plank-build\client-baseline'
if (-not (Test-Path "$baseline\runtime\plank-client.exe")) { throw "missing $baseline; run setup-client-baseline.ps1 once" }
Write-Output "=== building PLANK client $version ($commit) ==="

$root = 'C:\plank-build\cb'
$src = "$root\src"
$bld = "$root\build"
Write-Output '=== [1/5] unpack source + frozen build deps ==='
Remove-Item -Recurse -Force $root -EA SilentlyContinue
New-Item -ItemType Directory -Force $src, $bld | Out-Null
tar -xzf C:\plank-build\clientsrc.tgz -C $src
robocopy "$baseline\libs" "$src\client\libs" /E /NFL /NDL /NJH /NJS /NP | Out-Null

$transport = "$src\plank\protocol\plank-transport"
$cargo = "$env:USERPROFILE\.cargo\bin"
$env:Path = "$cargo;$env:Path"
Write-Output '=== [2/5] fetch Rust transport dependencies ==='
Push-Location $transport
cargo fetch --locked 2>&1 | Select-Object -Last 2
Pop-Location

Write-Output '=== [3/5] qmake + nmake (release) ==='
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$qt = 'C:\Qt\6.10.2\msvc2022_64\bin'
$bat = @"
call "$vcvars" >nul 2>&1
set PATH=$qt;$cargo;%PATH%
cd /d $bld
qmake.exe $src\client\moonlight-qt.pro CONFIG+=release CONFIG+=plank-transport "PLANK_TRANSPORT_DIR=$transport" "PLANK_VERSION=$version" 2>&1
echo QMAKE_EXIT=%ERRORLEVEL%
nmake 2>&1
echo NMAKE_EXIT=%ERRORLEVEL%
"@
$bat | Out-File -Encoding ascii "$root\build-client.bat"
$log = 'C:\plank-build\build-client.log'
& cmd /c "$root\build-client.bat" *> $log
Select-String -Path $log -Pattern 'QMAKE_EXIT|NMAKE_EXIT|error C|error LNK(?!2047)|fatal error|Project ERROR' | Select-Object -First 25 | ForEach-Object { $_.Line }

$exe = Get-Item "$bld\app\release\plank-client.exe" -EA SilentlyContinue
if (-not $exe) { throw "plank-client.exe was not produced. See $log. Do NOT sign." }
Write-Output ("built plank-client.exe: {0}  {1}" -f $exe.VersionInfo.FileVersion, $exe.LastWriteTime)
if ($exe.VersionInfo.FileVersion -ne $version) { throw ("built version is " + $exe.VersionInfo.FileVersion + ", expected " + $version + ". Do NOT sign.") }

Write-Output '=== [4/5] stage payload (frozen .41 libraries + new exe) ==='
$pkg = 'C:\plank-build\rebase\plank-client-pkg'
Remove-Item -Recurse -Force $pkg -EA SilentlyContinue
robocopy "$baseline\runtime" $pkg /E /NFL /NDL /NJH /NJS /NP | Out-Null
Copy-Item $exe.FullName "$pkg\plank-client.exe" -Force
$hook = Get-Item "$bld\AntiHooking\release\AntiHooking.dll" -EA SilentlyContinue
if ($hook) { Copy-Item $hook.FullName "$pkg\AntiHooking.dll" -Force }

Write-Output '=== [5/5] check staged version ==='
$staged = (Get-Item "$pkg\plank-client.exe").VersionInfo.FileVersion
if ($staged -ne $version) { throw ("staged version is " + $staged + ", expected " + $version + ". Do NOT sign.") }
Write-Output ''
Write-Output "BUILD + STAGE OK: PLANK client $version ($commit)"
Write-Output "NEXT (in your own PowerShell):  powershell -ExecutionPolicy Bypass -File C:\plank-build\sign-client.ps1 -Revision $Revision"
