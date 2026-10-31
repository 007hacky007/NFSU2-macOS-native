#!/bin/bash
# tests/input/suite.sh <engine> <SPEED2.EXE> <work dir>
# The keyboard and game pad scenarios (tests/input/*.seq, runtime/inputseq.m)
# in silent game runs, each checked against its log.  The same scenarios run
# on the European and the North American SPEED2.EXE (their engines:
# out/nfsu2_boot, out/nfsu2_na_boot).  A physical controller is not needed:
# the pad is the synthetic one (runtime/gamepad.m), which drives the same
# DirectInput device; tests/gamepad_harness.sh covers GameController itself.
# Exit status 0 when every check passes.
BIN="$1"; EXE="$2"; WK="$3"
D="$(cd "$(dirname "$0")" && pwd)"
[ -x "$BIN" ] && [ -f "$EXE" ] && [ -n "$WK" ] || { echo "usage: $0 <engine> <SPEED2.EXE> <work dir>"; exit 2; }
mkdir -p "$WK"; FAILED=0
check(){   # name, log, extended regex (must match a line)
    if LC_ALL=C grep -a -q -E -e "$3" "$2"; then printf "  PASS  %s\n" "$1"
    else printf "  FAIL  %s  (%s)\n" "$1" "$3"; FAILED=1; fi
}
nocheck(){ # name, log, regex that must not match
    if LC_ALL=C grep -a -q -E -e "$3" "$2"; then printf "  FAIL  %s  (found: %s)\n" "$1" "$3"; FAILED=1
    else printf "  PASS  %s\n" "$1"; fi
}
run(){     # scenario, home, log, VAR=value...
    local s="$1" h="$2" l="$3"; shift 3
    echo "== $s ($(basename "$BIN"))"
    "$D/run.sh" "$BIN" "$EXE" "$D/$s.seq" "$h" "$l" "$@"
    check "run completed" "$l" "^  unsupported instructions"
    nocheck "every wait reached its screen" "$l" "TIMEOUT"
}
IN='\[seq\] frame [0-9]+: in: '

rm -rf "$WK/kb"; L="$WK/kb_rebind_save.log"
run kb_rebind_save "$WK/kb" "$L" NFSU2_KEYLAYOUT=com.apple.keylayout.German NFSU2_KEY_LOG=1 DIMAP=1 NFSU2_PAD_FAKE=LX=0 QUITFRAMES=12000
check "German layout: Shift + the Y key types Z (VK_Z, scan code of DIK_Y)" "$L" "-> WM_CHAR 0x5a lParam 0x00150001"
check "German layout: the Z key types y" "$L" "-> WM_CHAR 0x79 lParam 0x002c0001"
check "dead key: WM_DEADCHAR 0xB4 (acute)" "$L" "-> WM_DEADCHAR 0xb4"
check "dead key + E: WM_CHAR 0xE9 (e acute, code page 1252)" "$L" "-> WM_CHAR 0xe9"
check "Cmd+N goes to the app, not the game" "$L" "kc=0x2d with Command -> app, not the game"
check "Option = Alt: WM_SYSKEYDOWN" "$L" "-> WM_SYSKEYDOWN 0x44"
check "Option+key that types (Option+L = @): AltGr-like WM_CHAR" "$L" "-> WM_CHAR 0x40 lParam 0x00260001"
check "capture: c_dfDIKeyboard offsets (Escape = dwOfs 1)" "$L" "event down key 0x01 -> dwOfs 1 \(raw\)"
check "Steering (Left) = J saved as a user map" "$L" "user map DIMap\.\{F19DD539-CB04-4126-908B-CF28FEFC69BD\}\.53\.4 = 810004cb 00000003 00002404"
check "user maps in the registry file" "$WK/kb/.nfsu2_registry" "^s DIMap\..*00001704$"
check "race: J steers left" "$L" "${IN}steer \+1\.00"
check "race: L steers right" "$L" "${IN}steer -1\.00"
check "race: I is the throttle" "$L" "${IN}steer -0\.00 throttle 1\.00 brake 0\.00 e-brake 0\.00"
check "race: Down is the handbrake" "$L" "${IN}.*e-brake 1\.00"
check "race: S still brakes" "$L" "${IN}steer -0\.00 throttle 0\.00 brake 1\.00"
L="$WK/kb_rebind_load.log"
run kb_rebind_load "$WK/kb" "$L" NFSU2_KEYLAYOUT=com.apple.keylayout.German DIMAP=1 NFSU2_PAD_FAKE=LX=0 QUITFRAMES=9000
check "the user map comes back (9 bindings)" "$L" "53 actions, 9 from the saved user map"
check "race: J steers left" "$L" "${IN}steer \+1\.00"
check "race: I is the throttle" "$L" "${IN}steer -0\.00 throttle 1\.00"
check "race: Down is the handbrake" "$L" "${IN}.*e-brake 1\.00"
L="$WK/kb_rebind_reset.log"
run kb_rebind_reset "$WK/kb" "$L" DIMAP=1 QUITFRAMES=4500
check "no controller: no game pad device" "$L" "peek 0x0086ffb4: 00000000 00000000"
nocheck "no controller: no pad offered" "$L" "game pad offered"
nocheck "Reset Keys To Default: the user maps are gone" "$WK/kb/.nfsu2_registry" "^s DIMap\."

rm -rf "$WK/pad"; L="$WK/pad_bind_save.log"
run pad_bind_save "$WK/pad" "$L" NFSU2_PAD_FAKE=PLUG=1 NFSU2_PAD_LOG=1 QUITFRAMES=7000
check "our profile entry: the default pad layout" "$L" "\[pad\] default pad layout applied to input channel 0x00874fb0"
check "A, B, View post Enter / Escape in the menus" "$L" "front end: keystroke 0x1b"
check "Shift Up bound to Y ([3] = 7, A's taken off)" "$L" "peek 0x00874fc8: 00000000 00000009 00000008 00000007"
L="$WK/pad_bind_load.log"
run pad_bind_load "$WK/pad" "$L" NFSU2_PAD_FAKE=PLUG=1 NFSU2_PAD_LOG=1 QUITFRAMES=5500
check "after a restart Shift Up is still Y" "$L" "peek 0x00874fc8: 00000000 00000009 00000008 00000007"
check "Throttle on A in the first column: the trigger axis goes off" "$L" "\[pad\] throttle bound to a button: its axis is off"
check "keyboard Escape cancels a pad capture (B then leaves the page)" "$L" "UI_OptionsMain.fng is up"
check "nothing bound by the cancelled capture (A = throttle, B unchanged)" "$L" "peek 0x00874fc8: 00000001 00000009 00000008 00000007"

rm -rf "$WK/race"; L="$WK/pad_race.log"
run pad_race "$WK/race" "$L" NFSU2_PAD_FAKE=PLUG=1 NFSU2_PAD_LOG=1 QUITFRAMES=4500
check "left stick half left steers" "$L" "${IN}steer \+0\.4"
check "right trigger half: throttle 0.50" "$L" "${IN}steer -0\.00 throttle 0\.50"
check "right trigger full: throttle 1.00 and its button" "$L" "right trigger button \(11\) down"
check "left trigger half: brake 0.50" "$L" "${IN}steer -0\.00 throttle 0\.00 brake 0\.50"
check "RB: e-brake" "$L" "${IN}steer -0\.00 throttle 0\.00 brake 0\.00 e-brake 1\.00"
check "focus lost: the pad reads at rest" "$L" "\[pad\] app inactive: the pad reads at rest"
check "back in front: at rest until let go" "$L" "\[pad\] controller let go: the game reads it again"
check "a key held through a focus loss is released" "$L" "app resigned active: 1 held key\(s\) released"
rm -rf "$WK/race"; L="$WK/pad_race_options.log"
run pad_race "$WK/race" "$L" NFSU2_PAD_FAKE=PLUG=1 NFSU2_PAD_LOG=1 NFSU2_PAD_TRIGGER_CLICK=off NFSU2_PAD_FE_KEYS=0 NFSU2_PAD_BACKGROUND=1 QUITFRAMES=4500
nocheck "NFSU2_PAD_TRIGGER_CLICK=off: no trigger buttons" "$L" "trigger button"
nocheck "NFSU2_PAD_FE_KEYS=0: no menu keystrokes" "$L" "front end: keystroke"
check "NFSU2_PAD_BACKGROUND=1: the pad keeps reading" "$L" "the pad keeps reading"
nocheck "NFSU2_PAD_BACKGROUND=1: never at rest for the focus" "$L" "controller let go"

rm -rf "$WK/ctl"; L="$WK/pad_controls_unplug.log"
run pad_controls_unplug "$WK/ctl" "$L" NFSU2_PAD=hotplug NFSU2_PAD_FAKE=PLUG=1 NFSU2_PAD_LOG=1 QUITFRAMES=6000
check "View opens the quit prompt (posted Q)" "$L" "front end: keystroke 0x51"
check "lost once the Controls page is left (DIERR_INPUTLOST)" "$L" "\[pad\] unplugged: DIERR_INPUTLOST"
check "the rescan finds it again" "$L" "CreateDevice -> 0x[0-9a-f]+ \(Fake Pad\)"
if LC_ALL=C sed -n '/log:unplug on the Joypad page/,/log:left the Controls page/p' "$L" | grep -a -q "DIERR_INPUTLOST"
then printf "  FAIL  kept while the Controls page is open\n"; FAILED=1; else printf "  PASS  kept while the Controls page is open\n"; fi

for m in 1 hotplug; do
    rm -rf "$WK/unp"; L="$WK/pad_unplug_$m.log"
    run pad_unplug "$WK/unp" "$L" NFSU2_PAD=$m NFSU2_PAD_FAKE=PLUG=0 NFSU2_PAD_LOG=1 QUITFRAMES=4500
    check "NFSU2_PAD=$m: plugged in mid-race, the rescan creates the device" "$L" "CreateDevice -> 0x[0-9a-f]+ \(Fake Pad\)"
    check "NFSU2_PAD=$m: it drives (stick, trigger, RB)" "$L" "${IN}steer \+1\.00 throttle 1\.00 brake 0\.00 e-brake 1\.00"
    v=$(LC_ALL=C sed -n '/log:unplug/,/log:plug back in/p' "$L" | grep -a -c -E "${IN}steer -0\.00 throttle 0\.00 brake 0\.00 e-brake 0\.00")
    if [ "$v" = 2 ]; then printf "  PASS  NFSU2_PAD=%s: unplugged, nothing stuck\n" $m; else printf "  FAIL  NFSU2_PAD=%s: unplugged, nothing stuck\n" $m; FAILED=1; fi
    if [ $m = hotplug ]; then check "hotplug: DIERR_INPUTLOST on the unplug" "$L" "unplugged: DIERR_INPUTLOST"
    else nocheck "default: the device stays (no DIERR_INPUTLOST)" "$L" "DIERR_INPUTLOST"; fi
done
echo
if [ $FAILED = 0 ]; then echo "RESULT: all passed"; else echo "RESULT: SOME FAILED"; fi
exit $FAILED
