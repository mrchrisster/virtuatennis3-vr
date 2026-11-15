# Local multiplayer / netplay for the Lindbergh recomps (Mac <-> Quest 3, then all games)

Read-only study, 2026-11-15. Nothing built, run or edited; no adb. Builds on
`versus-two-quests.md` (2026-11-12, VT3 only, recommended input lockstep)
and widens it: outside examples (Time Crisis 2 first), what the shared
runtime offers to every game, and two options that note dismissed too
quickly for the Mac <-> Quest goal (the Mac as a streaming host; replaying
the GL queue on the client). Runtime references are to
`lindberghrecomp/src/runtime/` here (the same runtime as
`lindbergh-recomp-ports`). **[V]** verified in code or in a cited source
today, **[G]** general knowledge, not re-checked against a source today,
**[I]** inferred, **[M]** only a prototype can tell.

Note on the owner's Reddit post
(`reddit.com/r/Emulationonquest/comments/1xqs5du/time_crisis_2_online_local_voice_chat_soon/`):
**reddit could not be fetched** (www, old and .json are all blocked for this
tool) and a web search for the title found nothing. Below, the TC2 project
is identified from its own GitHub pages, which fit the title exactly
("online / local / voice chat"): **DR-89/time-crisis-2-vr**. That this is
the project behind the post is an inference [I], not read from the post.

---

## The answer for the owner (one page)

**What Time Crisis 2 does.** The Quest Time Crisis II VR port (DR-89,
GitHub, MIT, source public) is a translated-to-C version of the arcade
board, like ours. Its online and local play works because **the arcade game
was built as two linked cabinets**: two complete boards, one per player,
each running its own copy of the game and drawing its own player's view,
joined by a serial cable. The port emulates that cable's chip and sends
what goes over it (one ~1 KB packet a frame) across the network. The
game's *own* link code keeps the two copies in step and puts up with
dropped or late packets. A small relay server gives you room codes; on
the same network the headset hosts by itself, and other machines find it
by broadcast. Voice chat (Opus) rides inside the same packets. The author
measured 16-35 ms ping and 1-2 frames of lag from a Quest 3 on home Wi-Fi
to a Windows PC. Arcade racers (Ridge Racer in MAME, OutRun 2 / Initial D
on Lindbergh in TeknoParrot and the Linux loaders) work the same way.

**Why we cannot copy it as is.** None of our six games has a cabinet link.
Virtua Tennis 3, House of the Dead 4 / 4 Special / EX, Let's Go Jungle and
Ghost Squad Evolution are all **two players on one cabinet, one screen**.
So there is no game-made link to carry. The other player has to be
"player 2 on the same cabinet, but somewhere else".

**What fits us. Two routes, used one after the other:**

1. **First: the Mac runs the game, the Quest joins as player 2 ("host
   streaming").** The Mac runs the one and only copy of the game with both
   players. That already works today on one cabinet: two pads on the Mac.
   The Quest sends its controller to the Mac, a few bytes a frame, and gets
   the picture back. Nothing has to be made deterministic, so it works for
   **every** Lindbergh game at once. Wi-Fi spikes cannot make the two sides
   drift apart, because there is only one game. The cost is delay and
   image quality on the Quest side. Your button reaches the Mac and the
   picture comes back through the video encoder: about 40-70 ms more than
   playing locally [G], like Air Link or Virtual Desktop.
   - Two ways to show the picture on the Quest:
     - **(a) Video.** Simplest. The Mac's hardware encoder makes it cheap,
       and the Quest decodes it easily. Shown on a big screen in VR at
       first, later as a stereo view with head-turn correction.
     - **(b) The Mac sends its drawing commands, and the Quest draws them
       itself (the "GL stream").** The Quest then renders true stereo VR
       with its own head tracking, as sharp as the native port. Only the
       game's own updates lag; head movement does not. This is the most
       interesting generic option. Our runtime already packs every GL call
       into a queue for its render thread, and that queue is the format
       that would go over the network. It is also real work and needs a
       bandwidth test (see G).
2. **Later: both devices run the game, swapping only button presses
   ("lockstep").** This is what the 11-12 study recommended for two
   Quests. It feels best (2-3 frames of delay, full native picture on
   both), and Quest-to-Quest is the case it was made for. But it needs the
   two copies to compute bit-identical results, and Mac vs Quest is the
   hardest case: different maths library, different `rand()`, different
   heap layout. The **shared part is generic**: the input exchange at the
   JVS board, which every game reads the same way. The determinism fixes
   are per game.

**What you would get first.** VT3 on the Mac with two players (stage 0,
exists today with two pads), then the Quest joining a game the Mac hosts,
as player 2, over home Wi-Fi. The Quest player sees the arcade's own shared
screen in VR, on a big flat screen at first (stage 2). That is the
original arcade versus: one screen, both players. The same build then
works for HOTD4 / LGJ / GSE co-op with the Quest's gun as player 2's gun.
The Quest's aim is computed on the Quest from what it sees, so it shoots
where you point.

**Effort, roughly (agent-days):**

| Stage | What | Effort |
|---|---|---|
| Stage 0 | Two players on one Mac, plus scripted P2 | about 1 day |
| Stage 1 | Network input layer, Mac host / Mac client | about 3-5 days |
| Stage 2 | Video to the Quest on a flat screen | about 5-8 days |
| Stage 3 | GL-stream client on the Quest (true VR for P2) | about 2-4 weeks, uncertain |
| Lockstep | Per game, plus a cross-platform maths library | about 2-3 weeks for VT3 Mac<->Quest; less for Quest<->Quest |

**Risks.**
- The streamed player's delay might feel too slow for tennis timing. Only
  you can judge that, worn. The gun games are more forgiving.
- Home Wi-Fi spikes. The TC2 author needed 8-12 frames of slack to stop
  hitches at 5% loss / 150 ms jitter.
- The GL stream's bandwidth during loading (texture uploads).
- For lockstep: Mac vs Quest maths, plus game threads we do not control.
- Quest apps need the INTERNET permission added (none of ours has it today).

---

## Part A - outside examples

### A1. Time Crisis 2

**Arcade (Namco System 23, 1997)** [V: DR-89 `docs/ONLINE.md`]

- **The link:** Time Crisis II was a twin cabinet: two full boards, each
  running its own game and drawing its own player's view, joined by an
  RS-422 cable through the board's **C422** link chip (16 KB buffer RAM,
  eight registers, IRQ3).
- **What is synchronised:** the game's own driver builds one packet a
  frame and sends it three times. It has its own checksum, resend count
  and timeout: the partner counts as lost after 16 frames without a packet,
  and the game recovers when packets return. Keith (P1) and Robert (P2) see
  each other in the scene and keep their own scores.
- **Why it was feasible:** the game was *designed* to tolerate a lossy,
  free-running link between two independently clocked machines. Each
  cabinet is authoritative for its own player, and the game protocol
  reconciles the rest.

**PS2 (2001)** [G; co-optimus.com listing: "LAN Play or System Link 2
Players"]

- Two consoles, two TVs, two discs, joined by an i.LINK (FireWire) cable:
  the same twin-cabinet design. It is not emulated by PCSX2 as far as any
  source found shows (PCSX2 wiki page, no netplay/link mention found).

**MAME (System 23 / C139 / C422)**

- Mainline MAME has only stubs for the Namco link chips [V: jamesfmackenzie.com
  2026-08-14 article, C139 stub ~113 lines; DR-89 says MAME only stubs C422].
- Forks have carried the chip's traffic over TCP between instances for Ridge
  Racer and Rave Racer. Reported problems: frame sync, late data (side-screen
  road clipping) and packet drops [V: same article]. A forum post reports a
  two-instance TC2 link in a WIP build [V: forum excerpt via search; page
  itself 403].

**namco22-decompile (spacestate1, desktop Linux/Windows)** [V:
`github.com/spacestate1/namco22-decompile`, `docs/NETPLAY.md`]

- A decompiled/translated System 22/23 engine; TC2 online in 0.9.x-0.10.x.
- **Protocol "NMN2":** UDP port 27750, a small Rust relay/lobby server
  (`nmn-server`) and a built-in LAN host. LAN discovery is a DISCOVER
  broadcast answered by ANNOUNCE.
- **Rooms:** HELLO with AUTO/JOIN/CREATE, slots = cabinet numbers, READY /
  START / GO control messages (resent every 500 ms), ping at 1 Hz, a member
  silent for 5 s is dropped. Rooms are keyed by game id + link version +
  frame size (that is the version check).
- **FRAME payloads are opaque link-chip traffic**, one per frame, never
  retransmitted: a newer frame supersedes a lost one.
- **Sync is free-running by default.** An optional `eng_net_wait(max_lead,
  timeout)` stalls a machine that is more than `max_lead` frames ahead of
  the slowest peer. The lead is 2 + ping in frames. No input delay, no
  desync detection: the game's link protocol handles it.

**Time Crisis II VR (DR-89, Quest 3 + PCVR + desktop, MIT, public)** [V:
`github.com/DR-89/time-crisis-2-vr`, README, releases, `docs/ONLINE.md`]

- **Base:** the US TSS3 Ver. B arcade program, built on namco22-decompile
  ("native arcade MIPS and H8 code translated to C"). The OpenXR host comes
  from the author's earlier Time Crisis VR. This is the closest project to
  ours.
- **Online and local play (v0.4.0, 13 Nov 2026; v0.4.1 the same day):**
  - Their own C422 model (`quest/tc2_link.c`) is wire-compatible with
    upstream, so Quest, PCVR and desktop players share rooms.
  - Ways in: room code via the community relay `zonesync.net:27750`,
    browse, quick match, LAN host with broadcast discovery, join by IP.
  - Each device runs the full game. Host = P1 Keith, joiner = P2 Robert.
    The cabinet side is agreed through a side block in every frame.
- **The payload:** one 1 KB UDP datagram per arcade frame (about 62 KB/s each
  way). It holds:
  - the newest link frames that fit, so every datagram repeats recent ones
    and a lost datagram costs nothing;
  - a voice block (Opus 20 kbit/s with FEC, SpeexDSP echo cancel, RNNoise),
    which takes room only from the repeated old frames;
  - a side block, a state trailer and the frame number.
- **Lead:** stall-and-wait with a lead of upstream's 2 + ping, **plus 6
  more, up to 12 frames**.
  - Measured at 5% loss / 150 ms jitter over 1.5 min: upstream's lead
    paused 26-28 times; a lead of 8 paused 7-9 times; 12 paused 2-4 times.
  - Their VR host **keeps rendering the headset while it waits** (it asks
    before each arcade frame instead of blocking inside the network call).
- **They tried reliable ordered delivery and took it out:** the backlog after
  a stall outgrew the resend history, and the game went 17 frames without
  link traffic, which it counts as "link lost". Lesson: for frame data,
  redundancy beats retransmission.
- **Keeps running** behind menus, with the headset off and in the background
  while linked (the partner needs it). A keepalive timer covers game-thread
  stalls beyond the lobby's 5 s eviction.
- **Drop-in "stand-in" partner:** an idle fake second cabinet answers on the
  link, so P1 can start SOLO/LINKED alone and a friend joins later. P2's
  arcade restarts once for the power-on handshake. P2's coin and trigger
  are held 25 s after P1's start. Both sides apply that rule.
- **VR views:** each headset is its own cabinet, so each player gets their own
  full native VR view of their own screen. The author notes the "SELECT
  GAME MODE" banner art is cut off, because the twin screens once stood
  side by side.
- **Latency measured:** Quest 3 host on home Wi-Fi with a Windows desktop
  joiner: 16-35 ms ping, 1-2 frames of link lag, 0 game errors. Through
  the internet relay: ~50 ms ping.
  - Not yet tested (the author's list): Quest-to-Quest, PCVR, playing
    linked while wearing the headset, voice quality by ear.
- **Test harness worth copying:** `tests/test_online.py` runs two real desktop
  instances side by side in real time, on "lanes" (each with its own
  cabinet folder and lobby port). Pieces:
  - scripted coins, start and shots;
  - WAV files in place of the microphone;
  - 25 scenarios (badnet, freeze 3 s / 8 s, leave/rejoin, late join,
    crossplay with upstream's release);
  - checks on the game's own link counters;
  - switches `TC2_NET_SCRIPT="600:hostroom;2400:mute"` and
    `TC2_NET_SIM=loss%,stall_ms`, and a `[LINKHEALTH]` log line every 30 s.

**Lessons for us**

- TC2 is a *native link* (architecture A in the 11-12 note). We do not have
  one, so the TC2 mechanism itself does not transfer.
- Its engineering transfers almost entirely:
  - UDP, one packet a frame with redundancy instead of retransmission;
  - a lead/stall budget sized for Wi-Fi spikes (8-12 frames for a
    link-tolerant game; lockstep needs much less slack per frame but
    stalls instead of absorbing);
  - keep rendering the headset while the game waits;
  - room/LAN discovery with a game+version key;
  - keepalive past stalls;
  - voice inside the game packets;
  - a scripted two-instance desktop test with simulated loss;
  - joining handled at the coin/start level of the game.
- Their Quest-to-PC numbers (16-35 ms ping on home Wi-Fi) are the best real
  data point we have for our Mac <-> Quest link.

### A2. Emulator netplay architectures

| Project | How the link works | What is synchronised | Latency handling | Lesson |
|---|---|---|---|---|
| MAME linked cabinets (forks) | Emulated comm chip (C139/C422) traffic over TCP/UDP between instances [V A1] | The games' own link packets | The game's protocol; stalls/late data cause glitches | Native link only; needs the original game to have one |
| Supermodel (Model 3) | Emulated network board between instances over sockets, in its net builds [G] | Link-board traffic (Daytona 2, Scud Race, ...) | Game protocol | Same as MAME |
| Lindbergh link titles (OutRun 2 SP SDX, Initial D 4/5, R-Tuned, Race TV) in TeknoParrot / lindbergh-loader | The games use real sockets on the board's Ethernet. The loader passes them to the host network; you set IP, link ID and cabinet count in the test menu [V: Batocera Lindbergh wiki, TeknoParrot wiki via search] | Game-level link | Game protocol | Lindbergh *has* a native link path, but only racing/fighting titles use it, none of ours (VT3 imports no socket API [V 11-12 note]) |
| Flycast (Naomi/Atomiswave) | GGPO rollback "on the system/emulator level using save states" for fighters; Naomi network link for linked games "patchy" [V: wiki.gbl.gg Flycast GGPO, arcadecontrols forum via search] | Inputs (rollback) / link traffic | Rollback: zero added delay; Dojo falls back to delay netcode | Rollback needs cheap full savestates |
| Dolphin | Deterministic lockstep: inputs exchanged with a pad buffer (input delay); settings, saves and memory cards synced at start; desync detection by comparing state hashes (with a notice) [G] | Inputs only | Fixed buffer, stall when late | Our model for (L). Its known pain is cross-platform/CPU float differences and settings mismatches [G] |
| RetroArch netplay | Rollback using the core's serialize (savestate), plus configurable input latency frames; host-assisted resync by sending a savestate on desync [G] | Inputs + state resync | Rollback / delay | Needs a core with small fast deterministic savestates. Desync repair = send state |
| GGPO (library) | Rollback: predict the remote input, run ahead, and on a mismatch load state and re-simulate up to ~8 frames [G] | Inputs | Hides latency | Needs save, load and advance of the *whole* game state many times a frame, deterministic. Not us (see R) |

### A3. Static-recompilation / decompilation ports with multiplayer

- **N64Recomp ports (Zelda64Recompiled etc.):** no official netplay found
  [G]. A recomp keeps the original memory and logic, so the path open to
  them is lockstep or memory-level state sync, not a netcode rewrite.
- **Ship of Harkinian "Anchor" (OoT, decomp-based):** *not* lockstep. It is
  co-op at the save-flag level: joining loads a remote player's save, then
  flag sets and item gives go to all players, and each plays their own
  world [V: garrettjoecox/anchor via search]. Only possible because the
  decomp gives named game state.
- **sm64ex-coop / sm64coopdx (SM64 decomp):** a real netcode rewrite.
  Per-object sync with owners, player state replication, custom
  host/client logic [G]. Again needs source-level understanding of every
  object; not feasible generically for a recompiled binary.
- **TC2 VR (A1):** a translated binary with a *native* link, the case that
  needs the least game knowledge.
- **What a recompiled (not decompiled) game allows:**
  - (1) native link if the game has one;
  - (2) input lockstep (needs determinism, not understanding);
  - (3) one instance + remote viewer (needs neither);
  - (4) narrow state patches for known structures (VT3's ball and player
    roots are known, B3 in the 11-12 note) as a repair, not a base.
  State replication like sm64coopdx is out of reach generically.

### A4. Cross-platform determinism in practice (ARM64 Android vs ARM64 macOS)

- **Floats in our recompiler [V]:** `pcrecomp/tools/lift/lift32_cpu.py`
  models x87 registers as host `double`. The lifter's own comment says
  widening loads/stores is harmless for compiler-emitted code. So the
  original's 80-bit extended precision is *not* reproduced, but both our
  hosts compute the same `double` C code.
  - Transcendentals go to host libm: `fsin -> sin`, `fcos -> cos`,
    `fptan -> tan`, `fpatan -> atan2`, `fsincos`, `fyl2x -> log`,
    `f2xm1 -> pow` (lines ~843-850).
  - Imported `sin/cos/acos/pow/sinf/cosf` go to host libm (`hle_libc.c`).
  - SSE: `rcpss` = exact `1.0f/x` (deterministic on our hosts).
  - `fldcw` stored (`cpu.h` 541).
- **Risk 1, libm:** Apple's libm and Bionic's (`sin`, `cos`, `atan2`, `pow`,
  `log`) are not guaranteed to round the same in the last bit [G].
  - Fix: one bundled implementation (fdlibm/musl or CORE-MATH; correctly
    rounded avoids the question) called from both the lifter's emitted
    code and the HLE.
  - `sqrt`, `+ - * /` are IEEE-exact and safe.
- **Risk 2, FMA contraction:** clang's default `-ffp-contract=on` fuses
  `a*b+c` within an expression on arm64. Apple clang and the NDK's clang
  are different versions and may fuse differently [G].
  - Fix: `-ffp-contract=off` for lifted code and the runtime on both.
  - No such flag in the CMake files today [V: grep].
- **Risk 3, host `rand()` [V]:** `hle_libc.c` `h_rand`/`h_srand` call the
  *host's* `rand()`. Apple and Bionic generators differ [G], so any game
  using libc `rand()` (VT3 imports it) diverges at once.
  - Fix: a bundled generator (glibc's TYPE_3 `random()` would also match
    the original Linux behaviour).
- **Risk 4, time [V]:** `time()`, `gettimeofday()` (libc HLE and the raw
  syscall) return host real time. In lockstep they must become a function
  of the agreed frame (e.g. session epoch + frame x 16.683 ms), at least
  for the callers that feed logic (VT3's seeds via `_sSystem::getTime`).
- **Risk 5, heap layout and uninitialised memory [I]:**
  - The guest heap is one dlmalloc mspace that the *runtime also allocates
    from* (`guest_alloc` for host objects handed to the game, the 16 MB GL
    ring, strings). Mac and Quest take different HLE paths (gl4es vs
    desktop GL, file system, Vulkan vs GL). So the game's own allocations
    land at different addresses, and freed memory has different leftover
    content.
  - Game logic that orders by pointer (sorting, pointer-keyed maps) or reads
    uninitialised heap would diverge.
  - Fix: a separate mspace for runtime allocations, so the game's heap
    sequence depends only on the game; zero-fill on `malloc` in netplay
    mode.
- **Risk 6, threads [I/M]:** guest threads are real host threads
  (`hle_pthread.c`). VT3's framework thread and main thread hand over
  with events (deterministic if strict). Loader, sound (ADX/CRI, SEGA API)
  and LGJ's worker run free. Logic that branches on "has the loader / the
  sound finished" at a frame count is timing-dependent. Mac and Quest load
  at very different speeds, which makes this worse than Quest-Quest.
- **How emulators get determinism [G]:** a single-threaded core stepping
  devices on an emulated clock, software or carefully emulated FPU, the same
  binary/libm on all hosts, virtualised time, and RAM initialised to a
  known pattern. We have none of that for free: our game runs natively on
  host threads with host libm. That is the real price of lockstep across
  platforms.

---

## Part B - what the Lindbergh runtime offers generically

### B1. The one chokepoint: the JVS board [V]

- **Every game reads its cabinet through `hle_sega.c` `jvs_command()`:**
  - 0x20 switches (test byte + `players` x `bytes`, `jvs_switch_byte()`);
  - 0x21 coins (2 slots, counters only ever go up);
  - 0x22 analog (gun 1 on channels 0/1, gun 2 on 2/3; 16-bit scaled, high
    byte sent);
  - 0x23 rotary (zeros).
- **Each read calls `host_cabinet_input(&CabinetInput)`** (desktop
  `host_sdl.c` 553; the other host `hle_window.c` 173), which fills
  `{coins[2], buttons (32-bit, both players: cabinet_buttons.h), gun_x/y,
  gun2_x/y, gun2, screen_w/h}`.
- **The full two-player cabinet state is ~16 bytes:** one button word,
  2 coin counters, 4 gun values. Per player: ~7 bytes (its half of the
  button word, its coin delta, its gun x/y).
- **Side doors (must be routed through the same layer):**
  `host_cabinet_buttons()` is read directly by game hooks (HOTD4 / HOTD4SP /
  HOTDEX `host.c` reload and gun-acceleration overrides, `hle_sega.c`).
  The gun position also feeds stereo.c for drawing the sight (local
  only, fine).
- **Gun aim is view-independent at this layer:** the analog value is "where
  on the game's 640x480-ish screen", and the gun games' camera is shared by
  both players. A remote player's aim, computed on their device from their
  own view (the Quest's aim uses its own depth read / HUD crossing,
  `aim_on_hud`, `depth_read` in `game_profile.h`), is correct for both
  instances. That makes the gun games the cleanest generic case.
- **2P today:** `xr_controls.c` `dual` = one person with two guns as P1+P2
  (off-hand trigger joins with an auto-coin and P2 Start). `joystick` (VT3)
  = P1 only. The desktop's second SDL pad is P2 (`host_sdl.c` `g_pad[2]`).
  Scripted P2 already exists (`host_sdl.c` `cabinet_p2_test`: coin, P2
  Start, gun-2 sweep).
- **A generic netplay input layer** sits inside `host_cabinet_input()` /
  `host_cabinet_buttons()`: local device = one side, remote = the other,
  merged into one `CabinetInput` per frame.
  - (H) host streaming: merge the newest remote input. No timing rule.
  - (L) lockstep: return the agreed pair for frame N, latched once per
    frame, and block at the frame boundary until the peer's input for N
    is in.
- **What "a frame" is generically:** `g_frame++` happens only in
  `hle_window.c:376` (the swap path; `host_swap`). That is the one counter
  shared by all games. The frame boundary for latching = swap. Open [M]:
  - whether every game polls JVS once per frame, on the frame's thread (VT3:
    the main thread's `_sInterface::execute`; gun games unknown);
  - if a game polls on an I/O thread at its own rate, lockstep needs that
    poll tied to the frame. `LINDBERGH_JVS=1` plus a thread id per read
    answers it.

### B2. Per game

| Game | 2P on one cabinet | Cabinet link | Determinism notes |
|---|---|---|---|
| VT3 | Versus (2P breaks in with coin + Start), co-op doubles vs CPU [V 11-12 note] | none: no socket imports [V] | Clock-seeded MTs, one global MT shared by menus/effects/logic, libc `rand` import, flow settings change loops, worker threads, load loops poll [V/I 11-12 note] |
| HOTD4 | 2-gun co-op (P2 gun on analog 2/3, P2 reload/start) [V `host.c`, `xr_controls.c dual`] | none known [I: one-cabinet game; imports not checked, generated lists not in repo] | GL thread on; logic timing, RNG source and threads unverified [M] |
| HOTD4 Special | 2-gun co-op (ride cabinet) [V `host.c` player per gun] | none known [I] | As HOTD4; decrypts a block under a fresh random IV (`host.c` 43: harmless if not logic) [M] |
| HOTD EX | 2-player (guns + pedals on player 1's byte) [V docs/hotdex/MACOS.md, `host.c`] | none known [I] | Unverified [M] |
| Let's Go Jungle | 2-player co-op, one gun each [V `host.c` calibration P1/P2 channels] | none known [I] | Paced by vsync originally (`host_pace_fps`); worker thread spawned at start (`hle_pthread.c` header); sound library unlocks mutexes across threads (docs/lgj) [V]: threads matter [M] |
| Ghost Squad Evolution | Two guns on one cabinet [G; the port's `xr_controls.c dual` path applies; player count/link not verified] | unverified [M] | One-CPU-thread-bound; unverified [M] |

- **Common to all:** the game logic is 60 Hz frame-stepped [I: arcade
  convention, verified for VT3 in play]. Loading is where devices
  differ most, and the gun games load between stages (HOTD4 "2-3 s",
  GSE "loads ... programs", docs).
- **Under (H) none of this matters:** one instance, real time, as today.

### B3. Architectures compared ("works for all Lindbergh recomps")

#### (L) Deterministic input lockstep at the JVS layer (+ state hash)

- **Generic part [I]:** the transport, the session, input exchange with
  delay D, the frame barrier at swap, latching in `host_cabinet_input`,
  virtual time for `time`/`gettimeofday`, a bundled `rand`, bundled libm,
  `-ffp-contract=off`, a separate runtime heap, and a hash of selected
  guest memory (a per-game list of ranges, or a page hash of the image's
  .data/.bss) for desync detection.
- **Per-game part:**
  - clock seeds and RNG split (VT3: about 10 wraps);
  - flow settings locked by the host;
  - finding thread/load races [M];
  - for VR: each copy's own view (VT3: camera flip for the 2P end;
    gun games: nothing, shared camera).
- **Quality:**
  - delay D = 2-3 frames for both players; full native VR on both;
    ~20 kbit/s;
  - Quest-Quest is the natural fit (same APK = same maths);
  - Mac-Quest is the hard case (A4 risks 1-5).
- **Failure mode:** a desync is unrecoverable without a state transfer. The
  match ends ("out of sync").

#### (R) Rollback

- **Guest RAM is one region** [V `guest_mem.c`: 4 GB window, image at
  0x08048000, heap 0x20000000-0xB0000000, stacks inside]. So a *guest*
  snapshot is conceptually easy: touched pages + each guest thread's CPU
  struct. Dirty-page tracking with `mprotect` would make it incremental.
- **Not feasible as a real rollback:**
  - The whole state also includes host-side state: GL objects created or
    changed in the frames being redone, the GL queue in flight, audio
    voices already playing, the loader's open files and threads, HLE
    statics, guest threads blocked inside host calls.
  - Re-simulating 3-8 frames would draw and play sound twice, and must run
    several frames inside one 16 ms frame. The Quest's game thread already
    takes ~13 ms for one.
- **Verdict:** no [I], as the 11-12 note said.
- **What is useful from it:** a *one-shot* guest snapshot for **desync
  recovery** or **late join** in (L): host sends its guest RAM delta, the
  client loads it between frames. That still runs into the host-state
  problem: GL objects must already match, which only holds if both are
  in the same scene. That makes it a research item, not a plan.

#### (H) Host-authoritative streaming (one instance, thin client)

- **One instance runs the game with both players.** That is today's "2P on
  one cabinet", already working on the desktop with two pads. The client
  sends its `CabinetInput` half (a few bytes, ~60-120 Hz) and receives
  the picture.
- **No determinism needed.** It works for every Lindbergh game
  immediately, and it cannot desync.
- **Host = the Mac:**
  - spare CPU/GPU;
  - hardware H.264/HEVC encode (VideoToolbox) with low-latency modes [G];
  - the Quest decodes HEVC in hardware (Air Link / Virtual Desktop / ALVR
    do exactly this) [G].
- **Picture options:**
  - **H1 flat:** the game's one framebuffer, ~1280x720-1920x1080 at
    60 fps, ~15-30 Mbit/s. Shown on a virtual screen in the Quest. The
    client is not true VR, but the head moves freely and costs no latency.
  - **H2 stereo video:** the Mac renders both eyes for the client's head
    pose (sent with the input; the Mac's stereo path today is "no picture
    test for VT3", guide 475, so this needs work). Encode 2 eyes, then
    reproject for head rotation on the Quest (timewarp). Video quality and
    ~40-60 ms pose age [G].
- **Latency for the client:**
  - input: Wi-Fi up ~3-10 ms; game: the frame it lands in;
  - picture: encode ~5-10 ms, Wi-Fi down ~5-15 ms, decode ~5-10 ms,
    display ~10 ms;
  - total ~35-70 ms button-to-photon over local play [G; TC2's measured
    16-35 ms ping Quest<->PC is the network part].
  - The host player has zero added delay. That is unfair in versus. In
    co-op it matters little.
- **Quest as host (Quest-Quest):** the Quest is already near its limit
  (VT3 ~13 ms game thread). Adding encode, and in H2 a second pair of eye
  views, is heavy and hot. Not recommended [I]; Quest-Quest goes to (L).

#### (G) GL command stream replication (the most interesting generic option)

**Idea:** the host runs the game. Its GL queue (`gl_thread.c`) is already
serialised: every call becomes a record `{size, kind, id, seq, fn, args}`
with its arguments copied (exact dword count per call), plus arrays of
known size (matrices, uniforms, multi-draw counts). Only calls that answer
(glGet*, glGen*, glMapBuffer) and client-memory draws are synchronous
[V header].
- The host sends that stream. The client (with the same runtime, the same
  `hle_gl*` handlers and its own stereo.c) replays it.
- The client applies **its own head pose**, as the native port does today:
  stereo.c reprojects the game's single camera per eye (`eye_projection`),
  and the game draws once.
- **The client gets true VR at native sharpness.** Head motion is local
  (zero added latency); only game updates are ~1 RTT + 1 frame late.
- **For the gun games this is ideal:** the camera is shared anyway. The
  client's aim comes from its own render (its own depth read), sent back
  as P2's gun.
- **For VT3:** the client sees the same broadcast camera (the arcade's
  shared screen), not its own end.
  - A world turn in the reprojection (V2 in the 11-12 note) could give
    "my end", with the screen-space shadow mask wrong.
  - Or the host flips its camera for the client (impossible: one camera).

**Feasibility, honestly:**

- **Synchronous calls:**
  - The host answers them from its own GL (it renders too, or runs
    headless with a real context). The client replays and discards answers.
  - Object names: the client must hand out the same names. It does if it
    replays every glGen* in order (replay the answer, i.e. send the names
    the host got).
  - Harder: calls whose *results* feed later arguments (a mapped
    buffer pointer, then writes into it) must be sent as data: "buffer N
    now has these bytes" at unmap.
- **Pointers into guest memory:**
  - Records point to their copies inside the ring (guest addresses). The
    client needs the same ring layout, or a rewrite of pointers to its own
    copy: doable, the ring is in guest memory on both.
  - Client-memory draws read vertex data at the draw. The host would have
    to send the referenced range (size from the draw's count and the array
    stride).
- **Bandwidth [I, needs measuring]:**
  - HOTD4SP: ~35,000 calls a busy frame, GSE 15-25k [V docs].
  - At ~20-40 bytes a call on the wire (id + args, without the ring
    header), that is 0.7-1.4 MB a frame = 40-85 MB/s = 340-680 Mbit/s raw.
  - Frames repeat almost exactly (the same call sequence, changed matrices
    and uniforms). A diff against the previous frame plus LZ4/zstd should
    take that down 10-30x [G for typical API-trace compression] = ~20-60
    Mbit/s, comparable to video.
  - Plus per-frame dynamic uploads (skinned vertices if done on the CPU,
    streamed textures, movies: HOTD4's SFD cutscenes are decoded on the
    CPU and uploaded = video-sized raw).
- **Loading:** stage loads upload tens to hundreds of MB of textures and
  buffers. At ~200-400 Mbit/s of real Wi-Fi throughput that adds seconds
  per load.
  - Mitigation: the client has the same game files. A content-hash cache:
    upload records carry a hash, the client pulls from its cache
    (populated across sessions). Or compress (DXT/BC data is already
    compressed).
- **Late join:** the client needs every live GL object, so join at boot or
  on a resend of all live objects (a "GL snapshot": the queue knows what
  was created).
- **Audio:** the host's game makes the sound. Send it too (Opus/PCM
  ~1.5 Mbit/s) or let the client mute. Small.
- **Two renderers:** the queue also feeds the native Vulkan renderer
  (`render_queue.h`) [V]. The wire format is the guest GL ABI, so a GL
  host can drive a Vulkan client and vice versa, in principle.
- **Prior art:** remote-GL stream systems (WireGL/Chromium, GLX
  indirect rendering, apitrace replay) work on LANs. The usual killers are
  synchronous round trips and uploads [G]. Our queue already removed the
  round trips from the hot path (6 answering calls a frame in HOTD4SP)
  [V]. That is why this is plausible here where it is not for arbitrary
  apps.
- **Verdict:**
  - The only generic route to *true VR for both players* without
    determinism.
  - Plausible, unproven.
  - Gate it on a measurement: record one busy frame's queue to a file
    (bytes, call count, upload bytes; compressed size with zstd and with a
    frame-to-frame diff) on the Mac, for HOTD4SP and VT3. That is a half-day
    tool, and it decides G.

#### Summary

| | Determinism | Works for all games | Client sees | Client delay | Host delay | Wi-Fi | Quest-Quest | Effort |
|---|---|---|---|---|---|---|---|---|
| L lockstep | required (per game, Mac-Quest hardest) | per-game work | native VR, own view | D frames | D frames | 20 kbit/s | best | medium per game + generic core |
| R rollback | required + snapshots | no | - | - | - | - | - | not feasible |
| H1 flat video | no | yes, now | flat screen in VR | ~40-70 ms | 0 | 15-30 Mbit/s | poor (encode on Quest) | low-medium |
| H2 stereo video | no | yes | stereo video, reprojected | ~40-70 ms (head: reprojected) | 0 | 30-60 Mbit/s | no | medium-high |
| G GL stream | no | yes (gun games best) | native VR, host's camera | game ~1 RTT+1 frame; head 0 | 0 | ~20-60 Mbit/s [M] + loads | Quest host possible (no encode), bandwidth [M] | high, uncertain |

### B4. Recommendation

- **First, for Mac <-> Quest VT3:**
  - H with the Mac as host, H1 flat video, behind a generic input layer.
  - Then measure G and, if the numbers hold, replace the video with the GL
    stream for true VR on the client.
  - This gives the owner something playable quickly in every game, with
    the Mac he already uses, and no determinism work.
- **The generic layer for all Lindbergh games is the same in both routes:**
  a `net_session.c` + `net_input.c` in the runtime, host-neutral C, plugged
  into `host_cabinet_input()` / `host_cabinet_buttons()`. It is what (L)
  needs too, so nothing is thrown away. Quest-Quest VT3 versus later = (L)
  on top of the same layer.
- **Discovery and pairing:**
  - Manual IP in the settings panel / env first.
  - Then a UDP broadcast DISCOVER/ANNOUNCE on one port, as NMN2 does. The
    Quest needs a Wi-Fi `MulticastLock` to *receive* broadcasts [G].
  - mDNS/Bonjour (`_lindbergh._udp`) is nicer on the Mac but adds NSD on
    Android. Broadcast is simpler and proven by TC2.
  - Note the "AP/client isolation" and 2.4/5 GHz band-split routers that
    block broadcasts (TC2 troubleshooting): manual IP stays as fallback.
- **Transport:**
  - **Input:** UDP, one datagram per client frame carrying the last ~8
    frames of input (redundancy, no retransmit), sequence number, ack of
    the last host frame seen, send timestamp, echo (NTP-style RTT).
  - **Control** (hello, version, settings, start, leave): small reliable
    layer, resend every 250-500 ms until acked.
  - **Video (H):** UDP with FEC or a simple slice-loss policy (as ALVR/Moonlight
    do) [G], or TCP_NODELAY on a dedicated socket for the first prototype
    (simpler; stalls on loss, acceptable on a clean LAN).
  - **GL stream (G):** must be reliable and ordered, so TCP_NODELAY, or QUIC
    later.
- **Session flow:**
  - **Host:** the Mac (H/G) / either (L). The host is always 1P (side 0),
    the joiner 2P (side 1).
  - **Lobby:** a "Multiplayer" page in the settings panel (both hosts have
    one): Host / Join (found list + IP), status (connected, RTT, delay or
    stream bitrate, sync state), Leave.
  - **Join / coin / start:**
    - The client's controller drives the P2 bits. With Coins Automatic the
      client's first Start sends a P2 coin and P2 Start, reusing
      `xr_controls.c`'s `dual` join logic (trigger: coin, then P2 Start
      150-450 ms later) but with the remote player's input.
    - VT3: 2P coin + Start = "here comes a new challenger", as the arcade.
    - Gun games: P2 joins mid-game as on the cabinet.
    - Free play in the test menu avoids coins entirely.
  - **Pause/menu:** the games have no pause. The client's panel blocks only
    its own input (`f->blocked` already does that locally).
  - **Headset off:** like TC2, keep the client's session alive and release
    its controls. The host's game goes on with P2 idle. VT3 versus: the
    CPU does not take over, so the client loses points. Show "partner
    away".
  - **Disconnect:** P2 just stops pressing. The game continues, P2 times
    out at continue as on a cabinet. Reconnect = rejoin the same host.
- **Settings and save sync:**
  - H/G: none. The host's settings, NVRAM and IC card (`vt3_save.c`) are
    the only ones. The client keeps only its view settings (height, laser,
    screen size).
  - L: host's flow/arcade settings and both card records at the handshake
    (11-12 note C3/C4).
- **Version check:** handshake carries a protocol version, the runtime git
  hash, the game id and the game ELF's SHA-256 (`SHA_FILE` in game.conf).
  Mismatch = refuse with a clear message.
- **Security:** LAN only. Bind to the LAN interface, accept only RFC 1918 /
  link-local peers, one session at a time, no listening port outside an
  open "Host" session, and a session nonce in every packet.
  - Quest: add `android.permission.INTERNET` (and
    `CHANGE_WIFI_MULTICAST_STATE` for discovery). None of the manifests
    has INTERNET today [V merged manifest].
  - macOS: the app may trigger the firewall prompt once.

### B5. Staged plan (each stage useful and testable alone)

**Stage 0 - local 2P on one Mac (exists; make it testable).** ~1 day.
- Already there: two SDL pads, P1/P2 keys, `cabinet_p2_test`.
- Add a scripted P2 for VT3: coin + 2P Start at frame X, lever/shots
  pattern (as `VT3_EXTRA_KEYS`).
- Test headless: flow log shows the versus (game type 1), a match to the
  end. Gun games: P2 joins and fires (existing `LINDBERGH_P2_TEST`-style
  script).

**Stage 1 - the network input layer, Mac host + second Mac process as P2.** ~3-5 days.
- `net_session.c`: UDP, hello/version, input packets with redundancy, RTT
  stats, a `[net]` log line every second. `net_input.c`: the client's local
  `CabinetInput` half sent; the host merges it as P2 in
  `host_cabinet_input()`.
- Client mode = "no game, just input + a status window".
- **Impairment built in:** `LINDBERGH_NET_SIM=loss%,delay_ms,jitter_ms,stall_ms@every_s`
  on send and receive, with its own RNG (as TC2's `TC2_NET_SIM`).
- **Bot client:** `LINDBERGH_NET_SCRIPT` replays scripted P2 inputs from
  stage 0 over the network.
- Tests: host + bot client on one Mac (two processes, separate data
  folders), versus to the end; at 5% loss / 150 ms stalls the host's log
  shows P2 input gaps but no crash. Useful alone: a keyboard on a second
  laptop as P2.

**Stage 2 - Quest joins as P2, flat video (H1).** ~5-8 days.
- Mac: VideoToolbox HEVC low-latency encode of the presented frame (the
  frame is already read back for screenshots?).
- Quest client mode in the APK: no game, OpenXR, MediaCodec decode to a
  surface texture on a big quad; controllers -> P2's `CabinetInput` (VT3
  lever map; gun games: aim = ray hit on the quad -> 640x480 coordinates,
  as the desktop mouse).
- Tests: Mac host with the Quest unworn running a scripted P2 (owner's
  rule: minimal headset runs). Log RTT, decode latency, dropped frames.
  Owner: one worn smoke run to judge the delay. That is the key human
  judgement of the whole plan.

**Stage 2b - measure G (half a day, can run any time after stage 0).**
- `LINDBERGH_GLQ_DUMP=<file>@<frame>`: write N frames of queue records to a
  file. Report bytes/frame, calls, upload bytes, zstd size, diff+zstd
  size, for VT3 (a rally, a replay), HOTD4SP (the street), GSE.
- Decision: G goes ahead if a busy frame compresses to under ~0.15 MB
  (~70 Mbit/s) and loads stay under ~100 MB.

**Stage 3 - GL stream client (G).** ~2-4 weeks, uncertain.
- Mac-to-Mac first: the client process replays the stream into its own
  window (desktop GL), compared by screenshot with the host
  (`LINDBERGH_GAME_SHOT`-style). Then Mac host -> Quest client replaying
  through gl4es/stereo.c, own head pose, P2 aim from its own depth.
- Tests: pixel-diff of host vs client frame N on Mac-Mac; stream bitrate
  log; Quest unworn run with the scripted P2 aim.

**Stage 4 - lockstep (L), Quest-Quest VT3 versus (and Mac-Quest as the hard test).**
- The 11-12 note's stages 2-6 on top of the stage-1 layer:
  - input record/replay and state hashes on one Mac;
  - the determinism fixes (seeds, MT split, virtual time, bundled `rand`,
    flow lock);
  - then the cross-platform set (bundled libm, `-ffp-contract=off`,
    separate runtime heap) for Mac-Quest;
  - the 2P-end camera.
- ~2-3 weeks for VT3. Each gun game afterwards: a few days to find its
  seeds/threads [M].

**Only the owner can judge:**
- whether H's ~40-70 ms is acceptable for tennis versus (P2 only) vs co-op
  guns;
- whether a flat screen in VR is good enough as P2;
- whether G's true VR is worth weeks;
- L's 2-3 frame delay worn.

### Open questions (prototype)

- JVS poll count and thread per frame in each gun game (`LINDBERGH_JVS=1`
  + thread id).
- GL queue size per frame and compressibility (stage 2b).
- Is the Mac's presented frame cheaply available for the encoder (IOSurface
  / PBO readback cost)?
- Quest MediaCodec decode latency for 1080p60 HEVC low-latency.
- Home Wi-Fi Mac<->Quest RTT and spikes (TC2: 16-35 ms ping Quest<->PC).
- Gun games' RNG/time/thread use, if lockstep is ever wanted for them
  (under H/G not needed).

## Sources

- DR-89, Time Crisis II VR: https://github.com/DR-89/time-crisis-2-vr
  (README; releases https://github.com/DR-89/time-crisis-2-vr/releases;
  `docs/ONLINE.md`, read via the GitHub API) [V]
- spacestate1, namco22-decompile: https://github.com/spacestate1/namco22-decompile
  and `docs/NETPLAY.md` [V]
- J. F. Mackenzie, "The Three-Screen Ridge Racer Quest" (C139 in MAME):
  https://jamesfmackenzie.com/2026/08/14/the-three-screen-ridge-racer-quest/ [V]
- Hackaday, three-monitor Ridge Racer in MAME:
  https://hackaday.com/2026/04/18/three-monitor-ridge-racer-machine-emulated-in-mame/ (search summary only)
- Arcade Controls forum, MAME link WIP (TC2 two-instance report):
  https://forum.arcadecontrols.com/index.php/topic,165638.105/wap2.html (403 on fetch; search excerpt only)
- Flycast GGPO: https://wiki.gbl.gg/w/Help:Flycast_GGPO (search summary)
- Batocera Lindbergh wiki: https://www.wiki.batocera.org/systems:lindbergh;
  TeknoParrot OutRun 2 SP SDX: https://teknoparrot.com/wiki/compatibility/or2spdlx.htm (search summaries)
- Anchor (SoH co-op): https://github.com/garrettjoecox/anchor (via a mirror's text in search)
- Co-Optimus TC2 PS2 listing: https://co-optimus.com/game/2088/playstation-2/time-crisis-2.html
- Owner's post (not fetchable): https://www.reddit.com/r/Emulationonquest/comments/1xqs5du/time_crisis_2_online_local_voice_chat_soon/
