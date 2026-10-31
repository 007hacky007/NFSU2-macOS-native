#!/bin/bash
# tests/run_suite.sh -- the test entry point.
#
#   tests/run_suite.sh                     the unit-level suites (no game files):
#                                          every tests/<name>.sh below, each
#                                          building into a temp folder; then
#                                          a summary.  Exit 0 when all pass.
#   tests/run_suite.sh --game <outdir> [scenario...]
#                                          the scripted game scenarios
#                                          (tests/scripts/*.txt, runtime/autotest.c)
#                                          through tools/autorun.sh, one game at a
#                                          time; NFSU2_DATA = the game folder or
#                                          SPEED2.EXE, NFSU2_BIN = the engine in
#                                          out/ (nfsu2_na_boot for the North
#                                          American SPEED2.EXE).  The same scripts
#                                          run on both: their addresses are
#                                          European and mapped on the NA build.
#
# A unit suite passes when its script exits 0.  Some need a Metal device or
# swiftc and say SKIP without them; network tests stay on loopback / AF_UNIX
# inside tests/net/loopback-only.sb.
#
# A game scenario passes when the run exits 0 via the script's "quit", with no
# fault ("FAULT IN GUEST", ...), no time limit reached, no unresolved indirect
# call, no failed "expect" check, no "waitfng/waitmem/... TIMEOUT", no
# "[net] BLOCKED" / "[roam] BLOCKED" line (an attempt to reach a network
# beyond loopback / the virtual LAN), and (where given) the expected marker in
# the log.  The other game-level tests have their own scripts (tests/README.md).
# Ported from th0mk's nfsu2-web tests/run_suite.sh (MIT).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ "${1:-}" != --game ]; then
  UNITS="${UNITS:-hle_unit watchdog_unit heap_stress windows_waits framerate keyboard_unit horn_unit gamepad_harness
    radio_native native_scene headlights_native shader_ps20 save_paths texpack_unit texrep_native game_folder_tools
    net_harness roam_unit photo_gallery save_manager display_options language_packs texture_packs}"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  pass=0; fail=0; failed=""
  for u in $UNITS; do
    [ -f "tests/$u.sh" ] || { echo "MISSING tests/$u.sh"; fail=$((fail+1)); failed="$failed $u"; continue; }
    t0=$(date +%s)
    if bash "tests/$u.sh" > "$TMP/$u.txt" 2>&1; then
      pass=$((pass+1)); echo "PASS  $u  ($(( $(date +%s) - t0 )) s)  $(grep -a -E 'passed|PASS' "$TMP/$u.txt" | tail -1 | cut -c1-90)"
    else
      fail=$((fail+1)); failed="$failed $u"; echo "FAIL  $u  ($(( $(date +%s) - t0 )) s)"
      grep -a -E "FAIL|error|Error" "$TMP/$u.txt" | head -8 | sed 's/^/        /'
    fi
  done
  echo; echo "unit suites: $pass passed, $fail failed${failed:+ (}${failed# }${failed:+)}"
  [ $fail -eq 0 ] && echo "RESULT: all passed" || echo "RESULT: SOME FAILED"
  [ $fail -eq 0 ]; exit
fi

shift
OUT="${1:?usage: tests/run_suite.sh --game <outdir> [scenario...]}"; shift
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
SEED="${NFSU2_REGFILE_SEED:-}"
FLOW='waitmem [0x008654a4]==6 satisfied'
# name : script : expected log marker : extra env
# (careerbot: the test-only career bot, runtime/career.c, ends the run itself)
ALL="
quickrace:quickrace.txt:$FLOW:
sprint:qr_mode1.txt:$FLOW:
drag:qr_mode2.txt:$FLOW:
drift:qr_mode3.txt:$FLOW:
streetx:qr_mode4.txt:$FLOW:
url:qr_mode5.txt:$FLOW:
career:career_prologue.txt:waitfng HUD_SingleRace.fng satisfied:
customize:mainmenu_item3.txt:screen UI_GenericParts_Browser.fng:
movies:career_movies.txt:tapuntil UI_StartCareer.fng satisfied:NOMOVIES=0
options:options_display.txt:[D3D] Reset:
hornvolume:options_horn.txt:[horn] volume 85 %:NFSU2_HORN=1
hornpause:pause_horn.txt:parts as SLIDER_BASE_8 SLIDER_KNOB_8 SLIDER_HANDLE_8 SLIDER_BEG_8 SLIDER_END_8:NFSU2_HORN=1
powerunits:options_units.txt:units: power in bhp:
eucars:qr_eucars.txt:[expect] PASS:
replay:replay_pause.txt:LOG back_to_pause:
photo:photo_mode.txt:[expect] PASS:NFSU2_PHOTO=1
headlights:native_headlights.txt:[expect] PASS:NFSU2_PHOTO=1 NFSU2_FPS=120
watchdog:watchdog_loading.txt:no Present for:ALARM=400
fespinners:fe_spinners.txt:LOG SPINDONE:
cutscenes60:cutscenes60.txt:[expect] PASS:NFSU2_CUTSCENES_60=1 NFSU2_FPS=120
heapreset:heap_resetloop.txt:[status] after_reset_8:
padrace:pad_quickrace.txt:$FLOW:
padfe:pad_fe_buttons.txt:waitfng UI_OptionsMain.fng satisfied:
kbprofile:kb_profile.txt:LOG Cmd-Q now:
kbfocus:kb_focus_mouse.txt:$FLOW:
wscameras:ws_cameras.txt:$FLOW:
wspause:ws_pause.txt:$FLOW:
careerbot:career_bot.txt:segment done:NFSU2_CAREER_BOT_RACES=2 ALARM=900
lan_host:lan_host_short.txt:waitfng UI_OLMAIN.fng satisfied:NFSU2_NET=loopback NFSU2_NET_LOOPOFFSET=2101
"
pass=0; fail=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IFS=: read -r name script marker extra <<< "$line"
  [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name" && continue
  d="$OUT/$name"; rm -rf "$d"
  # shellcheck disable=SC2086
  "$ROOT/tools/autorun.sh" "$d" ${SEED:+NFSU2_REGFILE_SEED="$SEED"} NFSU2_DISCORD=0 NFSU2_FNG_LOG=1 \
     NFSU2_STATUS_EVERY=1200 ALARM=400 NFSU2_INPUT_SCRIPT="$ROOT/tests/scripts/$script" ${extra:+$extra} > "$d.run" 2>&1 < /dev/null
  rc=$?; log="$d/log.txt"; why=""
  [ $rc -eq 0 ] || why="$why exit=$rc"
  # a script that ends with Cmd-Q / "close" ends the game the player's way, without "quit"
  if grep -v '^[[:space:]]*#' "$ROOT/tests/scripts/$script" | grep -qiE '[[:space:]](close|nstap[[:space:]]+cmd\+Q)'; then :
  else LC_ALL=C grep -aq "quit at guest frame\|segment done" "$log" || why="$why no-quit"; fi
  LC_ALL=C grep -aq "FAULT IN GUEST\|GUEST MEMORY FAULT\|HOST SEGV" "$log" && why="$why fault"
  LC_ALL=C grep -aq "TIME LIMIT REACHED\|ALARM:" "$log" && why="$why timeout"
  LC_ALL=C grep -aq "UNRESOLVED INDIRECT" "$log" && why="$why unresolved-icall"
  LC_ALL=C grep -aq "^\[expect\] FAIL" "$log" && why="$why expect-failed"
  LC_ALL=C grep -aq "^\[autotest\] .*TIMEOUT" "$log" && why="$why wait-timeout"
  LC_ALL=C grep -aq "^\[autotest\] script line\|^\[autotest\] line [0-9]*: 0x" "$log" && why="$why script-error"
  LC_ALL=C grep -aq "^\[net\] BLOCKED\|^\[roam\] BLOCKED" "$log" && why="$why net-blocked"
  [ -n "$marker" ] && ! LC_ALL=C grep -aqF "$marker" "$log" && why="$why missing:'$marker'"
  st=$(LC_ALL=C grep -a "^\[status\]" "$log" | tail -1 | sed 's/^\[status\] //')
  if [ -z "$why" ]; then pass=$((pass+1)); echo "PASS $name  ($st)"; else fail=$((fail+1)); echo "FAIL $name:$why"; fi
done <<< "$ALL"
echo "scenarios: $pass passed, $fail failed  (logs and frame dumps: $OUT/<name>/)"
[ $fail -eq 0 ]
