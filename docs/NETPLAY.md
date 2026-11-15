# Netplay: two copies of the game in lockstep

Status (2026-11-15): **stages 0 and 1, macOS only.** Two headless Mac
processes play Virtua Tennis 3 versus against each other over UDP on
localhost. Nothing of this runs on the Quest yet (no INTERNET permission, no
panel); see "Next stage" at the end. The plan behind it:
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
| `LINDBERGH_KEYS2="frame:key[*n],..."` | scripted player 2: `z x c` buttons, `^ _ < >` lever, `2` Start, `6` / `5` a coin in chute 2 / 1 |
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
| The hash itself: host pointers in guest mutexes | the 12 bytes after hle_pthread's "LGJ1" magic are skipped |

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

## Measured (macOS, 2026-11-15)

Scene `versus`, a 150 s run (8700 input frames: boot, 1P's match, 2P's
challenge at frame 2300, the VS select, 1P-vs-2P to the second game), hash
every 60 frames. Recordings and logs under `/tmp/vt3np` (not kept).

| Comparison | Match hash `[shash]` (ball, players, score, MT) | Memory hash `[hash]` | Flow log |
|---|---|---|---|
| replay 1 vs replay 2 | **identical, all 145 (frames 60-8700)** | differs from frame 60 | one loop change 1 display frame apart (7742/7743): display frames, not input frames |
| recording run vs its replay | identical to frame 360, differs from 420 | differs from frame 60 | the same, one change 1 frame apart (5296/5297) |

What the memory hash still sees (`state_dump_diff.py`): heap pointers of
the uva animation database and the scene database list - the loading thread
(thread 2) outgrows its 352 MB heap and its overflow goes to the shared one,
whose order is not fixed. They are excluded from VT3's regions now; what is
left differing is being traced (HANDOFF 3.1).

**Unfinished (2026-11-15):** why the recording run parts from its replays at
frame ~400 (the replays agree); the memory hash's last pointers; the
two-process scenario table (`vt3-netplay-test.sh`) has not been run yet.
The Strikers study's lessons still to apply: the global MT reseeded per frame
from (match seed, frame) and a separate stream for the visual callers
(particles, crowd, voices); an audit of logic that reads the camera
(culling, the camera worker) - each VR player has its own view.

## Next stage: a Quest joins a Mac

What it needs, in order:

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
