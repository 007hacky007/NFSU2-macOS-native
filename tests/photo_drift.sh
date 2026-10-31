#!/bin/bash
# tests/photo_drift.sh <engine> <SPEED2.EXE> [<career saves>] -- photo mode and drift mode in the game
# (runtime/photo.c, drift.c, native_scene.m), European or North American, driven by AUTOSEQ (keys) and
# NFSU2_PHOTO_SCRIPT (photo mode as the keys and the mouse drive it), checked in the log:
#   photo: a Quick Race; F12 opens photo mode (the world freeze set, the developers' free camera, the
#   race clock standing), the camera turned, closer, free and flown, a screenshot, field of view and
#   tilt, closed (the drive camera back, the clock running); the pause menu has Photo Mode after Replay,
#   drawn with the still camera icon, and opens it; F12 in the pause menu saves a screenshot.
#   drift (with <career saves>: a NFSU2_SAVEDIR folder with one profile whose career has a car, which
#   loads at the start): Resume Career, back to free roam, X, a drive with two slides, X.  Whether a
#   drift is banked depends on the drive, so it is reported, not required.
# Pictures (DUMPFRAME) and the screenshots stay in the run folder printed at the end.
#   e.g. tests/photo_drift.sh out/nfsu2_boot ~/NFSU2/SPEED2.EXE ~/saves-with-a-career
set -u
BIN="$1"; EXE="$2"; SEED="${3:-}"
T="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_photo_drift.XXXXXX")"
fails=0
run(){   # run <name> <seed or -> [VAR=val ...]
    local R="$T/$1" S="$2"; shift 2
    mkdir -p "$R/home" "$R/saves" "$R/as" "$R/dump"
    [ "$S" != - ] && cp -R "$S"/. "$R/saves"/
    env -i HOME="$R/home" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
      FIXMAT=1 FIXMAT_MODE=3 SNDSYNC=1 GPUVS=1 WINDOW=1 ALARM=0 NOFOCUS=2 NOSOUND=1 NFSFULL=0 NOMOVIES=1 \
      MOUSEAT=5,5 NFSRES=1920x1080 NFSU2_SAVEDIR="$R/saves" NFSU2_APPSUPPORT="$R/as" DUMPDIR="$R/dump" "$@" \
      "$BIN" "$EXE" > "$R/log.txt" 2>&1
}
check(){   # check <log> <extended regexp> <what>
    if grep -a -q -E "$2" "$1"; then echo "PASS  $3"; else echo "FAIL  $3"; fails=$((fails+1)); fi
}
clock(){ grep -a "state $2:" "$1" | sed -E 's/.*clock ([0-9]+).*/\1/'; }

# --- photo mode in a Quick Race ---
PS="4400:state before;4400:f12;4440:state on;4440:drag 0.3 0.05;4440:dolly 3;4500:state still;4505:free"
PS="$PS;4505:move 0 1;4535:move 0 0;4545:capture;4560:fov 40;4560:roll 15;4620:off;4650:state off;4710:state later"
PS="$PS;5130:state pausemenu;5200:state frompause;5260:off;5340:f12"
run photo - NFSU2_PHOTO=1 NFSU2_TEXPACKS_LOG=1 QUITFRAMES=6400 DUMPFRAME=4380,4500,4540,4600,5100,5200 \
    "AUTOSEQ=1000:0x1C,1350:0x1C,1750:0x1C,1950:0x1C,2150:0x1C,2350:0x1C,2550:0x1C,2750:0x1C,2950:0x1C,4760:0x01,4900:0xCD,4940:0xCD,4980:0xCD,5020:0xCD,5140:0x1C,5320:0x01" \
    "NFSU2_PHOTO_SCRIPT=$PS"
P="$T/photo/log.txt"
check "$P" "texpacks\] t[0-9]+ 128x64 -> pack [0-9]+ INGAME_ICON_VOIP_ON" "the pause menu's icon: INGAME_ICON_VOIP_ON drawn as the still camera"
check "$P" "state before: freeze 0 camera 1" "before: no freeze, the drive camera"
check "$P" "\[photo\] f=4400 on: the world stands" "F12 opens photo mode"
check "$P" "state on: freeze 1 camera 2" "on: the world freeze, the free camera mover"
c1="$(clock "$P" on)"; c2="$(clock "$P" still)"; c3="$(clock "$P" off)"; c4="$(clock "$P" later)"
if [ -n "$c1" ] && [ "$c1" = "$c2" ]; then echo "PASS  the race clock stands ($c1)"; else echo "FAIL  the race clock moved ($c1 -> $c2)"; fails=$((fails+1)); fi
check "$P" "the free camera" "the free camera"
check "$P" "\[photo\] f=4620 off \(closed\)" "closed"
check "$P" "state off: freeze 0 camera 1" "off: the freeze cleared, the drive camera back"
if [ -n "$c3" ] && [ -n "$c4" ] && [ "$c4" -gt "$c3" ]; then echo "PASS  the race clock runs again ($c3 -> $c4)"; else echo "FAIL  the race clock ($c3 -> $c4)"; fails=$((fails+1)); fi
check "$P" "the pause menu's Replay, Photo Mode after it" "Photo Mode in the pause menu"
check "$P" "the pause menu's Photo Mode$" "the pause menu's Photo Mode chosen"
check "$P" "state frompause: freeze 1 camera 2" "photo mode from the pause menu"
n=$(grep -a -c "\[photo\] screenshot saved" "$P")
if [ "$n" -ge 2 ]; then echo "PASS  $n screenshots saved (photo mode, the pause menu)"; else echo "FAIL  $n screenshots saved"; fails=$((fails+1)); fi
check "$P" "\[scene\] the photo panel shown" "the photo panel shown"
if grep -a -q "FAULT" "$P"; then echo "FAIL  a fault (photo)"; fails=$((fails+1)); else echo "PASS  no fault (photo)"; fi

# --- drift mode in free roam ---
if [ -n "$SEED" ]; then
    run drift "$SEED" NFSU2_DRIFT=1 NFSU2_PHOTO=1 QUITFRAMES=6300 DUMPFRAME=2800,3350,5300,5400 \
        "AUTOSEQ=1000:0x1C,1300:0x1C,1500:0xCB,1600:0x1C,1900:0x1C,2200:0x1C,2350:0xCB,2450:0x1C,1450:0x2D,3300:0x2D,3320:0xD0:280,3320:0xCB:280,3620:0xC8:2400,3900:0xCB:80,3900:0x39:25,4300:0xCD:80,4300:0x39:25,4700:0xCB:80,4700:0x39:25,5300:0xCB:30,5300:0x39:12,5340:0xCD:40,6100:0x2D" \
        "NFSU2_PHOTO_SCRIPT=5700:f12;5760:off"
    D="$T/drift/log.txt"
    check "$D" "\[drift\] f=[0-9]+ X outside free roam: nothing" "X outside free roam does nothing"
    check "$D" "\[drift\] f=33[0-9][0-9] drift handling on" "X in free roam: the drift handling on"
    check "$D" "the drift event's styles: [0-9]+ added" "the drift event's styles added to free roam's"
    check "$D" "\[scene\] the drift panel shown" "the drift panel shown"
    check "$D" "\[scene\] the drift panel hidden \(photo mode\)" "the drift panel hidden in photo mode"
    check "$D" "\[drift\] f=61[0-9][0-9] drift handling off" "X again: the drift handling off"
    if grep -a -q "FAULT" "$D"; then echo "FAIL  a fault (drift)"; fails=$((fails+1)); else echo "PASS  no fault (drift)"; fi
    if grep -a -q "a drift of" "$D"; then echo "INFO  $(grep -a -m1 'scene\] the drift panel:' "$D" | sed 's/.*\] //')"
    else echo "INFO  no drift banked on this drive"; fi
else
    echo "SKIP  drift mode: no career saves given"
fi
echo "run folder: $T"
[ $fails -eq 0 ] && echo "RESULT: all passed" || echo "RESULT: $fails failed"
exit $fails
