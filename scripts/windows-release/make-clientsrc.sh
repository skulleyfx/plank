#!/usr/bin/env bash
# Package the Windows client source at a given commit (with submodules), plus
# the plank-transport it links from the plank superproject, as vision's
# C:\plank-build\clientsrc.tgz, then copy it over.
#   usage: make-clientsrc.sh <client-commit-ish> [plank-commit-ish]
#   e.g.   make-clientsrc.sh windows            (skulleyfx/plank-client windows)
# The plank ref defaults to skulleyfx/plank windows. The previous tarball on
# vision is kept as clientsrc.tgz.prev; both commits are recorded in
# C:\plank-build\clientsrc.commit for build-client.ps1 to print.
set -euo pipefail
CREF=${1:?usage: make-clientsrc.sh <client-commit-ish> [plank-commit-ish]}
PREF=${2:-skulleyfx/windows}
CLIENT=/home/flame/src/instinctual/plank-main/client/moonlight-qt-fork
PLANK=/home/flame/src/instinctual/plank-upstream
OUTDIR=$HOME/plank-build-out
VISION=${PLANK_BUILD_HOST:-plank-build}   # ssh alias for the Windows build box (see ~/.ssh/config)
KEY=$HOME/.ssh/plank_win
STAGE=$(mktemp -d)

cd "$CLIENT"
[ -z "$(git status --porcelain)" ] || { echo "client tree has uncommitted changes; commit or stash first" >&2; exit 1; }
git fetch -q github-plank:skulleyfx/plank-client.git windows:refs/remotes/skulleyfx/windows || echo "warning: client fetch failed, using local refs" >&2
[ "$CREF" = windows ] && CREF=skulleyfx/windows
CSHA=$(git rev-parse --verify "$CREF^{commit}")
PREV=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)
restore() { cd "$CLIENT" && git checkout -q "$PREV" && git submodule update --init --recursive -q; rm -rf "$STAGE"; }
trap restore EXIT
git checkout -q --detach "$CSHA"
git submodule update --init --recursive -q
mkdir -p "$STAGE/client"
git ls-files --recurse-submodules -z | tar --null -cf - -T - | tar -xf - -C "$STAGE/client"

cd "$PLANK"
git fetch -q github-plank:skulleyfx/plank.git windows:refs/remotes/skulleyfx/windows || echo "warning: plank fetch failed, using local refs" >&2
PSHA=$(git rev-parse --verify "$PREF^{commit}")
mkdir -p "$STAGE/plank/third_party/kyber-kymux"
git archive "$PSHA" protocol/plank-transport third_party/quinn-proto-0.11.17 | tar -xf - -C "$STAGE/plank"
KPIN=$(git ls-tree "$PSHA" third_party/kyber-kymux | awk '{print $3}')
git -C third_party/kyber-kymux archive "$KPIN" | tar -xf - -C "$STAGE/plank/third_party/kyber-kymux"

echo "client $CSHA plank $PSHA kymux $KPIN" > "$STAGE/clientsrc.commit"
mkdir -p "$OUTDIR"
OUT=$OUTDIR/clientsrc-${CSHA:0:8}.tgz
tar -czf "$OUT" -C "$STAGE" client plank clientsrc.commit
echo "packaged client ${CSHA:0:8} ($(git -C "$CLIENT" log --format=%s -1 "$CSHA")) + plank ${PSHA:0:8} -> $OUT ($(du -h "$OUT" | cut -f1))"

ssh -i "$KEY" "$VISION" "powershell -Command \"if (Test-Path C:\plank-build\clientsrc.tgz) { Move-Item C:\plank-build\clientsrc.tgz C:\plank-build\clientsrc.tgz.prev -Force }\""
scp -q -i "$KEY" "$OUT" "$VISION:C:/plank-build/clientsrc.tgz"
scp -q -i "$KEY" "$STAGE/clientsrc.commit" "$VISION:C:/plank-build/clientsrc.commit"
echo "uploaded to vision. Next, on vision:  powershell -ExecutionPolicy Bypass -File C:\plank-build\build-client.ps1 -Revision <N>"
