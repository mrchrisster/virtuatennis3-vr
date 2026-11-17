# Netplay: two copies of the game in lockstep

Status (2026-11-16): **a Quest plays a Mac over home Wi-Fi.** Stages 0-1 on
macOS (2026-11-15) and, on 2026-11-16, the Quest: the APK has the INTERNET
permission; a session is started from `env.txt` (`LINDBERGH_NETPLAY=host` on
the Quest, `join:<quest ip>` on the Mac). Measured: unattended Quest host vs
Mac joiner (bots both sides), 11,640 frames in lockstep, every match hash
equal, a full 1P-vs-2P match, RTT 8.8 ms, delay 1, 3% of frames waited; then
the owner played worn against the Mac bot (Classic): 15,600+ frames, 260
hashes compared, no desync, "felt great"; then in **Immersive** (VR, the
owner's head moving the camera, the Mac with a fixed head): 25,200+ frames,
420 hashes compared, no desync, "seems to work well" - the camera does not
feed the match. The Mac's player 2 joins with `LINDBERGH_KEYS2_JOIN=1` (one
coin when a 1P match point starts, again only after a match has ended). A Mac recording replayed on the
Quest gives the Mac's match hash for the whole match. No headset panel yet
(env.txt only); see "Next stage" at the end. The plan behind it:
`ai_docs/research/local-multiplayer-netplay.md` (Part B),
`ai_docs/research/versus-two-quests.md`, `ai_docs/research/netplay-example-strikers.md`.

**Model:** deterministic input lockstep. Both machines run the whole game.
Each frame each sends the other only its own player's cabinet input (lever,
buttons, coins) for frame F + D; a frame is simulated only when both inputs for
it are in. No video, no state transfer. Host = player 1, joiner = player 2.

With none of the switches below set, the game runs exactly as before (the input
layer passes the host's own input straight through).

## Switches

| Switch | What |
|---|---|
| `LINDBERGH_NETPLAY=host[:port]` | host a session (UDP, default port 47100); waits for player 2 at the first frame |
| `LINDBERGH_NETPLAY=join:<ip>[:port]` | join a host as player 2 |
| `LINDBERGH_NETPLAY_DELAY=<n>` | the starting input delay in frames (default 2; it adapts from there, minimum 1) |
| `LINDBERGH_NETPLAY_TIMEOUT=<ms>` | how long a frame may wait for the other player before the session ends (default 10000) |
| `LINDBERGH_NETPLAY_WAIT=<s>` | how long the host waits for a joiner / the joiner for an answer (default 120) |
| `LINDBERGH_NETPLAY_HASH_EVERY=<n>` | state hash exchange every n frames (default 30; `LINDBERGH_STATE_HASH` wins) |
| `LINDBERGH_NETPLAY_HASH=mem` | compare the memory hash, not the game's match hash |
| `LINDBERGH_NETSIM=delay_ms,jitter_ms,loss_pct[,reorder_pct]` | the built-in network simulator, on this side's sends |
| `LINDBERGH_NETSIM_STALL=at_ms,len_ms` | one stall: sends held from at_ms after the start for len_ms (Wi-Fi power save) |
| `LINDBERGH_NETSIM_SEED=<n>` | the simulator's random seed |
| `LINDBERGH_INPUT_REC=<file>` | record both players' cabinet state every frame |
| `LINDBERGH_INPUT_PLAY=<file>` | play a recording back instead of the real input (`LINDBERGH_INPUT_PLAY_EXIT=1` quits at its end, `_STRICT=1` refuses a header mismatch) |
| `LINDBERGH_STATE_HASH=<n>` | log `[hash] frame F: <hex>` (and the game's `[shash]`) every n frames |
| `LINDBERGH_STATE_HASH_DETAIL=1` | also `[hashd]` per-4 KB-chunk hashes |
| `LINDBERGH_STATE_DUMP=<file>@<f>[,<f>]` | the hashed memory raw at those frames (for `tools/state_dump_diff.py`) |
| `LINDBERGH_STATE_HASH_REGIONS=lo-hi,...,!lo-hi` | override the profile's hash regions (hex, `!` left out) |
| `LINDBERGH_DETERMINISTIC=1` | the determinism fixes alone (implied by REC, PLAY and NETPLAY; `=0` turns them off to measure them) |
| `LINDBERGH_DET_LIBM=0` | deterministic mode without the bundled maths |
| `LINDBERGH_TICK_LOG=1` | input-frame vs display-frame log |
| `LINDBERGH_DET_AUDIO=0` | deterministic mode with the sound card's clock for the voices (to measure the fix) |
| `LINDBERGH_DET_CRI=0` | deterministic mode with CRI's wall-clock vsync (to measure the fix) |
| `LINDBERGH_SEGA_READS=<from>-<to>` | log the game's SEGAAPI status / position reads in that input-frame range, with callers |
| `LINDBERGH_SLOW_IO=<ms>[,<from frame>]` | every guest open/read takes that much longer (a slow disk on the Mac) |
| `LINDBERGH_DET_HITCH=<frame>,<ms>` | the main thread sleeps once at that game frame (a slow frame) |
| `LINDBERGH_DET_FRAMELOG=<n>` / `LINDBERGH_DET_MTLOG=<from>-<to>` | game frame vs input frame every n; each match-MT draw with caller and thread |
| `LINDBERGH_THREAD_LOG=1` | each guest thread's start routine and host thread id (`[open]` lines carry frame and thread with `LINDBERGH_OPENS=1`) |
| `LINDBERGH_KEYS2="frame:key[*n],..."` | scripted player 2: `z x c` buttons, `^ _ < >` lever, `2` Start, `6` / `5` a coin in chute 2 / 1 |
| `LINDBERGH_KEYS2_JOIN=1` | scripted player 2 joins (coin in chute 2, Start, shot taps through the select) once when a 1P match point starts, again only after a match ended |
| `LINDBERGH_BOT=<from>[,<1\|2\|3>]` | a lever-and-swing bot for player 1, 2 or both from that frame |

Tools (runtime `tools/`): `state_hash_diff.py a.log b.log [--semantic]` (first
diverging frame), `state_dump_diff.py a.<f> b.<f> <elf> --regions "<profile string>"`
(the differing bytes, by symbol). Scripts (this repository): `vt3-repro.sh versus`
(the two-player scene), `vt3-netplay-test.sh` (the scenario table).

## The input layer (generic, every Lindbergh game)

`netplay.c` sits at the cabinet chokepoint. Every reader goes through it:

- `cab_switch_read()` - the JVS switch read (command 0x20, `hle_sega.c`). Each
  call starts an **input frame (tick)**. Measured on VT3: one read a frame on
  one thread after 5 reads during boot (tick = display frame + 5).
- `cab_input()` - the coin (0x21) and analog/gun (0x22) reads, and the QTE log:
  they return the current tick's state.
- `cab_buttons()` - game hooks that look at a button between reads (HOTD4's
  and HOTD EX's reload overrides in their `host.c`).

In an active mode (REC, PLAY, NETPLAY) the state is canonical: the gun in the
board's 0..65535 units (screen size 65535), so two windows of different sizes
feed the game the same numbers.

## Recording format

Text header, then 32 bytes a frame (little-endian):

```
LGINPUT1
elf=<SHA-256 of the game's executable>
runtime=<runtime git hash[-dirty]>
settings=<name=value;... sorted>        (what changes the simulation)
deterministic=1
---
tick u32, buttons u32, coins[2] u16, gun x/y i32, gun 2 x/y i32, gun 2 on u8, 3 spare
```

A replay whose header differs warns (and stops with `LINDBERGH_INPUT_PLAY_STRICT=1`).

## Protocol (UDP, LAN, `lockstep.c`)

Every packet: `magic u32 "LGNP"`, `protocol u8` (1), `type u8`, `length u16`,
then the body, little-endian. Unknown magic is ignored.

| Type | Body |
|---|---|
| HELLO (1) joiner -> host, every 250 ms | protocol u32, ELF SHA-256 [32], runtime hash [40], wanted delay u8, settings length u16 + text |
| WELCOME (2) host -> joiner | session nonce u32, delay u8, start frame u32 (1) - repeated for any later HELLO |
| REFUSE (3) host -> joiner | length u16 + text: what differs, by name ("vt3.replays=1 here, 0 there") |
| INPUT (4) both ways | nonce u32, send time µs u32, echo of the peer's last send time u32, hold µs u32, ack u32 (I have all your input up to this frame), my frame u32, the host's delay change (at u32, d u8), the joiner's echo of it (u32), first frame u32, n u8, n x input (buttons u32, coins 2 x u16, gun x/y i32, gun u8), k u8, k x (frame u32, hash u64) |
| BYE (5) | nonce u32, reason u8 (1 quit, 2 desync, 3 timeout), sent 3 times |

- **Handshake / version check:** at the game's first input frame both block
  until the session stands. The host compares the HELLO with its own: protocol,
  the game executable's SHA-256, the runtime's git hash, and the settings that
  change the simulation (VT3: test jumps, replays, cutaways, overlays, mode,
  save, cull, hold, the NVRAM's checksum, the frame rate). Any difference ->
  REFUSE with the list; the joiner logs `[net] the host refused us: ...` and both
  play on alone. A mismatched protocol, game or runtime is named the same way.
- **Start:** lockstep from frame 1 on both. Frames 1..D carry no input
  (neutral on both sides).
- **Input:** each side samples its own input at frame F and assigns it to
  frame F + D. Every packet repeats all unacknowledged frames (up to 16) -
  redundancy instead of retransmission; a packet also goes out every 8 ms
  while a frame waits, and every 50 ms while this side has no frame (a load).
- **Delay:** both use the same D, changed only at an agreed frame. The host
  measures the round trip (NTP-style: send time, echo, hold time; smoothed
  RTT and mean deviation measured on the network thread) and wants
  D = ceil((RTT/2 + 2·jitter + 3 ms) / 16.68 ms), at least 1, at most 12. Up at
  once, down by one after 3 s of less. The change is scheduled
  2·12 + RTT-frames + 8 frames ahead, carried in every host packet until the
  joiner echoes it. A larger D repeats the last input into the gap, a smaller
  one drops samples (the other side reads by frame number, so either way both
  stay in step). The delay only decides when *my* input counts; it never
  touches what the two games compute.
- **Stall:** a frame whose other input is not in waits (the game does not
  advance on either side). After `LINDBERGH_NETPLAY_TIMEOUT` the session ends:
  BYE (timeout), `[net] frame N: nothing from the other player for ... -
  session ended, playing on alone`, and the game goes on with the local input
  only.
- **Desync:** every `HASH_EVERY` frames each side hashes its state at the start
  of the frame (before its input) - by default the game's own match hash if it
  has one (VT3: ball, players' roots and facing, match record, the global MT
  state and index), else the memory hash - and sends the last 4. The first
  mismatch: `[net] DESYNC: the two games differ at frame N`, BYE (desync), both
  play on alone. No recovery.
- **Stats:** `[net] frame N: delay D, rtt ... (min, max, jitter), stalls ...,
  sent, received, repeated inputs, hashes compared` every 600 frames and at exit.
- **Pause / menu:** nothing in the game pauses. The Mac's menu bar and the
  headset panel are overlays: the game keeps running and the panel only blocks
  that player's own input. The live Classic/Immersive switch is held while a
  session runs (`world_mode.c`); see "Open" for the other panel rows.
- **Network simulator:** in our own send path (`LINDBERGH_NETSIM`): delay ±
  jitter (uniform), loss, reordering (an extra delay), a one-off stall, own
  random generator. No system tools, no root.

## Deterministic mode (`LINDBERGH_DETERMINISTIC=1`)

Implied by REC, PLAY and NETPLAY; off by default so normal play is unchanged.

| Source of divergence | Fix |
|---|---|
| libc `rand`/`srand` (host's: Apple and Bionic differ) | glibc's TYPE_3 `random()` (the arcade's own), `netplay.c` |
| libc `time()` | a fixed date (2007-01-01 12:00 UTC) + input frames / 60 |
| VT3 `_sSystem::getTime` (gettimeofday in ms) feeding the frame clock (`getFrameTime`: uva animations, camera physics), the scene clock (`_sSceneDatabase::updateDatabase`) and the players' / AI's MT seeds | by caller: frame n's clock = epoch + n/60 s counted by `_sSystem::execute`'s own calls; seeds = epoch + 7919·k for the k-th; backup run time from the frame clock. Pacing (`waitFrame`, `waitMain`, `getFPS`) keeps the wall clock (`hle_sega.c`) |
| Elementary maths: lifted `fpatan/fsin/fcos/fptan/fsincos`, libm imports (VT3: acos acosf cos cosf expf log10 log10f logf pow powf sin sinf tanf; the runtime also binds asin atan atan2 tan sinh cosh tanh exp log and float forms) | `det_math.c` -> bundled fdlibm (`third_party/fdlibm`, Sun's licence + SDL's zlib, from SDL 2.32.10); asin/acos from atan2+sqrt, hyperbolics from exp, floats as the double rounded once. Exact on every host and left alone: sqrt, fabs, floor/ceil/trunc/nearbyint, fmod, frexp, modf, ldexp, `+ - * /` |
| FMA contraction (`a*b+c`) | `-ffp-contract=off` for the whole target - lifted code, runtime, fdlibm (CMake `LINDBERGH_FP_CONTRACT_OFF`, ON) |
| Heap layout: the runtime allocating in the game's heap; loader threads allocating at the same time as the main thread | the game's malloc gets its own heaps, one per thread (main 256 MB, the first four threads the game makes 352 MB each, the next eleven 8 MB, the rest 168 MB), zero-filled; the runtime's allocations above 0x98000000 (`guest_mem.c`) |
| A job pool hands jobs to whichever worker is free | VT3's `_sSystem::nWorkerThreads` 3 -> 1 |
| Loads finish when the disk is done: a faster machine saw a load complete frames earlier, and the draws that follow moved (MT index 259 vs 267 at frame 1680, equal again at 1740) | `netplay_frame_barrier`: each input frame first waits until VT3's `candy::ThreadPool`s are idle (waitDone's own test: +0x44 queued, +0x4c running) and assam's decoder count is 0 (3 s cap) - every disk infinitely fast |
| One global MT for the match and for presentation: the effects system (`_abm*`, `_abk*`, `Kf*` particles), the crowd (`CAudience2DManager`), voices (`sound::*`), the racket sound and the shader noise draw from it depending on what is shown and heard (seen: MT index 346 vs 349 three frames after a point at 60 ms; the next camera pick differed) | those 222 call sites (57 functions, by return address, `hle_sega.c k_vt3_fx_rand_from`) get a stream of their own (splitmix64); the match's callers keep the game's MT |
| After a stall the two 60 Hz frame grids stay a frame apart: one side then waits ~15 ms every frame | a frame that waited restarts the frame pacer's grid from that moment (`host_sdl.c pace`, `netplay_take_stalled`) |
| The voices on the sound card's clock: `vs::isVs_stop` (has the announcer's line ended?) gates the attract's flow; the answer changed a frame apart between runs (voice stop at input frame 615 vs 616, state split at 385; netplay clean desynced at frame 420 with `LINDBERGH_DET_AUDIO=0`) | the SEGAAPI mixer advances by input frames: each frame mixes 800 output frames (48000 / 60) into a FIFO from the input layer, the card's callback only plays the FIFO (a stall is silence) - `hle_segaapi.c` |
| CRI's middleware server on its own 60 Hz wall-clock "vsync" (`lxsync_thrd_proc` usleep 16666 -> `adxm_vsync_proc` -> `SVM_ExecSvrVsync`), blocking reads on the CRIDLG delegate thread: the text databases `assam::FileManager` loads for the boot's warning screen finished vsyncs later on a slower disk, and the screen ended 30-120 frames later on the Quest (reproduced on the Mac with `LINDBERGH_SLOW_IO=2,350`) | `lxsync_wait_cond` wakes `adxm_vsync_proc` once per input frame and the load barrier waits for its pass (3 s cap); `CRIDLG_TryBeginInvoke` runs the delegate in its caller (`hle_sega.c`) |
| The hash itself: host pointers in guest mutexes | the 12 bytes after hle_pthread's "LGJ1" magic are skipped |

## Lessons from Quest 3 Strikers (ideas only; that project is GPL-3.0)

`ai_docs/research/netplay-example-strikers.md`. Taken over: a separate random
stream for presentation (done, above); every time read on a virtual 60 Hz
clock (done for the clock reads that feed VT3's state); a small semantic hash
that names what diverged (`[shash]`: ball, players, score, MT); neutral input
for the first D frames; the version in every packet (the protocol byte and
the session nonce; the full check at the handshake); a long wait allowed at
load (our load barrier makes loads take no frames instead).
Still to do:
- **Reseed the match's MT every frame** from (match seed, frame) so one stray
  draw cannot carry on (Strikers does this). VT3's MT is drawn on the
  framework thread; the reseed has to happen there, at the frame start (e.g.
  a wrap of `tennis::procMain`), not from the JVS thread.
- **Camera-dependent game logic audit** (each VR player gets his own view in
  stage 5): `_sCamera::isVisible` / `TScene::Frustum::intersect` results that
  feed logic, culling-dependent animation, the camera routine on the job-pool
  worker (now the only worker in deterministic mode). The presentation
  callers above are already off the match's stream.
- **Delay from the median of pings** at the start (Strikers: median of 9,
  fixed for the match). Ours adapts from a smoothed RTT; a median-of-pings
  start value would avoid the first seconds' stalls on Wi-Fi.

## What else can differ between Apple clang (arm64, x86_64) and the NDK (arm64)

- **FMA:** off everywhere now. Apple clang's and the NDK's clang default to
  `-ffp-contract=on`; arm64 has FMADD, so without the flag the two could fuse
  different expressions.
- **x87 model:** the recompiler models the x87 stack as host `double` (no
  80-bit extended precision). Both hosts run the same C, so both get the same
  doubles - not the arcade's numbers, but the same on each side.
- **float -> int:** `(int32_t)nearbyint(v)` in `wri32`/`wri16` (fist) and
  `(int32_t)v` in `sse_cvtt_i32` (range-checked). Out of range `(int32_t)` is
  undefined in C; arm64 `fcvtzs` saturates on both Apple and Android, x86_64
  gives 0x80000000. arm64 Mac <-> arm64 Quest agree; an Intel Mac may not.
  `nearbyint` uses the current rounding mode - round-to-nearest on both, nobody
  changes it.
- **Denormals:** arm64 FPCR.FZ is 0 by default on macOS and Android: denormals
  are kept on both. (x86_64 SSE also keeps them unless DAZ/FTZ is set; the
  runtime does not set them.)
- **NaN payloads:** arm64 with default-NaN off propagates the first NaN
  operand's payload on both. x86 SSE propagates differently for two NaN
  operands. Only matters if the game stores and compares NaN bits.
- **Compiler versions:** a different clang can schedule and fold constants
  differently; with contraction off and IEEE semantics (no `-ffast-math`, not
  used) the results of each expression are fixed by C's rules.
- **`long double`, `__builtin` math:** not used by the runtime's guest paths.
- **qsort:** the HLE's own insertion sort, not the host's (stable, the same everywhere).

## Measured (macOS, 2026-11-15, runtime 61e0a49)

**Netplay scenario table** (`scripts/vt3-netplay-test.sh`, two headless copies
on one Mac over localhost UDP, scene `versus` with a bot on each side, 110 s =
6240 input frames each: boot, 1P's match, 2P's challenge, the VS select and
the 1P-vs-2P match; two scenarios at a time; match hash compared every 60
frames):

| Scenario | Completed | Delay | Waits (host) | Desync | Match hashes host = joiner |
|---|---|---|---|---|---|
| clean | yes | 1 (2 -> 1 at frame 244) | 11 waits, 80 ms in 110 s | none | yes (103) |
| 20 ms / 5 ms jitter | yes | 2 | 930, 14.6 s * | none | yes |
| 60 ms | yes | 4 | 2194, 34.5 s * | none | yes |
| 2% loss | yes | 1 | 2826, 32.6 s * | none | yes |
| 10% loss | yes | 1 | 963, 10.9 s * | none | yes |
| 20% reordered | yes | 2 | 70, 0.1 s | none | yes |
| 350 ms stall | yes | 1 | longest 352 ms | none | yes |
| peer killed at 70 s | yes: `nothing from the other player for 5001 ms - session ended, playing on alone` | 1 | - | none | - |
| version mismatch (joiner Replays off) | yes: refused, `settings differ: vt3.replays=1 here, 0 there` on both | - | - | - | - |

\* run before the pacer fix (61e0a49): one side kept waiting part of every
frame, the two 60 Hz grids a frame apart - no slowdown (both reach frame 6240
in 110 s) but every frame's input then rides on the network's jitter. With the
fix, clean went from 4305 to 11 waits; the stall scenario still settles with
one side waiting most frames (open: the simulator's send queue is flushed on
the network thread's 5 ms poll, and the delay does not yet rise on waits).

**Replay** (scene `versus`, 150 s = 8760 frames, record once, replay twice):

| Pair | Match hash `[shash]` (146 hashes) | Memory hash `[hash]` | Flow log |
|---|---|---|---|
| replay vs replay | **identical, all frames 60-8760** | differs (pointer noise, below) | one loop change one display frame apart |
| recording run vs replay | identical except frame 420 (the same from 480 on) | differs | the same |

The boot transient after 1P's Start (MT draws at frame 391 in one run, 440 in
another) was the voices on the sound card's clock - fixed (table above).

**Mac <-> Quest (2026-11-16, runtime a825500):** a Mac recording of the
`versus` scene (150 s, 8760 frames) replayed on the Quest
(`LINDBERGH_INPUT_PLAY`, the same NVRAM pushed with it): before the CRI fix,
140 of 143 match hashes equal - only frames 480-600, the boot warning screen
ending later; the whole match identical. With the fix a Mac replay with a
slowed disk (`LINDBERGH_SLOW_IO=1,200`) is identical to the recording over
all 8700 frames. The scenario table again (two Mac copies): all 9 complete,
no desync, hashes equal; under jitter, loss and stall one side still waits
most frames (below, "Open").

The memory hash (`.data/.bss` less VT3's noise list) still differs between
any two runs: the loading thread outgrows its 352 MB heap
(`[mem] deterministic: thread heap 2 is full`) and its overflow goes to the
shared heap, whose order is not fixed - heap pointers in the scene and
animation databases. Netplay therefore compares the match hash by default.

## Next stage: a Quest joins a Mac

Done (2026-11-16): 1 (INTERNET; no multicast yet), 2 by env.txt (no panel page yet), 3, 4, 5. Left: the panel page, 6, 7, 8, and the waits below. What it needed, in order:

1. **Android manifest:** `<uses-permission android:name="android.permission.INTERNET"/>`
   (and later `CHANGE_WIFI_MULTICAST_STATE` + a `WifiManager.MulticastLock`
   for broadcast discovery) in `quest/vt3/src/main/AndroidManifest.xml`.
2. **Starting a session on the Quest:** env.txt `LINDBERGH_NETPLAY=join:<mac ip>`
   (unattended first), then a "Versus" page in the panel: Host / Join (IP),
   status (connected, RTT, delay, in sync), Leave. A session starts at the
   game's first frame, so choosing Host/Join restarts the game with it.
3. **Mac as the bot peer:** `LINDBERGH_NETPLAY=host LINDBERGH_BOT=2900,1`
   (and the menu taps) on the Mac; the Quest joins with a bot or worn. The
   joiner's coin-and-Start: `LINDBERGH_KEYS2` today; in the headset the
   joiner's trigger at the attract screen (as `xr_controls.c`'s `dual` join).
4. **The joiner's controls as player 2:** `xr_controls.c` `lever_buttons()`
   produces P1 bits; `netplay.c side_input()` already maps a joiner's P1 bits to
   P2, so nothing else is needed for input.
5. **Determinism across the two builds:** both built from one commit (the
   handshake checks the runtime hash), `-ffp-contract=off` and fdlibm already
   in. Expect the first Mac <-> Quest desync to name a remaining source
   (per-thread heap sizes on the Quest, GL-thread timing in Immersive).
   Record on the Mac, `adb push` the recording, replay on the Quest with
   `LINDBERGH_STATE_HASH=60` and compare the `[shash]` logs first - that tests
   the maths without a network.
6. **The far-end view** (each player at his own end): research stage 5,
   camera flip V1. Until then player 2 sees the court from 1P's end.
7. **Settings locked during a session:** the panel's Replays, Point cutaways,
   overlays and Mode change the simulation: hide or grey them while
   `netplay_active()`; view settings stay per player.
8. **Session layer later:** LAN direct UDP stays the first path. For Internet
   play, either a small UDP relay with LAN broadcast (Time Crisis 2 VR's
   approach) or room codes over a WebSocket relay (Quest 3 Strikers uses a
   Cloudflare Worker); a "fake friend" CPU peer for one-headset smoke tests
   (the Mac bot covers it now).

## Open (2026-11-16)

- **Waits under impairment:** with jitter, loss or a stall one copy often
  waits part of most frames (table: j20 6199 waits in 110 s); never a desync,
  but each wait is a frame that rides on the network. The pacer re-base after
  a wait (61e0a49) does not always settle the two frame grids. Next: raise the
  delay on repeated waits, and a median-of-pings starting delay.
- **Splash:** a button pressed once the game runs takes the headset's
  start-up splash down (36c76fc); it was only taken down by the picture's
  brightness, and a quick Start could keep it over a dark screen.
- **Session from the headset:** a Versus page (Host / Join by IP, status,
  Leave) instead of env.txt; the simulation settings (mode, replays,
  cutaways, overlays) locked while a session runs.

## Update 2026-11-17: in the headset, online, voice

- **Versus tab** in the headset panel (Play / Versus / Settings): host on the
  same Wi-Fi (found by a UDP broadcast on port 47100) or **online** with a
  4-digit room code shown big on the start-up screen until player 2 joins.
  The game restarts into the session (`../netplay.txt`, read once); the
  joiner adopts the host's settings (LS_QUERY / LS_SETTINGS); each session
  starts from fresh factory NVRAM.
- **Online** goes through a WebSocket relay, a Cloudflare Worker with one
  Durable Object per room (`lindberghrecomp/tools/netplay-relay`, the way
  Quest 3 Strikers does it): `LINDBERGH_NETPLAY_RELAY=wss://...`, modes
  `online-host[:CODE]` / `online-join:CODE`. Online input delay starts at 3
  frames (`LINDBERGH_NETPLAY_MIN_DELAY`).
- **Voice chat** (`voice.c`): Opus 24 kbit/s in 40 ms pieces behind a
  -38 dBFS gate held 300 ms, sent as LS_VOICE packets on the same link,
  never part of the lockstep; 60-240 ms jitter buffer; Quest mic through
  AAudio's VOICE_COMMUNICATION preset (echo cancelling).
- **72 Hz in a match**: the match's sound is mixed per input frame
  (deterministic), so a match below 60 fps sounds slow. VR on the busiest
  court (New York) makes ~50-53 fps at 90 / 120 Hz (the GL thread, ~11 ms of
  gl4es and driver work, misses the beat); at 72 Hz it holds 60. A session
  therefore runs the headset at 72 Hz (`LINDBERGH_NETPLAY_HZ` overrides).
- Each session records its input (`netplay_session.lgin`) so a desync can be
  replayed; one seen at a new game's start (frame 30000) also diverges on a
  Mac replay of the Quest's recording - open.
