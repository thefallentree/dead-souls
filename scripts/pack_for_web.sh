#!/usr/bin/env bash
#
# pack_for_web.sh -- pack this mudlib into a playable static browser bundle
# (WebAssembly FluffOS + web terminal), for GitHub Pages.
#
# Usage: scripts/pack_for_web.sh <driver_dir> <out_dir>
#   <driver_dir>  dir containing fluffos.js/fluffos.wasm/telnet.js/vendor/
#                 (an extracted fluffos release *-wasm.zip)
#   <out_dir>     output dir (created), ready to publish as a Pages site root
#
# Modeled on fluffos/mudlibs' scripts/pack_lib_for_web.sh, simplified for a
# single mudlib per repo (no multi-lib site index, so the driver files sit
# directly alongside index.html instead of a shared ../_driver/). Like
# fluffos/nightmare3, this repo's mudlib lives in a lib/ subdirectory
# (config.deadsouls: "mudlib directory : ./lib"), not the repo root.
#
# gitignored runtime dirs (lib/log, lib/secure/log, lib/secure/save,
# lib/daemon/tmp) are absent from a fresh checkout, and this mudlib's
# write_file()/save_object() calls throw (silently aborting the caller) if
# the target directory doesn't exist at all, even one that would hold a
# brand new file -- so every directory pattern named in .gitignore gets
# its SHAPE (not content) recreated in the staged copy before packing.
#
# NOTE: this repo's own build.sh builds a NATIVE driver from the driver/
# submodule with -DPACKAGE_UIDS=OFF; this script instead uses the shared
# prebuilt fluffos/fluffos WASM release (same as every other repo here,
# built with OLD_ED on) -- the mudlib's own master.c already implements
# get_root_uid/get_bb_uid/creator_file so PACKAGE_UIDS being on doesn't
# matter, but OLD_ED being on means the modern ed_start/ed_cmd/
# query_ed_mode efuns this mudlib's in-game code editor (lib/lib/editor.c)
# expects aren't defined -- confirmed live (registration, exploration,
# look/score/quit all work with zero errors; only the creator-only
# in-game text editor is affected). Building a from-source WASM driver
# with matching flags would fix that too but is out of scope here; the
# native build.sh/run.sh path (documented in README) remains the fully-
# correct way to do in-game LPC development on this mudlib.
#
# Requires: emscripten's file_packager (emsdk on PATH), python3.

set -euo pipefail
set -x   # trace every command -- see fluffos/nightmare3's pack_for_web.sh
         # for why (CI-only failures need a diagnosable trail even without
         # repo-admin log access).
note() { echo "::notice::pack_for_web: $*"; }

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/.." && pwd)

if [ $# -ne 2 ]; then
  echo "usage: $0 <driver_dir> <out_dir>" >&2
  exit 2
fi

DRIVER_DIR=$(cd "$1" && pwd)
OUT=$2
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)   # must be absolute -- see nightmare3's pack_for_web.sh:
                          # step 4 below cd's into $STAGE first, so a relative
                          # $OUT would resolve against the stage dir instead
                          # of the caller's cwd.
[ -f "$DRIVER_DIR/fluffos.js" ] && [ -f "$DRIVER_DIR/fluffos.wasm" ] || {
  echo "error: driver not found in $DRIVER_DIR (need fluffos.js + fluffos.wasm)" >&2; exit 1; }
[ -f "$DRIVER_DIR/index.html" ] || { echo "error: $DRIVER_DIR/index.html not found" >&2; exit 1; }

FILE_PACKAGER=""
if command -v file_packager >/dev/null; then
  FILE_PACKAGER="file_packager"
else
  EMCC_PATH=$(command -v emcc || true)
  for c in "${EMCC_PATH:+$(dirname "$EMCC_PATH")/tools/file_packager.py}" \
           /usr/share/emscripten/tools/file_packager.py; do
    if [ -n "$c" ] && [ -f "$c" ]; then FILE_PACKAGER="python3 $c"; break; fi
  done
fi
[ -n "$FILE_PACKAGER" ] || { echo "error: emscripten file_packager not found (emsdk on PATH?)" >&2; exit 1; }
note "using FILE_PACKAGER=[$FILE_PACKAGER]"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/dspack.XXXXXX")
trap 'chmod -R u+w "$STAGE" >/dev/null 2>&1 || true; rm -rf "$STAGE" 2>/dev/null || true' EXIT
note "staging in $STAGE"

# --- 1. stage the mudlib tree (git-tracked files only: no local build/,
#        driver/ submodule, save data, or other untracked cruft leaks into
#        the published bundle) ------------------------------------------
mkdir -p "$STAGE/mudlib"
FILE_COUNT=0
while IFS= read -r rel; do
  dst="$STAGE/mudlib/${rel#lib/}"
  mkdir -p "$(dirname "$dst")"
  cp "$REPO_ROOT/$rel" "$dst"
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(cd "$REPO_ROOT" && git ls-files lib)
note "step 1 done: staged $FILE_COUNT tracked files"

# --- 2. recreate gitignored runtime-dir SHAPE (empty, no content) -----------
DIR_COUNT=0
while IFS= read -r pat; do
  case "$pat" in
    /lib/*.o|/lib/*/*.o) continue ;;  # file globs, not directories
  esac
  rel=${pat#/lib/}; rel=${rel%/}
  [ -z "$rel" ] && continue
  mkdir -p "$STAGE/mudlib/$rel"
  DIR_COUNT=$((DIR_COUNT + 1))
done < <(grep -oE '^/lib(/[A-Za-z0-9_.*-]+)+/?$' "$REPO_ROOT/.gitignore" 2>/dev/null || true)
note "step 2 done: recreated $DIR_COUNT gitignored runtime dirs"

# --- 3. rewrite the config's mudlib directory to the in-image path and pack
#        it INSIDE the mudlib tree itself (config.fluffos.mount reads it as
#        a relative path from the chdir'd mount point, not a separate fetch)
python3 - "$REPO_ROOT/config.deadsouls" "$STAGE/mudlib/mudlib.cfg" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8', errors='surrogateescape').read()
text, n1 = re.subn(r'^(\s*mudlib directory\s*:\s*).*$', r'\g<1>/mudlib', text, flags=re.M)
if n1 != 1:
    sys.exit('error: expected exactly one "mudlib directory :" line, found %d' % n1)
open(dst, 'w', encoding='utf-8', errors='surrogateescape').write(text)
PYEOF
note "step 3 done: wrote mudlib.cfg"

# --- 4. pack with file_packager ---------------------------------------------
(cd "$STAGE" && $FILE_PACKAGER "$OUT/mudlib.data" \
    --preload "mudlib@/mudlib" \
    --js-output="$OUT/mudlib.js")
note "step 4 done: file_packager produced $OUT/mudlib.data + mudlib.js"

# --- 5. boot config + driver + page -----------------------------------------
cat > "$OUT/fluffos-boot.js" <<EOF
// Generated by scripts/pack_for_web.sh -- consumed by index.html.
window.FLUFFOS_BOOT = {
  mount: "/mudlib",
  config: "mudlib.cfg",
};
EOF
cp "$DRIVER_DIR/fluffos.js" "$DRIVER_DIR/fluffos.wasm" "$DRIVER_DIR/telnet.js" "$OUT/"
cp -r "$DRIVER_DIR/vendor" "$OUT/"
cp "$DRIVER_DIR/index.html" "$OUT/index.html"
note "step 5 done: driver + page copied into $OUT"

SIZE=$(du -sh "$OUT" | cut -f1)
echo "packed dead-souls -> $OUT ($SIZE)"
