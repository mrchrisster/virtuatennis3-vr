#!/usr/bin/env bash
# build-macos.sh - lift your own copy of a game and build it for macOS.
#
#   ./scripts/build-macos.sh [--opengl|--vulkan] [--lift-only] [--relift] vt3 /path/to/disk0
#
# Builds the OpenGL renderer by default (into build-mac/), the one Virtua
# Tennis 3 is tested with; --vulkan builds the runtime's native Vulkan
# renderer instead (into build-mac-vulkan/, untested for this game).
#
# <game> is a folder name under games/ (vt3); its
# game.conf says what the game's folder holds. Nothing from it is copied into
# this repo; the lifted C goes to the gitignored games/<game>/generated/.
#
# --lift-only stops after the lift (what the Quest build needs; no SDL2).
# Safe to run again: the lift is skipped when the game, the recompiler and its
# Python packages are what the last lift used (generated/.lift-stamp;
# --relift lifts anyway), and unchanged lifted files keep their timestamps,
# so a rebuild only recompiles what moved.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLKIT="$ROOT/lindberghrecomp"
RENDERER=OPENGL LIFT_ONLY=0 RELIFT=0
while :; do
    case "${1:-}" in
        --opengl) shift ;; --vulkan) RENDERER=VULKAN; shift ;;
        --lift-only) LIFT_ONLY=1; shift ;; --relift) RELIFT=1; shift ;;
        *) break ;;
    esac
done
ID="${1:-}"
[ -n "$ID" ] && [ -f "$ROOT/games/$ID/game.conf" ] || {
    printf 'usage: %s <game> /path/to/the/game\ngames: %s\n' "$0" "$(ls "$ROOT/games" | tr '\n' ' ')" >&2; exit 1; }
. "$ROOT/games/$ID/game.conf"
GEN="$ROOT/games/$ID/generated"
if [ "$RENDERER" = VULKAN ]; then BUILD="$ROOT/build-mac-vulkan"; else BUILD="$ROOT/build-mac"; fi
VENV="$ROOT/.venv"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '==> %s\n' "$*"; }

[ "$(uname -s)" = Darwin ] || die "this script is for macOS"
[ $# -ge 2 ] || die "usage: $0 $ID \"$FOLDER_HINT\""

# ---- the game folder ----
GAME="$(find_game "$2")"
[ -n "$GAME" ] || die "no $ELF in $2 (expected $TITLE's folder, $FOLDER_HINT)"
if type check_game >/dev/null 2>&1 && ! check_game "$GAME" && [ "${LINDBERGH_ALLOW_DAMAGED_GAME:-}" != 1 ]; then
    die "build stopped: fix the game files above (or LINDBERGH_ALLOW_DAMAGED_GAME=1 to build anyway)"
fi
for f in $ELF ${SOLIBS:-}; do
    [ -f "$GAME/$f" ] || die "$GAME/$f is missing"
done
say "$TITLE: $GAME"

# ---- tools ----
missing=()
# Python 3.10+: $PYTHON, else the newest python3.x on the PATH, else python3
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
    for v in 3.12 3.11 3.13 3.10 3.14 ""; do
        c="$(command -v "python$v" 2>/dev/null || command -v "python${v:-3}" 2>/dev/null || true)"
        [ -n "$c" ] && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { PY="$c"; break; }
    done
    [ -n "$PY" ] || PY="$(command -v python3 || true)"
fi
[ -n "$PY" ] || missing+=("python@3.12")
PREFIX="$(brew --prefix 2>/dev/null || true)"
if [ "$LIFT_ONLY" = 0 ]; then
    for t in cmake ninja; do command -v "$t" >/dev/null || missing+=("$t"); done
    # sdl2, or sdl2-compat (what newer Homebrew installs for "sdl2"): either leaves
    # a CMake package or sdl2-config behind
    [ -d "${PREFIX:-/opt/homebrew}/lib/cmake/SDL2" ] || command -v sdl2-config >/dev/null || missing+=("sdl2")
fi
if [ "$LIFT_ONLY" = 0 ] && [ "$RENDERER" = VULKAN ]; then
    [ -e "${PREFIX:-/opt/homebrew}/lib/libvulkan.dylib" ] || missing+=("vulkan-loader")
    [ -d "${PREFIX:-/opt/homebrew}/include/vulkan" ] || missing+=("vulkan-headers")
    for t in glslangValidator:glslang spirv-cross:spirv-cross spirv-opt:spirv-tools; do
        command -v "${t%%:*}" >/dev/null || missing+=("${t#*:}")
    done
fi
[ ${#missing[@]} -eq 0 ] || die "missing: ${missing[*]}  ->  brew install ${missing[*]}"
xcrun --show-sdk-path >/dev/null 2>&1 || die "no macOS SDK  ->  xcode-select --install"
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))' || die "$PY is too old; need Python 3.10+  ->  brew install python@3.12 (or PYTHON=/path/to/python3.x)"

if [ ! -d "$TOOLKIT/pcrecomp/tools" ]; then
    say "fetching submodules"
    git -C "$ROOT" submodule update --init --recursive
fi

if [ ! -x "$VENV/bin/python" ]; then
    say "creating $VENV"
    "$PY" -m venv "$VENV"
fi
"$VENV/bin/python" -c 'import sys; sys.exit(sys.version_info < (3, 10))' ||
    die "$VENV was made with a Python older than 3.10: delete it and run again"
"$VENV/bin/python" -m pip install -q --disable-pip-version-check -r "$ROOT/requirements-dev.txt"
VPY="$VENV/bin/python"

# ---- is the last lift still current? ----
# The game's files, the recompiler's sources and the lifter's packages: the
# same inputs give the same C, so the lift (minutes) is skipped.
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
STAMP="$( {
    echo "elf $(sha "$GAME/$ELF")"
    for f in ${SOLIBS:-}; do echo "solib $f $(sha "$GAME/$f")"; done
    [ -f "$ROOT/games/$ID/names.txt" ] && echo "names $(sha "$ROOT/games/$ID/names.txt")"
    (cd "$TOOLKIT" && find tools pcrecomp/tools -name '*.py' -type f | LC_ALL=C sort | xargs shasum -a 256)
    "$VPY" -m pip freeze --disable-pip-version-check 2>/dev/null | grep -i -E '^(capstone|pyelftools)==' || true
} | shasum -a 256 | cut -d' ' -f1)"
if [ "$RELIFT" = 0 ] && [ "$(cat "$GEN/.lift-stamp" 2>/dev/null)" = "$STAMP" ] && ls "$GEN"/recomp_funcs_*.c >/dev/null 2>&1; then
    say "the lifted code in ${GEN#"$ROOT"/} is current (--relift to lift again)"
    LIFTED=1
else
    LIFTED=0
fi

# ---- lift ----
if [ "$LIFTED" = 0 ]; then
rm -f "$GEN/.lift-stamp"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/$ID-lift.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
GLH="$(xcrun --show-sdk-path)/System/Library/Frameworks/OpenGL.framework/Headers"

BOUNDS_ARG=()
if [ -n "${STRIPPED:-}" ]; then
    # A stripped executable lists no functions; find them (minutes, so the
    # result is kept, keyed by the executable's hash).
    BOUNDS="$GEN/bounds.txt"
    SUM="$(shasum -a 256 "$GAME/$ELF" | cut -d' ' -f1)"
    if [ ! -f "$BOUNDS" ] || [ "$(cat "$GEN/bounds.sha256" 2>/dev/null)" != "$SUM" ]; then
        say "finding its functions (a few minutes)"
        mkdir -p "$GEN"
        ( cd "$TOOLKIT" && "$VPY" -m tools bounds "$GAME/$ELF" "$BOUNDS" --names "$ROOT/games/$ID/names.txt" )
        echo "$SUM" > "$GEN/bounds.sha256"
    fi
    cp "$BOUNDS" "$GEN/bounds.sha256" "$STAGE/"
    BOUNDS_ARG=(--bounds "$BOUNDS")
fi
say "lifting the game"
( cd "$TOOLKIT" && "$VPY" -m tools recomp "$GAME/$ELF" "$STAGE" ${BOUNDS_ARG[@]+"${BOUNDS_ARG[@]}"} )
if [ -n "${SOLIBS:-}" ]; then
    say "lifting the libraries it loads"
    # The order (game.conf) fixes where each library lands in guest memory.
    libs=(); for f in $SOLIBS; do libs+=("$GAME/$f"); done
    ( cd "$TOOLKIT" && "$VPY" -m tools.recomp.solib "$STAGE" --main-elf "$GAME/$ELF" "${libs[@]}" )
fi
say "generating GL thunks"
"$VPY" "$TOOLKIT/tools/gen_gl_thunks.py" "$STAGE/recomp_imports.h" "$GLH/gl.h" "$GLH/glext.h" > "$STAGE/recomp_gl_thunks.c"

# copy only what changed, so unchanged files keep their timestamps
mkdir -p "$GEN"
for f in "$STAGE"/*; do
    cmp -s "$f" "$GEN/${f##*/}" || cp "$f" "$GEN/"
done
for f in "$GEN"/*; do
    case "${f##*/}" in *_android.c|*.elf.sha256) continue ;; esac  # the Quest build's, made separately
    [ -e "$STAGE/${f##*/}" ] || rm -f "$f"
done
echo "$STAMP" > "$GEN/.lift-stamp"
rm -rf "$STAGE"; trap - EXIT
fi
[ "$LIFT_ONLY" = 0 ] || { say "lifted code ready in ${GEN#"$ROOT"/}"; exit 0; }

# ---- build ----
say "building ($RENDERER renderer)"
cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLINDBERGH_RENDERER="$RENDERER" \
      ${PREFIX:+-DCMAKE_PREFIX_PATH="$PREFIX"} >/dev/null
cmake --build "$BUILD" --target "$ID"

[ -x "$BUILD/$ID" ] || die "build finished without $BUILD/$ID"
say "built $BUILD/$ID"
printf '\nRun it with:\n  %s/scripts/run-macos.sh %s%s "%s"\n' "$ROOT" "$([ "$RENDERER" = VULKAN ] && echo '--vulkan ')" "$ID" "$GAME"
