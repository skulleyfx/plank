# PLANK Windows host release

1. On wopr: `tools/plank-build/make-hostsrc.sh main` (or any commit) - packages the
   source with submodules and uploads it to vision as `C:\plank-build\hostsrc.tgz`.
2. On vision: `build-host.ps1 -Revision N` - builds 1.0.103.N, checks it, stages it.
3. On vision, in your own PowerShell: `sign-host.ps1 -Revision N` - signs and makes
   `C:\plank-build\msi\plank-host-1.0.103.N.msi`.
4. Deploy: SSH msiexec per machine, or Action1.

Scripts on vision are copies of `build-host.ps1` / `sign-host.ps1` from this folder.
Keep .ps1 files ASCII-only (an em dash once broke PowerShell parsing).

# PLANK Windows client release

0. Once only, on vision: `setup-client-baseline.ps1` - freezes the .41 runtime DLLs/QML
   and build deps in `C:\plank-build\client-baseline` (already done 2026-10-02).
1. On wopr: `tools/plank-build/make-clientsrc.sh <client-commit> [plank-commit]` - packages
   the client with submodules plus plank-transport (+ kymux, quinn-proto) from the plank repo.
2. On vision: `build-client.ps1 -Revision N` - builds plank-client.exe 1.0.103.N (MSVC +
   Qt 6.10.2) and stages it into a copy of the frozen runtime.
3. On vision, in your own PowerShell: `sign-client.ps1 -Revision N`.

Only plank-client.exe (and AntiHooking.dll) change per release; changing Qt/FFmpeg/SDL
means re-baselining.
