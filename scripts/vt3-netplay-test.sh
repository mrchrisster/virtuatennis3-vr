#!/usr/bin/env bash
# vt3-netplay-test.sh - two headless copies of Virtua Tennis 3 on this Mac play
# a versus match against each other over the netplay layer (localhost UDP),
# a bot on each side, under the built-in network simulator.
#
#   ./scripts/vt3-netplay-test.sh /path/to/disk0 [scenario ...]
#
# Scenarios (default: all):
#   clean       no impairment
#   j20         20 ms each way, 5 ms jitter
#   d60         60 ms each way
#   loss2       2% of packets lost
#   loss10      10% lost
#   reorder     20% reordered (3 ms, 1 ms jitter)
#   stall       one 400 ms stall from the host (as Wi-Fi power save), 25 s in
#   kill        the joiner is killed 70 s in: the host must play on alone
#   mismatch    the joiner has Replays off: the host must refuse it, by name
#
# The host is player 1 (its menu taps start a match; LINDBERGH_BOT plays 1P),
# the joiner player 2 (a coin in chute 2 and Start during 1P's match - "here
# comes a new challenger" - then LINDBERGH_BOT plays 2P). Per scenario:
# completed (both still in lockstep at the end and a 1P-vs-2P match played),
# the input delay used, stalls, desync (none expected), and whether the two
# copies' match hashes ([shash], every 60 frames) are the same.
#
# SECS=<n> (default 110) per scenario; OUT=<dir> (default /tmp/vt3-netplay);
# PAR=<n> scenarios at once (default 2). Each copy gets its own NVRAM copy
# (LINDBERGH_NVRAM, from the game folder's lindbergh_nvram.bin) and runs
# headless (vt3-repro.sh). Never touches the headset.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="${1:-}"; shift || true
[ -n "$GAME" ] || { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
SCEN="${*:-clean j20 d60 loss2 loss10 reorder stall kill mismatch}"
OUT="${OUT:-/tmp/vt3-netplay}"; SECS="${SECS:-110}"; PAR="${PAR:-2}"
mkdir -p "$OUT"
NV="$GAME/vt3_Lindbergh/lindbergh_nvram.bin"; [ -f "$NV" ] || NV="$GAME/disk0/vt3_Lindbergh/lindbergh_nvram.bin"

one() {     # one() <name> <port>
    local s=$1 port=$2 d="$OUT/$1" sim="" stall="" hostx="" joinx="" kill_at=0
    case $s in
        clean)    ;;
        j20)      sim="20,5,0,0" ;;
        d60)      sim="60,0,0,0" ;;
        loss2)    sim="1,0,2,0" ;;
        loss10)   sim="1,0,10,0" ;;
        reorder)  sim="3,1,0,20" ;;
        stall)    stall="25000,400"; sim="1,0,0,0" ;;
        kill)     kill_at=70 ;;
        mismatch) joinx="LINDBERGH_REPLAYS=0" ;;
    esac
    rm -rf "$d"; mkdir -p "$d/host" "$d/join"
    if [ -f "$NV" ]; then cp "$NV" "$d/host/nvram.bin"; cp "$NV" "$d/join/nvram.bin"; fi
    common=(LINDBERGH_STATE_HASH=60 LINDBERGH_VT3_FLOWLOG=1 LINDBERGH_SHOT_EVERY=100000 LINDBERGH_NETPLAY_TIMEOUT=5000 LINDBERGH_NETPLAY_WAIT=60)
    [ -n "$sim" ] && common+=(LINDBERGH_NETSIM="$sim")
    env "${common[@]}" ${stall:+LINDBERGH_NETSIM_STALL=$stall} LINDBERGH_NVRAM="$d/host/nvram.bin" OUT="$d/host" \
        LINDBERGH_NETPLAY="host:$port" LINDBERGH_KEYS2= LINDBERGH_BOT=2900,1 \
        "$ROOT/scripts/vt3-repro.sh" versus mac "$GAME" "$SECS" >"$d/host.out" 2>&1 &
    local hp=$!
    env "${common[@]}" ${joinx:+$joinx} LINDBERGH_NVRAM="$d/join/nvram.bin" OUT="$d/join" \
        LINDBERGH_NETPLAY="join:127.0.0.1:$port" LINDBERGH_AUTOSTART=0 VT3_KEYS= LINDBERGH_BOT=2900,2 \
        "$ROOT/scripts/vt3-repro.sh" versus mac "$GAME" "$SECS" >"$d/join.out" 2>&1 &
    local jp=$!
    if [ "$kill_at" -gt 0 ]; then
        sleep "$kill_at"
        # the joiner's game process (the repro script's child), killed outright
        pkill -9 -P "$jp" 2>/dev/null; for c in $(pgrep -P "$jp"); do pkill -9 -P "$c" 2>/dev/null; kill -9 "$c" 2>/dev/null; done
        echo "killed the joiner at ${kill_at}s" >"$d/killed"
    fi
    wait $hp $jp 2>/dev/null
}

report() {  # report <name>
    local s=$1 d="$OUT/$1" H="$OUT/$1/host/vt3.log" J="$OUT/$1/join/vt3.log"
    local started delay stalls desync same vs ended completed
    started=$(grep -c "player 2 joined\|joined as player 2" "$H" "$J" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
    delay=$(grep -ho "input delay [0-9]* -> [0-9]*\|input delay [0-9]*$\|lockstep from frame 1, input delay [0-9]*" "$H" | tail -1 | grep -o "[0-9]*$")
    [ -n "$delay" ] || delay=$(grep -o "delay [0-9]*," "$H" | tail -1 | grep -o "[0-9]*")
    stalls=$(grep "^\[net\] frame" "$H" | grep "stalls" | tail -1 | sed -E 's/.*stalls ([0-9]+) \(([0-9]+) frames, ([0-9]+) ms, longest ([0-9]+) ms\).*/\1 waits, \3 ms, longest \4 ms/')
    desync=$(grep -ho "DESYNC: the two games differ at frame [0-9]*" "$H" "$J" | head -1 | grep -o "[0-9]*$")
    ended=$(grep -h "session ended\|playing on alone\|refused" "$H" "$J" | head -2 | sed 's/^\[net\] //' | tr '\n' '|')
    vs=$(grep -c "GameLoop" "$H")
    if python3 "$ROOT/lindberghrecomp/tools/state_hash_diff.py" --semantic "$H" "$J" >"$d/shash.txt" 2>&1; then same="same"; else same="$(head -1 "$d/shash.txt")"; fi
    completed=no
    case $s in
        kill)     grep -q "nothing from the other player\|the other player left" "$H" && [ "$(grep -c GameLoop "$H")" -gt 3 ] && completed="yes (host played on alone)" ;;
        mismatch) grep -q "refused" "$J" && grep -q "refused a player" "$H" && completed="yes (refused: $(grep -o 'vt3.replays=[^;]*;' "$H" | head -1)...)" ;;
        *)        [ "$started" -ge 2 ] && [ -z "$desync" ] && ! grep -q "session ended" "$H" "$J" && [ "$vs" -gt 3 ] && completed=yes ;;
    esac
    printf '%-9s | %-26s | %-5s | %-36s | %-7s | %s\n' "$s" "$completed" "${delay:--}" "${stalls:--}" "${desync:-none}" "$same"
    [ -n "$ended" ] && printf '          %s\n' "$ended"
}

i=0; port=47200
for s in $SCEN; do
    one "$s" $((port + i)) &
    i=$((i + 1))
    [ $((i % PAR)) -eq 0 ] && wait
done
wait
printf '%-9s | %-26s | %-5s | %-36s | %-7s | %s\n' scenario completed delay stalls desync "match hashes host/joiner"
for s in $SCEN; do report "$s"; done
