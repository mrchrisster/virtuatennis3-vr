#!/usr/bin/env bash
# build-quest-from-my-copy.sh - build Virtua Tennis 3 VR for Meta Quest from
# your own copy of the game, in one command.
#
#   scripts/build-quest-from-my-copy.sh [options] /path/to/disk0
#
# Steps (each is skipped when its result is already there, so the script can
# be run again after a failure or an update):
#   1. checks the tools this needs and says how to install what is missing
#      (it never installs system tools itself)
#   2. checks your game folder: the files the port needs, the executable's
#      and lib/libCg.so's fingerprints
#   3. fetches and builds the Quest libraries (quest/deps.sh: SDL2, gl4es +
#      quest/gl4es.patch, OpenAL Soft, the OpenXR loader) into $DEPS
#   4. recompiles your copy of the game to C (games/vt3/generated, git-ignored)
#   5. builds quest/VirtuaTennis3VR.apk
#   6. with --install: copies the game files the app reads to the headset
#      (/sdcard/VirtuaTennis3) and installs the APK - after asking you
#
# Options:
#   --install     after the build, install on the headset over USB (adb);
#                 asks before writing anything to the headset
#   --yes         with --install: do not ask
#   --mac         build the macOS desktop version instead of the Quest app
#                 (build-mac/vt3; run it with scripts/run-macos.sh)
#   --check       only check the tools and the game folder, build nothing
#   --relift      recompile the game even if the last lift is current
#   --deps DIR    where the Quest libraries go (default: ../deps, next to
#                 this repository; also $DEPS)
#   -v, --verbose show every step's output (default: a log file per step in
#                 build-quest/logs/)
#   -h, --help    this text
#
# Environment: ANDROID_SDK_ROOT (default ~/Library/Android/sdk), ANDROID_NDK
# (default: the newest NDK 27 or 28 in the SDK), JAVA_HOME (default: Homebrew's
# openjdk@21, else the newest JDK 17+), PYTHON (a Python 3.10+), ANDROID_SERIAL
# (which headset, if more than one is connected).
#
# The APK holds code translated from your copy of the game: keep it to
# yourself. Nothing from the game is copied into this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID=vt3
. "$ROOT/games/$ID/game.conf"

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

INSTALL=0 YES=0 MAC=0 CHECK_ONLY=0 RELIFT=0 VERBOSE=0 GAME_ARG=
DEPS="${DEPS:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL=1 ;;
        --yes|-y) YES=1 ;;
        --mac) MAC=1 ;;
        --check) CHECK_ONLY=1 ;;
        --relift) RELIFT=1 ;;
        --deps) [ $# -ge 2 ] || { echo "--deps needs a folder" >&2; exit 2; }; DEPS="$2"; shift ;;
        --deps=*) DEPS="${1#--deps=}" ;;
        -v|--verbose) VERBOSE=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown option $1 (see --help)" >&2; exit 2 ;;
        *) [ -z "$GAME_ARG" ] || { echo "one game folder only (see --help)" >&2; exit 2; }; GAME_ARG="$1" ;;
    esac
    shift
done
[ -n "$GAME_ARG" ] || { usage >&2; exit 2; }
[ "$MAC" = 0 ] || [ "$INSTALL" = 0 ] || { echo "--install is for the Quest build, not --mac" >&2; exit 2; }
DEPS="${DEPS:-$ROOT/../deps}"
mkdir -p "$DEPS" 2>/dev/null && DEPS="$(cd "$DEPS" && pwd)"

# ---- output ----
if [ -t 1 ]; then B=$'\033[1m' R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' N=$'\033[0m'; else B= R= G= Y= N=; fi
say()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '    %sok%s  %s\n' "$G" "$N" "$*"; }
bad()  { printf '    %sno%s  %s\n' "$R" "$N" "$*"; }
warn() { printf '    %s!!%s  %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
T0=$SECONDS
elapsed() { local s=$((SECONDS - $1)); printf '%dm%02ds' $((s / 60)) $((s % 60)); }

LOGS="$ROOT/build-quest/logs"
# run <name> <command...>: the command's output goes to $LOGS/<name>.log (or
# the terminal with --verbose); on failure the log's end is shown
run() {
    local name="$1"; shift
    local t=$SECONDS log="$LOGS/$name.log"
    mkdir -p "$LOGS"
    if [ "$VERBOSE" = 1 ]; then
        "$@" 2>&1 | tee "$log" || { die "$name failed (log: ${log#"$ROOT"/})"; }
    elif ! "$@" > "$log" 2>&1; then
        printf '\n----- last lines of %s -----\n' "${log#"$ROOT"/}" >&2
        tail -n 40 "$log" >&2
        die "$name failed (whole log: ${log#"$ROOT"/})"
    fi
    ok "$name done in $(elapsed $t)  (log: ${log#"$ROOT"/})"
}

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fsize() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }

# =========================================================================
say "checking the tools"
PROBLEMS=()
need() { PROBLEMS+=("$1"$'\n'"        -> $2"); bad "$1"; }

[ "$(uname -s)" = Darwin ] || die "this script runs on macOS (the recompiler reads the macOS SDK's GL headers)"
ok "macOS $(sw_vers -productVersion 2>/dev/null || true) ($(uname -m))"
if xcrun --show-sdk-path >/dev/null 2>&1; then ok "Xcode command line tools"
else need "Xcode command line tools" "xcode-select --install"; fi

BREW="$(command -v brew || true)"
[ -n "$BREW" ] && ok "Homebrew" || warn "Homebrew not found (https://brew.sh); the install hints below use it"
BREW_PKGS=()
for t in cmake ninja git curl unzip; do
    if command -v "$t" >/dev/null; then ok "$t"; else need "$t" "brew install $t"; BREW_PKGS+=("$t"); fi
done
if [ "$MAC" = 1 ]; then
    PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    if [ -d "$PREFIX/lib/cmake/SDL2" ] || command -v sdl2-config >/dev/null; then ok "sdl2"
    else need "SDL2 (for the macOS build)" "brew install sdl2"; fi
fi

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
    for v in 3.12 3.11 3.13 3.10 3.14 3; do
        c="$(command -v "python$v" || true)"
        [ -n "$c" ] && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { PY="$c"; break; }
    done
fi
if [ -n "$PY" ] && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    ok "Python $("$PY" -c 'import platform; print(platform.python_version())') ($PY)"
    export PYTHON="$PY"
else
    need "Python 3.10 or newer${PY:+ ($PY is too old)}" "brew install python@3.12"
fi

if [ "$MAC" = 0 ]; then
    # --- JDK 17+ ---
    jmajor() { "$1/bin/java" -version 2>&1 | sed -nE '1s/.*version "([0-9]+)(\.[0-9]+)*.*/\1/p'; }
    if [ -z "${JAVA_HOME:-}" ]; then
        for j in /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
                 /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
                 "$(/usr/libexec/java_home -v 17+ 2>/dev/null || true)"; do
            [ -n "$j" ] && [ -x "$j/bin/java" ] && { JAVA_HOME="$j"; break; }
        done
    fi
    JV="$( [ -n "${JAVA_HOME:-}" ] && jmajor "$JAVA_HOME" || true)"
    if [ -n "$JV" ] && [ "$JV" -ge 17 ]; then ok "JDK $JV ($JAVA_HOME)"; export JAVA_HOME
    else need "a JDK 17 or newer${JV:+ (JAVA_HOME has Java $JV)}" "brew install openjdk@21"; fi

    # --- Android SDK, platform, licences ---
    SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
    CSDK="$(sed -nE 's/.*compileSdkVersion[[:space:]]+([0-9]+).*/\1/p' "$ROOT/quest/$ID/build.gradle" | head -1)"
    SDKM="$SDK/cmdline-tools/latest/bin/sdkmanager"
    command -v sdkmanager >/dev/null && SDKM=sdkmanager
    if [ -d "$SDK" ]; then
        ok "Android SDK ($SDK)"
        export ANDROID_SDK_ROOT="$SDK"
        if [ -d "$SDK/platforms/android-$CSDK" ]; then ok "Android platform $CSDK"
        else warn "Android platform $CSDK not installed: Gradle will try to download it (or: $SDKM \"platforms;android-$CSDK\")"; fi
        if ls "$SDK"/licenses/android-sdk-license >/dev/null 2>&1; then ok "SDK licences accepted"
        else need "the Android SDK licences are not accepted" "$SDKM --licenses   (or open Android Studio's SDK Manager once)"; fi
    else
        need "the Android SDK (looked in $SDK)" "brew install --cask android-studio, open it once and install the SDK (or set ANDROID_SDK_ROOT)"
    fi

    # --- NDK 27 or 28 ---
    ndkver() { sed -nE 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*([0-9.]+).*/\1/p' "$1/source.properties" 2>/dev/null; }
    if [ -z "${ANDROID_NDK:-}" ] && [ -d "$SDK/ndk" ]; then
        for d in $(ls -1 "$SDK/ndk" 2>/dev/null | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
            case "$d" in 27.*|28.*) [ -f "$SDK/ndk/$d/build/cmake/android.toolchain.cmake" ] && { ANDROID_NDK="$SDK/ndk/$d"; break; } ;; esac
        done
    fi
    NV="$( [ -n "${ANDROID_NDK:-}" ] && ndkver "$ANDROID_NDK" || true)"
    case "$NV" in
        27.*|28.*) ok "Android NDK $NV ($ANDROID_NDK)"; export ANDROID_NDK ;;
        "") need "Android NDK 27 or 28${ANDROID_NDK:+ (ANDROID_NDK=$ANDROID_NDK is not an NDK)}" \
                 "$SDKM \"ndk;28.2.13676358\"   (or Android Studio > SDK Manager > SDK Tools > NDK)" ;;
        *)  need "Android NDK 27 or 28 (ANDROID_NDK is $NV; the build is tested with 27.3 and 28.2)" \
                 "$SDKM \"ndk;28.2.13676358\", then unset ANDROID_NDK or point it at the new one" ;;
    esac

    # --- adb (only to install) ---
    ADB="$(command -v adb || true)"
    [ -n "$ADB" ] || { [ -x "${SDK:-}/platform-tools/adb" ] && ADB="$SDK/platform-tools/adb"; } || true
    if [ -n "$ADB" ]; then ok "adb ($ADB)"
    elif [ "$INSTALL" = 1 ]; then need "adb (to install on the headset)" "brew install --cask android-platform-tools"
    else warn "adb not found (only needed for --install: brew install --cask android-platform-tools)"; fi
fi

# =========================================================================
say "checking the game folder"
GAME="$(find_game "$GAME_ARG" || true)"
if [ -z "$GAME" ]; then
    bad "no $ELF in $GAME_ARG (also looked in $GAME_ARG/disk0)"
    PROBLEMS+=("the game folder: give the folder that holds vt3_Lindbergh/, shader/ and lib/ ($FOLDER_HINT)")
else
    ok "$GAME"
    GAME_OK=1
    for f in "$ELF" ${SOLIBS:-}; do
        [ -f "$GAME/$f" ] || { bad "$f is missing"; PROBLEMS+=("$GAME/$f is missing: the port needs it"); GAME_OK=0; }
    done
    for d in vt3_Lindbergh/resource shader; do
        [ -d "$GAME/$d" ] || { bad "$d/ is missing"; PROBLEMS+=("$GAME/$d/ is missing: the game reads it"); GAME_OK=0; }
    done
    if [ -f "$GAME/$ELF" ]; then
        have="$(sha256 "$GAME/$ELF")"
        if [ "$have" = "$ELF_SHA256" ]; then ok "$ELF (SHA-256 ${have:0:12}...)"
        else
            bad "$ELF has a different SHA-256 (${have:0:12}...)"
            if [ "${LINDBERGH_ALLOW_OTHER_EXE:-}" = 1 ]; then warn "LINDBERGH_ALLOW_OTHER_EXE=1: going on with it (untested)"
            else
                PROBLEMS+=("$ELF: SHA-256 $have"$'\n'"        the port is built and tested against vt3_Lindbergh_HD with SHA-256"$'\n'"        $ELF_SHA256; other versions of the executable are not supported")
                GAME_OK=0
            fi
        fi
    fi
    while read -r path size sum; do
        [ -n "$path" ] || continue
        f="$GAME/$path"; [ -f "$f" ] || continue
        hs="$(fsize "$f")"; hh="$(sha256 "$f")"
        if [ "$hs" = "$size" ] && [ "$hh" = "$sum" ]; then ok "$path ($size bytes, SHA-256 ${sum:0:12}...)"
        else
            bad "$path: $hs bytes, SHA-256 ${hh:0:12}..."
            PROBLEMS+=("$path is not the one the port is built against: it needs $size bytes with SHA-256"$'\n'"        $sum (yours: $hs bytes, $hh)")
            GAME_OK=0
        fi
    done <<< "${SOLIBS_EXPECTED:-}"
    if type check_game >/dev/null 2>&1; then
        if check_game "$GAME"; then ok "player models complete"
        elif [ "${LINDBERGH_ALLOW_DAMAGED_GAME:-}" = 1 ]; then warn "LINDBERGH_ALLOW_DAMAGED_GAME=1: going on with the files above damaged"
        else PROBLEMS+=("the game files listed above are empty, missing or damaged"); GAME_OK=0; fi
    fi
fi

if [ ${#PROBLEMS[@]} -gt 0 ]; then
    printf '\n%sFix these first, then run this again:%s\n' "$R" "$N" >&2
    for p in "${PROBLEMS[@]}"; do printf '  - %s\n' "$p" >&2; done
    if [ ${#BREW_PKGS[@]} -gt 1 ]; then printf '\n  (all the Homebrew packages at once: brew install %s)\n' "${BREW_PKGS[*]}" >&2; fi
    exit 1
fi
if [ "$CHECK_ONLY" = 1 ]; then say "all set: run this again without --check to build"; exit 0; fi

# =========================================================================
if [ ! -d "$ROOT/lindberghrecomp/src" ] || [ ! -d "$ROOT/lindberghrecomp/pcrecomp/tools" ]; then
    say "fetching the recompiler (git submodules)"
    run submodules git -C "$ROOT" submodule update --init --recursive
fi

if [ "$MAC" = 1 ]; then
    say "recompiling your copy and building the macOS version (the first time takes several minutes)"
    run build-macos "$ROOT/scripts/build-macos.sh" $([ "$RELIFT" = 1 ] && echo --relift) "$ID" "$GAME"
    say "done in $(elapsed $T0): $ROOT/build-mac/$ID"
    printf '\nRun it with:\n  scripts/run-macos.sh %s "%s"\n(LINDBERGH_HEADLESS=1 keeps the window off screen.)\n' "$ID" "$GAME"
    exit 0
fi

STEPS=3; [ "$INSTALL" = 1 ] && STEPS=4
say "[1/$STEPS] Quest libraries in $DEPS"
echo "    (downloads SDL2, gl4es, OpenAL Soft, the OpenXR loader and GL headers the first time;"
echo "     each one is skipped once built - delete its folder there to rebuild it)"
run deps env ANDROID_NDK="$ANDROID_NDK" ANDROID_SDK_ROOT="$SDK" DEPS="$DEPS" sh "$ROOT/quest/deps.sh"
# a gl4es built before quest/gl4es.patch changed would give an app with old
# graphics fixes: the source must be exactly the pinned commit + this patch
GL4ES_COMMIT="$(sed -n 's/^GL4ES_COMMIT=//p' "$ROOT/quest/deps.sh")"
if [ "$(git -C "$DEPS/gl4es" rev-parse HEAD 2>/dev/null)" != "$GL4ES_COMMIT" ] ||
   ! git -C "$DEPS/gl4es" apply --reverse --check "$ROOT/quest/gl4es.patch" >/dev/null 2>&1; then
    die "$DEPS/gl4es does not match quest/gl4es.patch (it was built from another version of it).
Rebuild it:  rm -rf \"$DEPS/gl4es\" \"$DEPS/gl4es-android\"  and run this again."
fi
ok "gl4es matches quest/gl4es.patch"

say "[2/$STEPS] recompiling your copy of the game to C (several minutes the first time)"
run lift "$ROOT/scripts/build-macos.sh" --lift-only $([ "$RELIFT" = 1 ] && echo --relift) "$ID" "$GAME"
grep -q "is current" "$LOGS/lift.log" && ok "(the lifted code was already current)"
GEN="$ROOT/games/$ID/generated"
# the game's GL calls bound to what gl4es defines, and the executable's
# fingerprint (the app refuses any other executable)
NM="$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm"
VPY="$ROOT/.venv/bin/python"
gl_thunks() {
    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/vt3-thunks.XXXXXX")"
    "$NM" -g --defined-only "$DEPS/gl4es/lib/libGL.a" | awk 'NF==3{print $3}' | sort -u > "$tmp/gl4es.exports"
    "$VPY" "$ROOT/lindberghrecomp/tools/gen_gl_thunks.py" --exports "$tmp/gl4es.exports" "$GEN/recomp_imports.h" \
        "$DEPS/gl4es/include/GL/gl.h" "$DEPS/gl4es/include/GL/glext.h" > "$tmp/thunks.c"
    cmp -s "$tmp/thunks.c" "$GEN/recomp_gl_thunks_android.c" || cp "$tmp/thunks.c" "$GEN/recomp_gl_thunks_android.c"
    sha256 "$GAME/$ELF" > "$tmp/sha"
    cmp -s "$tmp/sha" "$GEN/$SHA_FILE" || cp "$tmp/sha" "$GEN/$SHA_FILE"
    rm -rf "$tmp"
}
run gl-thunks gl_thunks

say "[3/$STEPS] building the APK (Gradle downloads its own parts the first time)"
run apk env ANDROID_NDK="$ANDROID_NDK" ANDROID_SDK_ROOT="$SDK" DEPS="$DEPS" JAVA_HOME="$JAVA_HOME" sh "$ROOT/quest/build.sh" "$ID"
APKF="$ROOT/quest/$APK.apk"
[ -f "$APKF" ] || die "the build finished without $APKF"
if unzip -l "$APKF" | awk '{print $4}' | grep -q '^assets/'; then
    die "$APKF has assets/ in it - this build should carry no game files; delete it and quest/$ID/src/main/assets and run again"
fi
ok "$APKF ($(du -h "$APKF" | cut -f1 | tr -d ' '), no game files in it)"

if [ "$INSTALL" = 0 ]; then
    say "done in $(elapsed $T0)"
    cat <<EOF

The app is quest/$APK.apk. It holds code translated from your copy of the
game: keep it to yourself. To put it and the game files on the headset
(developer mode on, USB connected), run this again with --install.
EOF
    exit 0
fi

# =========================================================================
say "[4/$STEPS] installing on the headset"
[ -n "$ADB" ] || die "adb not found"
DEVS="$("$ADB" devices | awk 'NR>1 && NF>=2 {print $1" "$2}')"
if [ -n "${ANDROID_SERIAL:-}" ]; then DEVS="$(echo "$DEVS" | awk -v s="$ANDROID_SERIAL" '$1==s')"; fi
case "$(echo "$DEVS" | grep -c . || true)" in
    0) die "no headset found by adb. Connect it over USB, make sure developer mode is on, put it on and
accept \"Allow USB debugging\", then run this again." ;;
    1) ;;
    *) die "more than one device connected: set ANDROID_SERIAL to one of: $(echo "$DEVS" | awk '{print $1}' | tr '\n' ' ')" ;;
esac
SERIAL="$(echo "$DEVS" | awk '{print $1}')" STATE="$(echo "$DEVS" | awk '{print $2}')"
case "$STATE" in
    device) ;;
    unauthorized) die "the headset has not allowed this computer yet: put it on, accept \"Allow USB debugging\" and run this again" ;;
    *) die "the headset is '$STATE' to adb; reconnect it and run this again" ;;
esac
export ANDROID_SERIAL="$SERIAL"
MODEL="$("$ADB" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
DEST="$HEADSET_DIR${HEADSET_SUB:+/$HEADSET_SUB}"

# The files the app reads, without this computer's settings, saves, logs and
# test output (the headset's own vr.cfg, env.txt and saves stay as they are).
# Staged as hard links (or APFS clones) under build-quest/, so it takes no space.
STAGE="$ROOT/build-quest/headset-files"
stage_files() {
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    local mode=ln n=0
    (cd "$GAME" && find $GAME_PARTS -type f \
        ! -name lindbergh_nvram.bin ! -name lindbergh.ini ! -name env.txt ! -name vr.cfg \
        ! -name 'vt3_save.bin*' ! -name '*.ppm' ! -name '*.pgm' ! -name '*.log' ! -name '.*' \
        ! -name '*.scc' ! -name '*~' ! -iname thumbs.db ! -iname picasa.ini ! -path '*/CVS/*') > "$STAGE.list"
    while IFS= read -r f; do
        mkdir -p "$STAGE/$(dirname "$f")"
        case $mode in
            ln) ln "$GAME/$f" "$STAGE/$f" 2>/dev/null || { mode=clone; cp -cp "$GAME/$f" "$STAGE/$f" 2>/dev/null ||
                    { mode=copy; echo "(the game folder is on another disk: copying the files, about $SIZE)"; cp -p "$GAME/$f" "$STAGE/$f"; }; } ;;
            clone) cp -cp "$GAME/$f" "$STAGE/$f" ;;
            copy) cp -p "$GAME/$f" "$STAGE/$f" ;;
        esac
        n=$((n + 1))
    done < "$STAGE.list"
    echo "$n files staged ($mode)"
}
run stage-headset-files stage_files
NFILES="$(wc -l < "$STAGE.list" | tr -d ' ')"

cat <<EOF

    This writes to the headset ${MODEL:-$SERIAL}:
      1. installs quest/$APK.apk as "$APP" ($PKG; an update keeps its settings)
      2. lets it read the game from shared storage (MANAGE_EXTERNAL_STORAGE)
      3. copies $NFILES game files ($GAME_PARTS, $SIZE) to $DEST/
         - only files that are newer here than on the headset; vr.cfg, env.txt
           and saves there are not touched
EOF
if [ "$YES" = 0 ]; then
    [ -r /dev/tty ] || die "no terminal to ask on: run with --yes to install without asking"
    printf '\n    Go ahead? [y/N] '
    read -r answer < /dev/tty || answer=
    case "$answer" in y|Y|yes|YES) ;; *) say "nothing written to the headset"; exit 0 ;; esac
fi
run adb-install "$ADB" install -r "$APKF"
run adb-permission "$ADB" shell appops set --uid "$PKG" MANAGE_EXTERNAL_STORAGE allow
push_game() {
    "$ADB" shell mkdir -p "$DEST"
    for part in $GAME_PARTS; do "$ADB" push --sync "$STAGE/$part" "$DEST/"; done
}
run adb-copy-game push_game
say "done in $(elapsed $T0)"
cat <<EOF

Start "$APP" from Unknown Sources (Library > Applications > Unknown Sources).
The first start takes longer while the game reads its files. Log of the last
run: adb shell cat $HEADSET_DIR/$LOG
EOF
