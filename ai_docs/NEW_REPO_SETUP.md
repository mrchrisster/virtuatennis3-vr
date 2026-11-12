# New repository setup (2026-11-13)

How `virtuatennis3-vr` was made from lindbergh-recomp-ports, what was left out
and why, and what has to happen before it is published.

- Source: lindbergh-recomp-ports commit `0c2631b` (read only, `git archive`),
  then T19's outer changes `0c2631b..1db0343` applied (libCg.so no longer
  embedded). The source repo's working tree was never used.
- Submodule `lindberghrecomp` pinned at `1addfc1` (branch `vt3-quest`, T19),
  its submodule `pcrecomp` at `e8b993e` (branch `vt3-port`).

## GitHub description and topics (for the conductor)

Description (one line):

> Virtua Tennis 3 in VR on Meta Quest: stand courtside in the full 3D stadium, or play Classic on a big virtual screen. Static recompilation runtime and build tools; no game files included - bring your own copy and build it yourself. Unofficial fan project, not affiliated with SEGA.

Topics: `meta-quest`, `virtual-reality`, `openxr`, `static-recompilation`,
`sega-lindbergh`, `virtua-tennis`, `gl4es`, `macos`

## What went in

- `games/vt3/` (game.conf, host.c, android_main.c, splash_art.c - original art)
- `quest/`: build.sh, deps.sh, install.sh, gl4es.patch, gradle wrapper,
  settings.gradle (vt3 only), build.gradle (Vulkan block removed), `vt3/`
  Android module, `tools/vt3_icon.py`, `tools/vt3_splash.py`
- `scripts/`: build-macos.sh, run-macos.sh (OpenGL now the default, `--vulkan`
  optional), vt3-repro.sh, wav_glitches.py
- `CMakeLists.txt` (OpenGL default renderer, Vulkan offscreen target removed)
- `docs/VT3_PORTING_GUIDE.md`, `docs/VT3_QUEST_BACKLOG.md`
- `ai_docs/`: README (ground rules updated), HANDOFF, CONDUCTOR_STATE,
  SESSION_LOG_2026-11-11, research/ (all 11), wip/vt3-icon-notes.md
- New: README.md, NOTICE, LICENSE (sp00nz notice kept, contributors added),
  .gitignore, .gitmodules (absolute URL to the fork), .github/workflows/ci.yml
  (macOS self-check + unit tests, no game)

## Left out

- Other games: games/{hotd4,hotd4sp,hotdex,lgj,ghostsquadevolution},
  quest/{hotd4,hotd4sp,lgj,ghostsquadevolution}, docs/{hotd4,hotd4sp,hotdex,
  lgj,ghostsquadevolution} (incl. their .jpg screenshots)
- Vulkan / Windows / Steam Frame tooling: quest/build_vulkan.py,
  run_vulkan_offscreen.py, run_vulkan_xr.py, vulkan_offscreen.c,
  scripts/{harvest-pipelines.sh,test-vulkan-macos.sh,build-windows.sh,
  run-hotd4-windows.ps1,package-windows.py,build-steam-frame.sh,steam-frame/},
  tools/vulkan/, cmake/toolchains/mingw64.cmake, docs/VULKAN_*.md
- Gun tools: quest/tools/{font2h.py,gunbuild.py,obj2gun.py}
- .github/workflows/quest.yml (other games' release CI, private lifted-code
  repo and signing secrets), old ci.yml (Windows job)
- CONTRIBUTING.md (multi-game), docs/QUEST-RELEASE.md (multi-game release
  notes), the old README
- ai_docs/wip/*.diff and wip/README.md (safety copies of runtime code, now
  committed in the submodule or, for T19, still in progress in the old repo)
- docs/.DS_Store (tracked in the source repo!) and every other .DS_Store
- Never present: games/vt3/generated, game data, APKs, build dirs

## Audit edits

- Home and scratch paths replaced: the owner's local pictures folder ->
  `$VT3_PICS/`; agent scratch paths -> `$SCRATCH/`; the owner's workspace
  folder -> `<workspace>/`, the old repo's path -> `<repo>`.
- Dongle / modified-executable details removed: VT3_PORTING_GUIDE 1 (dump
  archive names, Redump image, ext2 dump forensics) and 2.2 (the 13-byte
  diff of the executables incl. the stubbed error routine and the dongle
  challenge description); research/ic-card-save-emulation.md (dongle call
  chain and addresses); research/card-reader-top-bar.md (stubbed
  setError clause). game.conf's comments and check_game message neutralised
  (no dump/ROM-set names).
- Checked: no disassembly listings, no decompiled game functions (code
  blocks in research are our own runtime sketches); no keys/tokens (only the
  Android debug keystore's public default password in vt3/build.gradle); PNG
  icons carry no metadata; splash_art.c decoded and inspected (our art).

## Before publishing: what must be pushed where

1. `lindberghrecomp` fork (github.com/mrchrisster/lindberghrecomp), branch
   `vt3-quest`: today at `9d68719`; the pin `1addfc1` needs these 12 commits
   (fast-forward from `9d68719`): 2c3f4f4 688a9b9 2e61a2c 9dd8505 66ce3ff
   298f90a ca127f5 891dd47 992a066 4929c07 d2a2332 1addfc1.
   Push from the old repo's submodule (its `fork` remote):
   `git -C <workspace>/lindbergh-recomp-ports/lindberghrecomp push fork 1addfc1:refs/heads/vt3-quest`
2. `pcrecomp` fork: `e8b993e` is already on mrchrisster/pcrecomp `vt3-port`
   (checked with ls-remote) - nothing to push.
3. Then this repo (see the report for the commands).

## Progress

- [x] file selection, audit, licence/NOTICE, README, .gitignore, submodule
- [x] macOS build + headless smoke on the old base (0c2631b / d2a2332):
  lift + build 6m22s, round0 90 s: match started, two points played, frames OK
- [x] APK on the old base: quest/VirtuaTennis3VR.apk 25.3 MB, 1m59s
- [x] rebuild on the T19 base (1db0343 / 1addfc1), scratch copy, existing
  ../deps (gl4es source checked identical to quest/gl4es.patch applied to
  gl4es 1891af3): lift + build OK (generated has recomp_solib_relocs.c, no
  recomp_solib_img.c); headless round0 90 s: libCg.so read from the game
  folder (SHA-256 verified, 6721 relocations), match started, three points
  played; APK 24.6 MB built (NDK 28.2, JDK 21), contents only classes/res/
  manifest + libmain/libSDL2/libopenal/libopenxr_loader, no assets; 0 of ~360
  sampled 48-byte runs of libCg.so found in libmain.so or the mac binary.
  All 15 lindberghrecomp/tests/test_*.py and tools/recomp/test_driver.py pass.
- [x] initial commit
