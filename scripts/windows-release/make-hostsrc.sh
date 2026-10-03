#!/usr/bin/env bash
# Package the Windows host source at a given commit (with submodules) as
# vision's C:\plank-build\hostsrc.tgz, then copy it over.
#   usage: make-hostsrc.sh <commit-ish> [plank-commit-ish]
#   e.g.   make-hostsrc.sh main v1.0.143
# Also packages plank-transport (+ kymux, quinn-proto) from the plank repo at
# [plank-commit-ish] (default skulleyfx/plank windows) as transportsrc.tgz;
# build-host.ps1 installs it as C:\plank-build\rebase\plank before building.
# The previous tarballs on vision are kept as *.prev, and the commits are
# recorded in C:\plank-build\hostsrc.commit for build-host.ps1 to print.
set -euo pipefail
REF=${1:?usage: make-hostsrc.sh <commit-ish> [plank-commit-ish]}
PREF=${2:-skulleyfx/windows}
PLANK=/home/flame/src/instinctual/plank-upstream
REPO=/home/flame/src/instinctual/plank-main/host/sunshine-fork
OUTDIR=$HOME/plank-build-out
VISION=${PLANK_BUILD_HOST:-plank-build}   # ssh alias for the Windows build box (see ~/.ssh/config)
KEY=$HOME/.ssh/plank_win

cd "$REPO"
[ -z "$(git status --porcelain)" ] || { echo "host tree has uncommitted changes; commit or stash first" >&2; exit 1; }
git fetch -q github-plank:skulleyfx/plank-host-windows.git main:refs/remotes/skulleyfx/main || echo "warning: fetch from skulleyfx failed, using local refs" >&2
[ "$REF" = main ] && REF=skulleyfx/main
SHA=$(git rev-parse --verify "$REF^{commit}")
SHORT=${SHA:0:8}

PREV=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)
restore() { cd "$REPO" && git checkout -q "$PREV" && git submodule update --init --recursive -q; }
trap restore EXIT
git checkout -q --detach "$SHA"
git submodule update --init --recursive -q

mkdir -p "$OUTDIR"
OUT=$OUTDIR/hostsrc-$SHORT.tgz
git ls-files --recurse-submodules -z | tar --null -czf "$OUT" -T -
echo "packaged $SHORT ($(git log --format=%s -1 "$SHA")) -> $OUT ($(du -h "$OUT" | cut -f1), $(tar tzf "$OUT" | wc -l) files)"

cd "$PLANK"
git fetch -q github-plank:skulleyfx/plank.git windows:refs/remotes/skulleyfx/windows || echo "warning: plank fetch failed, using local refs" >&2
PSHA=$(git rev-parse --verify "$PREF^{commit}")
KPIN=$(git ls-tree "$PSHA" third_party/kyber-kymux | awk '{print $3}')
git -C third_party/kyber-kymux cat-file -e "$KPIN^{commit}" 2>/dev/null || git -C third_party/kyber-kymux fetch -q https://github.com/instinctual/plank-kymux.git "$KPIN"
TSTAGE=$(mktemp -d)
mkdir -p "$TSTAGE/plank/third_party/kyber-kymux"
git archive "$PSHA" protocol/plank-transport third_party/quinn-proto-0.11.17 | tar -xf - -C "$TSTAGE/plank"
git -C third_party/kyber-kymux archive "$KPIN" | tar -xf - -C "$TSTAGE/plank/third_party/kyber-kymux"
TOUT=$OUTDIR/transportsrc-${PSHA:0:8}.tgz
tar -czf "$TOUT" -C "$TSTAGE/plank" .
rm -rf "$TSTAGE"
echo "packaged transport from plank ${PSHA:0:8} (kymux ${KPIN:0:8}) -> $TOUT"

for f in hostsrc.tgz transportsrc.tgz; do
  ssh -i "$KEY" "$VISION" "powershell -Command \"if (Test-Path C:\\plank-build\\$f) { Move-Item C:\\plank-build\\$f C:\\plank-build\\$f.prev -Force }\""
done
scp -q -i "$KEY" "$OUT" "$VISION:C:/plank-build/hostsrc.tgz"
scp -q -i "$KEY" "$TOUT" "$VISION:C:/plank-build/transportsrc.tgz"
echo "host $SHA plank $PSHA kymux $KPIN" > "$OUTDIR/hostsrc.commit"
scp -q -i "$KEY" "$OUTDIR/hostsrc.commit" "$VISION:C:/plank-build/hostsrc.commit"
echo "uploaded to vision. Next, on vision:  powershell -ExecutionPolicy Bypass -File C:\plank-build\build-host.ps1 -Revision <N>"
