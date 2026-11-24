#!/bin/sh
# OpenTyrian for AmigaOS 3.x / AmiCradle (68040 + FPU, SDL2 through GFOpenGPU),
# built with the os32-gcc16 stove (OpenAmigaGCC 16.2.0-open3 or open4). This is the
# build Cradle's stove_build runs (STOVE= and OUT= set); build_open3.py is the
# same build from a local checkout with a staged stove.
#   STOVE              the stove (default ~/AmigaChrome/stoves/os32-gcc16)
#   OUT                the output directory (default build-amiga)
#   OPENTYRIAN_SOURCE  a local upstream checkout holding the pinned commit;
#                      without it the pinned commit is fetched from upstream
#   JOBS               make's job count (default 2)
# Outputs: OpenTyrian/opentyrian (put it in a drawer beside data/), receipt.json.
# The game data is not built here: runtime-data/build-amiga.sh stages it.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STOVE=${STOVE:-"$HOME/AmigaChrome/stoves/os32-gcc16"}
OUT=${OUT:-"$HERE/build-amiga"}
JOBS=${JOBS:-2}
P="$STOVE/prefix"
SDK="$P/m68k-amigaos"
CC="$P/bin/m68k-amigaos-gcc"

# the compiler is recorded, not checked (BL-144): scripts/record_stove.py
# prints "RELEASE ARCHIVE-SHA256" (the release the compiler's --version names;
# "unpublished" when the stove names no archive) and the compiler's own
# --version line on stderr; it fails only when the stove has no compiler
COMPILER=$(python3 "$HERE/scripts/record_stove.py" --stove "$STOVE") || {
    for f in STOVE.json provenance.json; do
        if [ -f "$STOVE/$f" ]; then head -c 1500 "$STOVE/$f" >&2; echo >&2; fi
    done
    exit 2
}
RELEASE=${COMPILER% *}
"$CC" --version | head -n 1

PIN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ports"]["opentyrian"]["source"]["commit"])' "$HERE/gameports/catalog.json")
URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ports"]["opentyrian"]["source"]["url"])' "$HERE/gameports/catalog.json")

WORK=$(mktemp -d "${TMPDIR:-/tmp}/opentyrian-build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -n "${OPENTYRIAN_SOURCE:-}" ]; then
    SRC=$OPENTYRIAN_SOURCE
else
    SRC="$WORK/upstream"
    git init -q "$SRC"
    git -C "$SRC" fetch -q --depth 1 "$URL" "$PIN"
fi
git -C "$SRC" cat-file -e "$PIN^{commit}"
EPOCH=$(git -C "$SRC" show -s --format=%ct "$PIN")

mkdir -p "$WORK/src"
git -C "$SRC" archive "$PIN" | tar -xf - -C "$WORK/src"
for patch in "$HERE"/patches/*.patch; do
    echo "patch: $(basename "$patch")"
    patch --batch --forward --fuzz=0 -p1 -d "$WORK/src" < "$patch"
done

# -fno-delete-null-pointer-checks: address 0 is memory on an Amiga
FLAGS="-noixemul -m68040 -msoft-float -fno-delete-null-pointer-checks -pthread -O2 -ffile-prefix-map=$WORK/src=."
( cd "$WORK/src" && SOURCE_DATE_EPOCH=$EPOCH make -j "$JOBS" PLATFORM=AMIGA WITH_NETWORK=false \
    CC="$CC" CFLAGS="$FLAGS" SDL_CPPFLAGS="-I$SDK/include/SDL2" SDL_LDFLAGS="-L$SDK/lib" \
    SDL_LDLIBS="-lSDL2 -lGL -lm -pthread" TYRIAN_DIR=PROGDIR:data "VCS_IDREV=printf ${PIN}" ) \
    > "$WORK/make.log" 2>&1 || { tail -n 60 "$WORK/make.log"; exit 1; }
cat "$WORK/make.log"

EXE="$WORK/src/opentyrian"
[ "$(od -An -tx1 -N4 "$EXE" | tr -d ' \n')" = "000003f3" ] || { echo "not an Amiga HUNK executable"; exit 2; }
# One binary for every 68040 and 68060: -m68040 -msoft-float throughout, no
# FPU instruction in the objects, the stove's fpuauto linked in
# (package/soft-float.sh).
sh "$HERE/package/soft-float.sh" "$P" "$EXE" --log "$WORK/make.log" "$WORK/src" > "$WORK/soft-float.txt" ||
    { cat "$WORK/soft-float.txt"; exit 1; }
cat "$WORK/soft-float.txt"
mkdir -p "$OUT/OpenTyrian"
cp "$EXE" "$OUT/OpenTyrian/opentyrian"

python3 - "$HERE" "$OUT" "$PIN" "$EPOCH" "$STOVE" "$RELEASE" <<'EOF'
import hashlib, json, sys
from pathlib import Path
here, out, pin, epoch, stove, release = Path(sys.argv[1]), Path(sys.argv[2]), *sys.argv[3:]
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
sdk = Path(stove) / "prefix/m68k-amigaos"
receipt = {
    "source_commit": pin, "source_date_epoch": epoch,
    "patches": {p.name: sha(p) for p in sorted((here / "patches").glob("*.patch"))},
    "compiler_release": release,
    "sdk_inputs": {n: sha(sdk / n) for n in ("lib/libSDL2.a", "lib/libGL.a", "include/SDL2/SDL.h")},
    "executable_sha256": sha(out / "OpenTyrian/opentyrian"),
    "scope": "Source build only; network disabled; no runtime or release pass implied",
}
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
EOF
