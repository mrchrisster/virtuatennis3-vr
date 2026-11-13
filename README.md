# Virtua Tennis 3 VR

**Stand courtside in a full 3D stadium: Virtua Tennis 3 rebuilt as a
standalone VR game for Meta Quest, from your own copy of the arcade game.**

[![Virtua Tennis 3 VR Trailer](https://img.youtube.com/vi/HLOx7s2JFiw/maxresdefault.jpg)](https://youtu.be/HLOx7s2JFiw "Watch Virtua Tennis 3 VR Trailer on YouTube")

**[▶ Watch the Virtua Tennis 3 VR Trailer on YouTube](https://youtu.be/HLOx7s2JFiw)** — *Classic 2D & 3D VR captured on Meta Quest 3.*

This repository has the VR runtime, the build scripts and the Quest app for a
port of Sega's arcade *Virtua Tennis 3* (Lindbergh, 2006) to Meta Quest 3 / 3S /
Pro, plus a macOS build for testing. The game's x86 code is statically
recompiled to C on your machine by
[lindberghrecomp](https://github.com/mrchrisster/lindberghrecomp) (a submodule)
and built against its runtime, which stands in for the arcade cabinet.
Nothing is emulated.

> **No game files are included.** No executable, no game data, no recompiled
> code, no APK. You need your own copy of the game and build
> the app yourself. The build reads your copy on your machine; the app reads
> the game's files from the headset. The stadium, the sky and the title logo
> you see are the game's own, drawn at run time from your files.
> Generated files (`games/vt3/generated/`, e.g. `recomp_funcs_*.c`,
> `recomp_solib_relocs.c`) are made by the build from your copy and are never
> committed.

## Features

Two ways to play, chosen up front with two big buttons on the settings panel:

- **Classic**: the arcade picture on a big virtual screen in front of you.
- **VR**: you stand courtside, in the stadium.

In VR:

- **The whole stadium in 3D around you**: the upper tiers and both ends,
  which the arcade's TV cameras only ever showed part of, under Sega's own
  sky dome all the way round (Sky: Stadium / Painted / Off).
- **A steady view between points**: no jarring cuts; the move to the next
  point's start is eased.
- **Camera height** Low / Medium / High, raised automatically when your
  player changes ends to the far side; **Step back** and **Camera closer**
  place you where you like.
- **Replays and reaction cams** (one setting: replays, the winner's reaction
  close-up and the match's other camera scenes): on a flat screen (default),
  in VR from the broadcast camera's angle with soft fades between shots
  (*VR*, experimental), or off.
- **Starts in VR** with the settings the developer plays with on a Quest 3
  (anti-aliasing 2x in VR, Off in Classic; texture filtering 4x, shadows 4096,
  120 Hz); lower them in the panel on a Quest 3S / Quest Pro if the frame
  rate suffers.

Both modes:

- **Sharper crowd and ad boards**: the game's texture LOD bias, which the
  Quest's GPU lacks, is applied in the shaders.
- **Picture settings**: shadow quality, display rate (the headset's own
  rates, e.g. 72 / 90 / 120 Hz), resolution per eye, foveation; anti-aliasing
  Off / 2x / 4x and texture filtering Standard / Sharp 4x / Sharp 8x (both
  experimental).
- **No card needed**: the card-reader notices are gone (a Classic row brings
  them back), and **Save progress** (experimental, on by default) keeps your
  career between sessions the way the arcade's player card did. **Reset
  save** starts over; the old save is kept as a backup.
- **Language**: English (default) or Japanese.
- **Quest controls**, either hand alike: trigger = top spin, A / X = slice,
  B / Y = lob, stick = move, stick click = Start. The left controller's menu
  button opens the settings panel.
- **Arcade-to-Quest fixes**: music no longer skips; the prize-money digits,
  the players' lighting in close-ups, shadows and more are drawn correctly on
  the Quest's GPU (see [the porting guide](docs/VT3_PORTING_GUIDE.md)).

*Experimental*: built and checked on macOS, not yet confirmed on the headset.

## Screenshots

*Coming: pictures the project owner will take from his own copy.*

## Build for Meta Quest

There is no download of the app: it holds code translated from the game, so
everyone builds their own from their own copy. One command does it:

```sh
git clone --recursive https://github.com/mrchrisster/virtuatennis3-vr.git
cd virtuatennis3-vr
scripts/build-quest-from-my-copy.sh /path/to/disk0            # -> quest/VirtuaTennis3VR.apk
scripts/build-quest-from-my-copy.sh --install /path/to/disk0  # ...and onto the headset
```

`disk0` is your game folder, the one that holds `vt3_Lindbergh/`, `shader/`
and `lib/`. The script:

1. checks what it needs and says how to get what is missing (it does not
   install anything on your Mac itself): macOS with the Xcode command line
   tools, Homebrew's `cmake ninja`, Python 3.10+, a JDK 17+ (21
   recommended: `brew install openjdk@21`), the Android SDK with NDK 27 or 28
   (Android Studio's SDK Manager), and `adb` for `--install`
   (`brew install --cask android-platform-tools`);
2. checks your game folder: the files the port needs, and the fingerprints of
   `vt3_Lindbergh/vt3_Lindbergh_HD` and `lib/libCg.so` (see below);
3. downloads and builds the Quest libraries (SDL2, gl4es with
   `quest/gl4es.patch`, OpenAL Soft, the OpenXR loader) into `../deps`, next
   to this folder;
4. recompiles your copy of the game to C (into `games/vt3/generated`,
   git-ignored; several minutes the first time);
5. builds `quest/VirtuaTennis3VR.apk` (no game files in it);
6. with `--install` (headset in developer mode, on USB): shows what it will
   write and asks, then installs the APK and copies the game files the app
   reads to `/sdcard/VirtuaTennis3/` on the headset (only files that are
   newer than the headset's; its settings and saves are left alone).

Run it again after an update or a failure: finished steps are skipped. Each
step's output is in `build-quest/logs/`; `--check` only checks, `--help`
lists the options. The first build takes about 7-15 minutes (7 on an M-series
Mac), most of it the recompile; a rerun with nothing changed, seconds.

All of the game folder is needed, including `lib/libCg.so`: its code is
recompiled like the game's, and its bytes are read from your file (size and
SHA-256 checked) when the game starts. The port is built and tested against
the `vt3_Lindbergh_HD` executable (the 1360x768 one); the script checks its
SHA-256. This project does not emulate or answer the cabinet's security
dongle, so an executable that requires the dongle check to pass will stop at
start-up with "Game Program Not Found".

Start *Virtua Tennis 3 VR* from Unknown Sources.

### Troubleshooting

- **"lib/libCg.so is missing" / "not the one the port is built against"**
  (from the script, or the app's message on the headset): the whole game
  folder is needed, `lib/` included, and on the headset at
  `/sdcard/VirtuaTennis3/lib/libCg.so`. The app needs the same file the build
  checked (2,170,374 bytes).
- **"vt3_Lindbergh_HD has a different SHA-256"**: the port is built against
  `vt3_Lindbergh_HD` with SHA-256 `4bc1ff17...d3c9aa`; other versions of the
  executable are not supported.
- **"Android NDK 27 or 28"**: install one with Android Studio's SDK Manager
  (SDK Tools > NDK (Side by side), e.g. 28.2.13676358), or point
  `ANDROID_NDK` at one. Other NDK versions are untested.
- **"... does not match quest/gl4es.patch"**: the patch changed since
  `../deps/gl4es` was built; delete `../deps/gl4es` and `../deps/gl4es-android`
  and run the script again.
- **The headset shows "Finding position in room", a Guardian prompt, or
  stays dark**: the app waits for the headset's tracking. Turn on the light
  (tracking needs a lit room) and confirm the boundary prompt in the headset.
- **The first start is slow** (around 35 s, a start-up screen with the
  controls and a progress line; "MOVE · START" means the stick moves and its
  click is Start): the game reads its files. Later starts are quicker.
- **Nothing happens after `--install`**: put the headset on and accept
  "Allow USB debugging"; the script says when adb sees no headset or one that
  has not allowed this computer.

<details>
<summary>Building by hand (what the script runs)</summary>

```sh
export ANDROID_NDK=$HOME/Library/Android/sdk/ndk/<version>

# 1. recompile your copy of the game to C (into games/vt3/generated,
#    git-ignored); without --lift-only this also builds the macOS test binary
./scripts/build-macos.sh --lift-only vt3 /path/to/disk0

# 2. the Quest dependencies (SDL2, gl4es + quest/gl4es.patch, OpenAL Soft,
#    the OpenXR loader), built into ../deps
quest/deps.sh

# 3. the game's GL calls bound to gl4es, and the executable's fingerprint
G=games/vt3/generated
"$ANDROID_NDK"/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm -g --defined-only \
    ../deps/gl4es/lib/libGL.a | awk 'NF==3{print $3}' | sort -u > /tmp/gl4es.exports
.venv/bin/python lindberghrecomp/tools/gen_gl_thunks.py --exports /tmp/gl4es.exports \
    $G/recomp_imports.h ../deps/gl4es/include/GL/gl.h ../deps/gl4es/include/GL/glext.h \
    > $G/recomp_gl_thunks_android.c
shasum -a 256 /path/to/disk0/vt3_Lindbergh/vt3_Lindbergh_HD | cut -d' ' -f1 \
    > $G/vt3_Lindbergh_HD.elf.sha256

# 4. the APK (quest/VirtuaTennis3VR.apk); then, headset in developer mode on
#    USB, install it and copy the game to /sdcard/VirtuaTennis3
quest/build.sh vt3
quest/install.sh vt3 /path/to/disk0
```

`quest/install.sh` copies the game folders as they are, including any
`vr.cfg` / `lindbergh.ini` a macOS run left in them; the script copies
without those.

</details>

## Build and run on macOS

```sh
scripts/build-quest-from-my-copy.sh --mac /path/to/disk0   # or: ./scripts/build-macos.sh vt3 /path/to/disk0
./scripts/run-macos.sh vt3 /path/to/disk0
```

This needs Homebrew's `cmake ninja sdl2` and Python 3.10+ (no Android tools).

Keyboard: arrows move, Z = top spin, X = slice, Z + X = lob, 5 = coin,
1 = start, M = sound (it starts muted), Esc = quit. `LINDBERGH_VT3_IMMERSIVE=1`
shows the VR mode in a flat window. `scripts/vt3-repro.sh` runs scripted test
scenes; `LINDBERGH_HEADLESS=1` keeps the window off screen.

## Tests

No game needed:

```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python lindberghrecomp/tools/recomp/test_driver.py
(cd lindberghrecomp && ../.venv/bin/python -m unittest discover -s tests -p 'test_*.py')
```

The XR actions test needs `openxr/openxr.h` (from `../deps` after
`quest/deps.sh`, or `LINDBERGH_TEST_OPENXR_HEADERS=<dir>`) and is skipped
without it. CI (`.github/workflows/ci.yml`) runs these and the runtime's
self-check.

## Settings

On the Quest the left menu button opens the settings panel; its choices are
kept in `vt3_Lindbergh/vr.cfg` on the headset. Any setting can be forced with
a `NAME=value` line in `/sdcard/VirtuaTennis3/env.txt` (the panel then shows
"(env.txt)"); on macOS the same `LINDBERGH_*` switches are environment
variables. The arcade's Test / Service switches are not offered: the
game's operator test menu cannot be reached (Test closed the game). The full list is in [the porting guide](docs/VT3_PORTING_GUIDE.md).

## Layout

| Path | What |
| --- | --- |
| `games/vt3/` | the game's profile (`game.conf`: its files, checks and app names) and host code |
| `lindberghrecomp/` | submodule: the recompiler and the runtime (VR, GL, audio, cabinet I/O) |
| `quest/` | the Android project, `build.sh`, `deps.sh`, `install.sh`, `gl4es.patch`, the icon and start-up screen generators |
| `scripts/` | macOS build and run, `vt3-repro.sh` test scenes, `wav_glitches.py` |
| `docs/` | the porting guide and the backlog |
| `ai_docs/` | working notes, hand-off and research for contributors and coding agents |

## Credits

- **sp00nznet** wrote the original
  [lindberghrecomp](https://github.com/sp00nznet/lindberghrecomp),
  [pcrecomp](https://github.com/sp00nznet/pcrecomp) and the Lindbergh
  recompilation ports this grew from.
- **lialan**'s [lindbergh-recomp-ports](https://github.com/lialan/lindbergh-recomp-ports),
  [lindberghrecomp](https://github.com/lialan/lindberghrecomp) and
  [pcrecomp](https://github.com/lialan/pcrecomp) brought the macOS and Meta
  Quest ports this repository is built from.
- [gl4es](https://github.com/ptitSeb/gl4es) (MIT), patched by
  `quest/gl4es.patch`; [SDL2](https://libsdl.org),
  [OpenAL Soft](https://openal-soft.org) and the
  [Khronos OpenXR loader](https://github.com/KhronosGroup/OpenXR-SDK), fetched
  at build time.

Licences: [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Legal

Unofficial fan project, not affiliated with or endorsed by SEGA. Virtua
Tennis is a trademark of SEGA. No game files are included; you need your own
copy. The code in this repository is MIT-licensed; the game and everything in
it belong to their owners. This project contains no code that emulates,
answers or bypasses the security dongle, and it does not provide game files or
explain how to obtain or modify them.
