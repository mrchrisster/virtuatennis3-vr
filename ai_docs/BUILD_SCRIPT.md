# One-command build from the player's copy (2026-11-13)

Owner's decision: the app stays free of game data and the APK is never
published, so each player builds their own from their own copy. This is the
work log for `scripts/build-quest-from-my-copy.sh` and the test / CI clean-up
that came with it.

## What it does

`scripts/build-quest-from-my-copy.sh [--install [--yes]] [--mac] [--check]
[--relift] [--deps DIR] [-v] <disk0>`

1. Tools: macOS + Xcode CLT, Homebrew (warning only), cmake ninja git curl
   unzip, Python 3.10+ (prefers 3.12 / 3.11), JDK 17+ (JAVA_HOME, Homebrew
   openjdk@21, `/usr/libexec/java_home -v 17+`), Android SDK (platform from
   `quest/vt3/build.gradle` compileSdkVersion: warning; licences: error),
   NDK 27/28 (newest in `$SDK/ndk`, or ANDROID_NDK, version from
   source.properties), adb (error only with --install; `$SDK/platform-tools`
   fallback). `--mac` needs sdl2 instead of the Android tools. All problems
   are listed together with install hints; nothing is installed system-wide.
2. Game folder: `find_game`, the ELF + SOLIBS present, `shader/` and
   `vt3_Lindbergh/resource/`, the ELF's SHA-256 against `ELF_SHA256`, each
   `SOLIBS_EXPECTED` entry's size + SHA-256 (game.conf), `check_game`
   (player models). Overrides: `LINDBERGH_ALLOW_OTHER_EXE=1`,
   `LINDBERGH_ALLOW_DAMAGED_GAME=1`. Messages say what is missing / which
   hash is expected - nothing about how to obtain or change files.
3. `quest/deps.sh` (its own skip logic), then a check that `$DEPS/gl4es` is
   the pinned commit with exactly `quest/gl4es.patch` applied
   (`git apply --reverse --check`); otherwise stop with the rm command.
4. `scripts/build-macos.sh --lift-only` (lift skipped when
   `generated/.lift-stamp` matches: ELF + solib hashes, names.txt, every
   lifter .py under tools/ and pcrecomp/tools, capstone/pyelftools versions).
5. Android GL thunks (llvm-nm of libGL.a + gen_gl_thunks.py) and the ELF
   fingerprint, written only when changed; `quest/build.sh vt3`; the APK is
   refused if it contains `assets/`.
6. `--install`: one adb device (ANDROID_SERIAL for several), the files of
   GAME_PARTS staged as hard links (APFS clone / copy fallback) under
   `build-quest/headset-files` without lindbergh_nvram.bin, lindbergh.ini,
   env.txt, vr.cfg, saves, logs, frames, dotfiles; a summary and a [y/N]
   prompt on /dev/tty (`--yes` skips; no tty and no --yes = stop); then
   `adb install -r`, `appops ... MANAGE_EXTERNAL_STORAGE allow`,
   `adb push --sync` per part into /sdcard/VirtuaTennis3/.

Logs per step: `build-quest/logs/<step>.log` (last 40 lines shown on failure).

## Plan / progress

- [x] script, `--help`, `--check` (real folder ok; fake folder: missing
  shader/, wrong ELF hash, wrong libCg size/hash, missing models all named)
- [x] `scripts/build-macos.sh`: `--lift-only`, lift stamp, `--relift`,
  Python search, `requirements-dev.txt`
- [x] `games/vt3/game.conf`: `ELF_SHA256`, `SOLIBS_EXPECTED`
- [x] tests (lindberghrecomp b347611 on top of b8ef66f; now b8ddc4c, cherry-picked by the graphics worker onto 01b320c): `test_xr_actions`
  failed to link - lindberghrecomp 20f9a90 added the Thumbstick vector2f
  action, the selftest had no xrGetActionStateVector2f stub and the old
  counts; `test_solib_relocs` skips without pyelftools; OpenXR header search
  ($DEPS, env var); `test_nn_culling` / `test_xr_panel` had no main guard
  (ran nothing as scripts)
- [x] CI: discovery, OpenXR headers from Khronos (release-1.1.49), a tracked-
  files guard, scripts parse; simulated locally in a clean clone: all steps
  pass (82 tests OK, selftest ok). actionlint / shellcheck not installed.
- [x] README: one-command path, manual steps in `<details>`, troubleshooting,
  Tests section
- [x] proof (2026-11-13): fresh `git clone` of 3dfbf84 (submodule URLs pointed
  at the local module dirs, as b347611 is not on GitHub yet), fresh empty
  `../deps`, no .venv: `scripts/build-quest-from-my-copy.sh <workspace>/vt3/disk0`
  -> exit 0 in 7m18s (deps 34 s, lift 4m38s, thunks 1 s, APK 2m04s):
  quest/VirtuaTennis3VR.apk 23 MB, contents classes.dex, resources, manifest,
  libmain/libSDL2/libopenal/libopenxr_loader - no assets/. Rerun: 4.5 s
  (lift skipped as current, everything else no-op). Headless: nothing ran.
- [x] --install path with a fake `adb` on PATH (the real one never called):
  no device -> clear stop; no tty without --yes -> stop, nothing written
  (fixed: `[ -r /dev/tty ]` passed without a controlling tty); --yes ->
  install -r, appops, mkdir, push --sync x3; 1298 files staged as hard links,
  none of lindbergh.ini / nvram / vr.cfg / env.txt / logs. Not run on a headset.
- [x] old tree's submodule pin: moved to b8ddc4c by the graphics worker (both trees pin it)

- [x] `--mac` in the same fresh clone: build-mac/vt3 in 1m26s (lift reused
  from the stamp). Built only, not run.

## Concurrency note

Another worker committed to this repo during this work (83c3396, submodule
b8ef66f). The test commit was cherry-picked onto b8ef66f (b347611) so the
pin does not drop their change. The graphics worker then cherry-picked it onto
01b320c as b8ddc4c (outer 096527b); both trees pin b8ddc4c. Start any
further submodule commit from b8ddc4c.
