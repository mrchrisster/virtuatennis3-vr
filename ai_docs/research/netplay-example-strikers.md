# Netplay example: "Quest 3 Strikers" (Super Mario Strikers on Quest 3)

Read-only web + source study, 2026-11-15. Nothing built or run, no adb. Source read from a
shallow clone in a scratch folder (not in this repo). Builds on `local-multiplayer-netplay.md`
(read that first) and its Time Crisis 2 study. **[V]** read in the source or a cited page today,
**[I]** inferred.

## Which project this is

| Rank | Candidate | Evidence | Verdict |
|---|---|---|---|
| 1 | **LanceSweatpants/Strikers-Quest-MR**, released as **"Quest 3 Strikers"** (Super Mario Strikers, GameCube) | Release titles are literally "Quest 3 Strikers - alpha 1.x" ([releases](https://github.com/LanceSweatpants/Strikers-Quest-MR/releases/tag/v0.1.14-alpha1)); the description says "online 1v1 with room codes"; listed on [questports.com](https://questports.com/ports/strikers-quest-mr); created 2026-10-12, last push 2026-11-13 [V] | **Almost certainly the one meant** (about 90%). Exact name, Quest 3, multiplayer, same decomp-port community as TC2 |
| 2 | LanceSweatpants/Quest-3-Strikers-CHARGED (Mario Strikers Charged, Wii decomp) | Same author; its README says online is still to come: "Nintendo's servers are gone", with room codes and voice planned [V] | No netcode yet, so no help for us |
| - | Cesarus85/Strikers-Quest-MR | A fork of #1 [V] | Same code |
| - | Virtua Striker, Strikers 1945, Omega Strikers | Nothing found for Quest | Not it |

I could not read Reddit itself. A search turned up no r/Emulationonquest thread for "Quest 3
Strikers", and questports.com links only to GitHub. So the identification comes from the
project's own name, not from a post the owner saw [I]. It is not by DR-89. The author is
"LanceSweatpants" (the commits say "Lance").

## 1. What it is

- **Base:** a **native port built from the community decompilation** of Super Mario Strikers,
  not an emulator. It is a fork of `luisxl15/Strikers-Android-Port` (arm64 Android), and uses
  **Aurora**, the GX/Dolphin-SDK layer from the decomp scene, for graphics. On top of that is an
  OpenXR layer: `src/platform/xr_quest.cpp` (about 23k lines) [V]. This is the same kind of
  project as ours: the original game code, compiled natively and run on a fake platform layer.
- **Platform:** Quest 3 (Quest 2 partly supported). The player brings their own disc image.
- **Licence:** GPL-3.0 for the repository. Source is public:
  [github.com/LanceSweatpants/Strikers-Quest-MR](https://github.com/LanceSweatpants/Strikers-Quest-MR).
- **Network code:** `smstrikers-port/src/platform/xr_net.cpp` (2429 lines),
  `include/port/xr_net.h`, `src/platform/xr_net.hpp`, `include/port/determinism.h`,
  `src/platform/vi.c` (fixed step), `src/platform/xr_voice.cpp`, the Java side
  (`android/.../NetWs.java`, `LobbyActivity.java`), and `server/src/index.js` (the relay) [V].

## 2. Multiplayer architecture: delay-based input lockstep (the same model as our plan)

- **Model:** "Delay-based lockstep: both run the same game and swap only their pad states, one per
  game frame" (`xr_net.h`). There is no rollback and no state transfer during a match. The match
  setup (teams, stadium, options, seed, delay) is sent once at the start [V].
- **Who hosts:** the lower 64-bit random id hosts. In co-op, the headset that made the room hosts
  instead. The host is the home side, pad 0; the guest is pad 1. Each headset feeds its own
  player's pad as its local pad (`local_pad()`). This is the same rule as our "player 1 = pad 0" [V].
- **Transport:** **one outbound TLS WebSocket per headset to a Cloudflare Worker relay**
  (`wss://<worker>/room/<CODE>`). There is **no UDP, no P2P and no LAN path**. Before that,
  r33-r38 used public MQTT brokers, which dropped messages and froze "the first online night".
  The relay sends every message to everyone in the room, **the sender included**. The headset
  ignores its own messages coming back, but uses them as a liveness check: if none of its own
  messages comes back for 5 s, it drops the link and reconnects (backoff 1-10 s) [V].
- **Threads:** a network thread owns the socket and the JNI calls. The game thread queues
  outgoing messages and drains incoming ones once per headset frame (`poll()`), so a game frame
  never blocks on the network [V].
- **Message layout:** a little-endian header `[type u8][protocol u8][sender id u64]`, then the
  body. Types: Hello=1, Start=2, Input=3, Hash=4, Ping=5, Pong=6, Coop=7. The relay caps
  messages at 4096 bytes [V].
  - `NetPad` is 8 bytes: `u16 buttons; s8 stickX, stickY, substickX, substickY; u8 trigL, trigR`
    (the GameCube `PADStatus` without its error and analog fields).
  - Input: `[first frame u32][count u8][count x NetPad]` then the voice trailer. **Redundancy,
    not acks**: each Input message carries every frame from `frame - delay - 1` up to the newest,
    at most 255 frames. A comment on r39 records that one frame short of that window, a single
    lost message "stalled both headsets for good" [V].
  - Inputs go out every 2 frames (30 messages a second). While stalled, the latest window is resent
    every 100 ms, because one lost message would otherwise stall both sides [V].
- **Input delay:** fixed for the whole match. The host sets it from the **median of the last 9
  RTT samples**: `delay = clamp((rtt/2 + 16)/17 + 2, 3, 20)` frames, sent in Start
  (`host_start`). The guest takes the host's value. The **first `delay` frames use neutral pads on
  both sides**. The README says this is "usually about a tenth of a second". Ping and pong are
  answered and timed **on the network thread**. Timing them on the game thread had inflated a
  same-house RTT to about 220 ms and given a 9-frame delay (commit 4035b98, "honest input delay")
  [V]. There is no adaptation during the match.
- **Tick:** online, the game runs exactly one 60 Hz frame per step:
  - `nlTask.cpp` forces `clampedDeltaTime = 1/60`.
  - `vi.c` `PortNetSetFixedStep(1)` swaps the host clock for a virtual ticker: retrace count ×
    675000 bus ticks.
  - Offline, the game can run at the display rate. Online it is held at 60 game frames a second,
    and the slower headset sets the pace for both (README, Known issues) [V].
  - A frame is "due" from the headset's own accumulator. If the remote input has not arrived, the
    frame stays due and the headset keeps rendering VR while it waits (`xr_quest.cpp` ~19517) [V].
- **Commit after the frame really runs (pitfall r39b):** `step()` hands out a frame's pads, but
  `PortNetCommitFrame()` counts it as used only once `aurora_begin_frame` has accepted the frame.
  If the renderer refuses a frame, the same inputs and seed are given out again. Before this fix,
  one refused frame left a headset "one frame off for the rest of the match" [V].
- **Determinism:**
  - **The same binary only.** A `kProtocol` byte is in every message header, plus an "edition"
    byte (Classic/Plus). The protocol number goes up on any change to game logic or RNG.
  - Floats are ordinary hardware floats (both sides are arm64 Quest); there is no fixed-point
    and no soft-float.
  - **The RNG is reseeded every frame:** `nlSetRandomSeed(frame_seed(seed, frame))`, an
    integer hash of the match seed and the frame number. One extra draw on one headset therefore
    cannot carry into the next frame [V].
  - **Presentation code moved to its own RNG stream:** the crowd chants, character audio, audio
    streams, FE audio and spark effects drew from the gameplay RNG depending on local playback
    state, which **desynced matches after goals**. They now use `nlAudioSeed` (Alpha 1.11, protocol
    5 to 6) [V].
  - **View-dependent game logic removed online:** `SidelineExplodable::Explode` checked the game
    camera's frustum, which the VR views skip. Online it no longer checks it [V]. This is directly
    relevant to our VR cameras.
  - Per-player cosmetic choices (goal effects, ball skins, weather) are swapped in the hello and
    the start message. Gameplay-relevant guest stats travel as raw float bits, so both headsets
    simulate the same numbers [V].
- **Desync detection, no recovery:**
  - At the end of each frame the game hashes ball position, both scores and all 10 player
    positions (FNV-1a, `Game.cpp` ~920).
  - Every 30 frames the hash goes out in a Hash message and is compared with the other side's;
    mismatches are counted and logged.
  - Every 300 frames it is written to the log "so two runs compare line by line".
  - There is no resync. A desync only shows up in the log line at the end of the match:
    "N/M state checks differed, K stalls" [V].
- **Watchdogs:**
  - If the friend's input is 10 s old, or no frame has run for 10 s, the match ends.
  - Around the match load the limit is 30 s, because the whole match loads in one blocking frame
    (online frame 1).
  - The match ends cleanly when both headsets have been in the front end for 30 frames [V].

## 3. Session layer

- **Room codes:** the host gets a fresh 4-letter code; a player can also type their own code (3-8
  A-Z/0-9). Each code is its own Durable Object. A room holds at most 4 sockets, and the oldest is
  evicted, so a reconnect can replace its own dead socket. A third headset is ignored while two
  are playing. The relay stores nothing and has no authentication (`server/README.md`) [V].
- **Hello every 0.5 s:** a ready bit, the edition, the choice (team, sidekick, stadium, options,
  mode), plus optional tagged tails ('H' id and name, 'L' slots, 'G', 'B', 'W'). Tails are how
  later builds add fields without breaking older parsers [V].
- **Start:**
  1. When both are ready (each hello under 2 s old) and both picked the same kind of match, the
     host sends Start: both ids, the seed, the delay, the edition, both choices and the tails.
  2. The host repeats it every 300 ms until the guest's first input arrives [V].
- **Waiting:** the match start waits for the friend at the loading screen "however long they
  take", with a card in the headset showing the code. The player holds B for 2 s to play the
  computer instead. Before Alpha 1.8 the game fell back to offline at once, and users complained
  [V].
- **Version mismatch:** the player sees why. `online-note.txt` gets `edition=...` or
  `protocol=N`, and the launcher panel puts it into words [V].
- **Quick match:** a Matchmaker Durable Object at `/quick/<KEY>`, where KEY is edition +
  protocol, so builds that cannot play each other never meet. It pairs the two that have waited
  longest and sends both `match Q?????`; both then join that room code [V].
- Also built on the same relay: **tournaments** (4 or 8 players, brackets, result
  reconciliation), **online leagues** (2-8 players), and co-op careers sent in 3500-byte pieces
  with receipts [V].
- **Voice:** Opus at 48 kHz in 20 ms frames, with a level gate (about -38 dBFS, 300 ms hang).
  Frames ride as a **trailer on the Input messages**. The receiver gathers 60 ms before playing,
  keeps at most 240 ms queued and drops older frames. Audio runs through AAudio on its own thread
  [V]. This is the same idea as TC2's.
- **Not present:** LAN discovery, direct P2P, NAT traversal (the relay sidesteps it), spectators,
  and reconnect in the middle of a match (a drop of about 10 s ends it).

## 4. VR specifics

- Each headset picks its own view (big screen in the room, tabletop hologram, life-size stadium)
  regardless of the other player's choice ("one can play on the table while the other plays on the
  big screen") [V].
- I found **no remote avatar, head or hands** of the other player in the code; the only
  "friend" effects are cosmetic (their goal explosion, ball skin, team name) [V, from grep].
- Comfort: in the stadium, the scorer is kept at least 2.5 m away; eye height is adjustable.
  Online, the game is held at 60 game frames a second while the display runs faster [V].

## 5. Test tooling

- `server/test-room.mjs`, `test-quick.mjs`, `test-tourney.mjs`, `test-league.mjs`: Node scripts
  that open fake WebSocket clients against `wrangler dev` or the live relay. They check the echo,
  fan-out, RTT, pairing and bracket rules. A `TEST_FAST` variable shortens the timers locally [V].
- **`tools/fakefriend`:** a test friend that joins a room. Start can carry a `cpuPlays` byte
  so **the headset's own AI plays the fake friend's side**: one headset can test a whole online
  match. It is referenced in `xr_net.h` and the Alpha 1.4 notes, but **it is not in the public
  repo** [V].
- `STRIKERS_SEED` + `STRIKERS_FIXED_DT`: repeatable headless runs. With the hash logged every 300
  frames, two logs can be diffed [V].
- No network simulator (loss or jitter injection) was found. Testing was "online matches
  between two Quest 3 headsets" (README) [V].

## 6. What we can reuse or imitate

Nearly all of it maps onto our JVS-level lockstep:

1. **Packet layout:** `[type][proto][sender u64]`, an 8-byte pad for each frame, an Input message
   of `[first u32][count u8][pads]` with a window back to `frame - delay - 1`, sent every 2 frames
   plus a 100 ms keepalive resend while stalled. Our JVS state (switch bytes plus a few analog
   channels) fits in about 8 bytes the same way.
2. **Delay rule:** the host takes the median of 9 RTT pings, timed on the net thread,
   `clamp((rtt/2+16)/17 + 2, 3, 20)`. The first `delay` frames are neutral. It is fixed for the
   match. That is enough to begin with; adapting the delay can come later.
3. **Per-frame RNG reseed** from `hash(seed, frame)` at the top of each game frame. This works for
   any recomp: find the game's `rand`/LCG state and overwrite it every frame. It is the cheapest
   insurance against small draw-count differences.
4. **A separate RNG stream for presentation:** any audio, particle or camera code that draws
   from the game RNG depending on local state gets its own stream. In VT3, check the crowd and
   announcer audio and the replay cameras.
5. **No game logic that depends on the camera or culling.** Our VR camera differs from the game
   camera, just like theirs. Audit any frustum or visibility test that feeds gameplay or RNG.
6. **Fixed game dt online** plus a virtual clock built from the frame counter, not the host clock.
   Any code that reads time (our `gettimeofday`/`clock_gettime` shims) must see the virtual clock
   while online.
7. **Count a frame as consumed only after it really ran** (the `PortNetCommitFrame` pattern). Our
   render thread or GL queue may refuse or skip a frame too.
8. **Hash a few key gameplay values every 30 frames, log them every 300.** In VT3: ball position
   and velocity, player positions, score and game state. Compare them over the wire and in logs.
9. **Session flow:** hellos every 0.5 s with a ready bit and the choices; lower id hosts; the host
   repeats Start until the first remote input arrives; the start waits for the friend
   indefinitely, with a way to cancel; mismatches are explained to the player; protocol and
   edition go in every header.
10. **Relay:** a Cloudflare Worker with a Durable Object per room is about 50 lines (the `Room`
    class), free, and needs no NAT work. Echo-to-sender gives a free liveness check. It is a
    cheap option alongside a TC2-style relay.
11. **A test AI as a fake friend** (`cpuPlays`) lets one headset run a whole online match. For
    VT3 this could be the game's own CPU player on the remote pad, plus a Mac build as the second
    peer.

**Pitfalls the author hit**, all from the code comments and commit notes:
- MQTT brokers lost messages.
- A redundancy window one frame short stalled both sides.
- RTT measured on the game thread inflated the delay.
- Audio drew from the game RNG, which desynced after goals.
- Frustum-dependent gameplay.
- A renderer-refused frame left a headset one frame off.
- One long load frame tripped the watchdog.
- The wrong socket was evicted on reconnect (`getWebSockets()` is not oldest-first).
- Falling back to offline when no friend was there yet frustrated users.
- Every logic change needed a protocol bump.

## What this changes in our plan

- **It confirms the lockstep route for Quest-to-Quest.** A decomp-native GameCube game, very
  close to our setup, runs delay-based input lockstep on stock hardware floats between two
  Quest 3s with no rollback. Treat Mac-to-Quest float differences as a separate risk.
- **Add these to the lockstep stage:**
  - reseed the game RNG every frame;
  - give presentation code its own RNG stream;
  - audit gameplay code that reads the camera or culling;
  - put the virtual clock behind every time read;
  - consume a frame only once it has run.
- **Copy the delay formula and the redundancy window as they are** for the first version. The
  fixed-delay-per-match design they settled on is enough to ship; adapting the delay is optional.
- **Transport can be simpler than TC2's:** a WebSocket to a Cloudflare relay worked for them,
  with room codes and quick match on the same worker. Keep a LAN/UDP path optional (they have
  none).
- **Desync handling can stay detection-only at first** (hash every 30 frames, log every 300),
  as theirs does. Resync is not needed to ship.
- **Plan a "fake friend" test early:** a CPU-controlled remote pad lets one headset smoke-test
  online.
