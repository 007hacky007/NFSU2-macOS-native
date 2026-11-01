#!/bin/bash
# Build the out/NFSU2.app bundle.
#
# The bundle opens a small launcher window (launcher/*.swift, Swift + SwiftUI):
# it finds and checks the game, lets the player pick Original or HD graphics and
# full screen, makes a portable copy with the game inside, then starts the engine.
#   Contents/MacOS/NFSU2              launcher (the bundle's executable)
#   Contents/MacOS/nfsu2-engine       out/nfsu2_boot     (original)
#   Contents/MacOS/nfsu2-engine-hd    out/nfsu2_hd_boot  (HD, if built)
#   Contents/MacOS/nfsu2-engine-na[-hd]  out/nfsu2_na[_hd]_boot  (North American v1.2, if built)
# Without swiftc the engine itself becomes Contents/MacOS/NFSU2 (no window), as before.
#
#   ./pack.sh                 the port only (~70 MB, both engines) -- the game data is the user's
#   ./pack.sh --with-data     also copy the game data next to it (~1.5 GB)
#   ./pack.sh --zip           also produce NFSU2.zip for distribution
#   ./pack.sh --embed         one app with the game data INSIDE the bundle
#                             (out/personal/NFSU2.app, ~1.8 GB, Contents/Resources/Game):
#                             it needs no game folder and can be moved anywhere.  It
#                             contains the game, so keep it for yourself; no distribution
#                             folder / zip is made.  GAME_DIR= names the game folder
#                             (default: the Clean Edition folder in the repository);
#                             NFSU2 Builder always builds this way.
#   ./pack.sh --hd            "NFSU2 HD.app" with the HD engine only (the older
#                             two-app layout; separate bundle id, sits next to NFSU2.app)
#   ./pack.sh --original-only NFSU2.app with the original engine only
#   ./pack.sh --region eu|na  NFSU2.app with only that executable's engines (NFSU2 Builder
#                             builds one region: European or North American v1.2)
#   BUILDER_VERSION=1.1.0     recorded in Info.plist as NFSBuilderVersion (NFSU2 Builder
#                             shows "1.0.0 -> 1.1.0" when it updates an app it made)
#
# Without --embed the game data does NOT go into the bundle: the app asks for the
# folder on first launch and remembers the choice.  That keeps the bundle small
# and everyone runs it with their own installation.
#
# Saves (career profiles) are, in EVERY bundle, OUTSIDE the app and the game
# folder, in ~/Library/Application Support/NFSU2 Saves; settings in
# ~/.nfsu2_registry.  When a new version is shipped and the .app or the game
# folder is replaced, the player's progress isn't lost (runtime/bundle.m).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"

WITH_DATA=0; MAKE_ZIP=0; HD=0; EMBED=0; ORIG_ONLY=0; REGION=""; SIGN_ID="${SIGN_ID:-}"
NEXT=""
for a in "$@"; do
  if [ "$NEXT" = region ]; then REGION="$a"; NEXT=""; continue; fi
  case "$a" in
    --region)    NEXT=region ;;
    --with-data) WITH_DATA=1 ;;
    --zip)       MAKE_ZIP=1 ;;
    --hd)        HD=1 ;;
    --embed)     EMBED=1 ;;
    --original-only) ORIG_ONLY=1 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done

if [ "$HD" = 1 ]; then
  BIN="$ROOT/out/nfsu2_hd_boot"; NAME="NFSU2 HD"; DISP="Need for Speed Underground 2 HD"
  BID="org.nfsu2.nativeport.hd"; TAG="-hd"
else
  BIN="$ROOT/out/nfsu2_boot";    NAME="NFSU2";    DISP="Need for Speed Underground 2"
  BID="org.nfsu2.nativeport";    TAG=""
fi
case "$REGION" in
  ""|eu) ;;
  na) [ "$HD" = 0 ] || { echo "--region na can't be combined with --hd"; exit 1; }
      BIN="$ROOT/out/nfsu2_na_boot" ;;
  *)  echo "--region must be eu or na"; exit 1 ;;
esac
[ -x "$BIN" ] || { echo "build first: ./build.sh && ./link.sh  ($BIN missing)"; exit 1; }

if [ "$EMBED" = 1 ] && { [ "$WITH_DATA" = 1 ] || [ "$MAKE_ZIP" = 1 ]; }; then
  echo "--embed puts the game inside the app; it can't be combined with --with-data / --zip"; exit 1
fi
OUTDIR="$ROOT/out"; [ "$EMBED" = 1 ] && OUTDIR="$ROOT/out/personal"
mkdir -p "$OUTDIR"
APP="$OUTDIR/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- launcher (rebuilt when a launcher/*.swift is newer) ---
LAUNCHER="$ROOT/out/nfsu2_launcher"
if [ ! -x "$LAUNCHER" ] || [ "$ROOT/runtime/names.h" -nt "$LAUNCHER" ] || [ -n "$(find "$ROOT/launcher" -name '*.swift' -newer "$LAUNCHER" 2>/dev/null)" ]; then
  echo "building the launcher..."
  # -target: runs on macOS 11 like the engine; -swift-version 5: no Swift 6 strict concurrency;
  # runtime/names.h: the free-roam room and crew names checked by the engine's own rules
  swiftc -swift-version 5 -O -target arm64-apple-macos11.0 -import-objc-header "$ROOT/runtime/names.h" -o "$LAUNCHER" "$ROOT"/launcher/*.swift \
    || { echo "warning: launcher build failed (swiftc missing?), bundling without it"; rm -f "$LAUNCHER"; }
fi

# --- engines ---
ENGINES=()
if [ -x "$LAUNCHER" ]; then
  cp "$LAUNCHER" "$APP/Contents/MacOS/NFSU2"
  if [ "$HD" = 1 ]; then
    cp "$BIN" "$APP/Contents/MacOS/nfsu2-engine-hd"; ENGINES+=(nfsu2-engine-hd)
  elif [ "$REGION" != na ]; then
    cp "$BIN" "$APP/Contents/MacOS/nfsu2-engine"; ENGINES+=(nfsu2-engine)
    if [ "$ORIG_ONLY" = 0 ] && [ -x "$ROOT/out/nfsu2_hd_boot" ]; then
      cp "$ROOT/out/nfsu2_hd_boot" "$APP/Contents/MacOS/nfsu2-engine-hd"; ENGINES+=(nfsu2-engine-hd)
    fi
  fi
  # North American v1.2 engines (BUILD=na ./build.sh && BUILD=na ./link.sh), if built;
  # the launcher picks them by the SPEED2.EXE it finds.
  if [ "$HD" = 0 ] && [ "$REGION" != eu ] && [ -x "$ROOT/out/nfsu2_na_boot" ]; then
    cp "$ROOT/out/nfsu2_na_boot" "$APP/Contents/MacOS/nfsu2-engine-na"; ENGINES+=(nfsu2-engine-na)
  fi
  if [ "$ORIG_ONLY" = 0 ] && [ "$REGION" != eu ] && [ -x "$ROOT/out/nfsu2_na_hd_boot" ]; then
    cp "$ROOT/out/nfsu2_na_hd_boot" "$APP/Contents/MacOS/nfsu2-engine-na-hd"; ENGINES+=(nfsu2-engine-na-hd)
  fi
else
  cp "$BIN" "$APP/Contents/MacOS/NFSU2"     # old layout: the engine is the executable
fi
chmod +x "$APP/Contents/MacOS/"*
# the Texture Packs window's list (launcher/TexturePackCatalog.swift)
cp "$ROOT/launcher/texture-packs.json" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- icon ---
# The game's own icon, traced to vectors, when SPEED2.EXE is here (tools/exeicon.py;
# ICON_EXE= picks another one); otherwise the drawn speedometer (tools/mkicon.py).
ICON_EXE="${ICON_EXE:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2/SPEED2.EXE}"
if [ ! -x "$ROOT/.venv/bin/python" ]; then
  echo "warning: no .venv, icon not generated"
elif [ -f "$ICON_EXE" ] && "$ROOT/.venv/bin/python" "$ROOT/tools/exeicon.py" "$ICON_EXE" "$APP/Contents/Resources/AppIcon.icns" >/dev/null; then
  :
else
  "$ROOT/.venv/bin/python" "$ROOT/tools/mkicon.py" "$APP/Contents/Resources/AppIcon.icns" >/dev/null
fi

# --- embedded game data (--embed only) ---
# /bin/cp -c: APFS clones.  Take NO extra space on the same disk and finish
# instantly; on another disk (or one that can't clone) it is a normal copy.  The
# source is only read.  Left out: Windows-only plugins and scripts the native port
# never loads (as the launcher's portable copy, launcher/Portable.swift) and
# Finder's .DS_Store files.  server.dll and server.cfg stay: hosting a LAN game
# loads them.
if [ "$EMBED" = 1 ]; then
  SRC="${GAME_DIR:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2}"
  [ -f "$SRC/SPEED2.EXE" ] || [ -f "$SRC/speed2.exe" ] || [ -f "$SRC/Speed2.exe" ] \
    || { echo "game data not found: $SRC"; exit 1; }
  echo "embedding the game data in the bundle..."
  GAME="$APP/Contents/Resources/Game"
  mkdir -p "$GAME"
  for item in "$SRC"/*; do
    [ -e "$item" ] || [ -L "$item" ] || continue
    name="$(basename "$item")"
    case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
      .*|scripts|dinput8.dll|safemode.bat) continue ;;
    esac
    /bin/cp -Rc "$item" "$GAME/$name" 2>/dev/null || { rm -rf "$GAME/$name"; /bin/cp -R "$item" "$GAME/$name"; } \
      || { echo "could not copy $name into the app"; exit 1; }
  done
  find "$GAME" -name .DS_Store -delete
  # No macOS code from the player's copy goes into the app: the game is Windows
  # files only, and a Mac program hidden in a downloaded repack must not end up
  # inside a signed app (it would lose the quarantine check below).  Windows files
  # and mods stay.
  find "$GAME" \( -iname '*.app' -o -iname '*.framework' -o -iname '*.bundle' -o -iname '*.plugin' \
      -o -iname '*.kext' -o -iname '*.pkg' -o -iname '*.mpkg' -o -iname '*.workflow' \) -prune \
      -exec echo "left out of the app (macOS code): {}" \; -exec rm -rf {} +
  find "$GAME" -type f \( -iname '*.command' -o -iname '*.tool' -o -iname '*.sh' -o -iname '*.dylib' \
      -o -iname '*.so' -o -iname '*.scpt' \) -exec echo "left out of the app (macOS code): {}" \; -delete
  find "$GAME" -type f -size +3c -exec sh -c '
    for f; do
      case "$(od -An -tx1 -N4 "$f" | tr -d " \n")" in
        feedface|cefaedfe|feedfacf|cffaedfe|cafebabe|bebafeca)
          echo "left out of the app (macOS code): $f"; rm -f "$f" ;;
      esac
    done' sh {} +
fi

# Extended attributes off before signing: codesign --strict refuses resource
# forks and Finder info inside a bundle.  Everything this script made loses all
# of them (quarantine too).  The game data copied from the player's own copy only
# loses those two, so a download's quarantine stays on its files (the game only
# reads them).
clear_attrs(){
  local p
  for p in "$APP" "$APP/Contents" "$APP/Contents/Resources"; do xattr -c "$p" 2>/dev/null; done
  for p in "$APP/Contents"/* "$APP/Contents/Resources"/*; do
    case "$p" in "$APP/Contents/Resources"|"$APP/Contents/Resources/Game") continue ;; esac
    xattr -cr "$p" 2>/dev/null
  done
  if [ -d "$APP/Contents/Resources/Game" ]; then
    xattr -c "$APP/Contents/Resources/Game" 2>/dev/null
    xattr -dr com.apple.FinderInfo "$APP/Contents/Resources/Game" 2>/dev/null
    xattr -dr com.apple.ResourceFork "$APP/Contents/Resources/Game" 2>/dev/null
  fi
  return 0
}

VER="$(date +%Y.%m.%d)"
# Version tracking (see link.sh): shows in Finder like "2.0 (2026.10.18)".
VERSION="$(tr -cd '0-9' < "$ROOT/VERSION" 2>/dev/null)"; VERSION="${VERSION:-0}"
# Builder version (NFSBuilderVersion) and the copyright line about the game data
BUILDER_KEY=""
case "${BUILDER_VERSION:-}" in
  "") ;;
  *[!0-9A-Za-z.+-]*) echo "BUILDER_VERSION must be a version like 1.1.0"; exit 1 ;;
  *) BUILDER_KEY="<key>NFSBuilderVersion</key>       <string>${BUILDER_VERSION}</string>" ;;
esac
if [ "$EMBED" = 1 ]; then
  GAME_NOTE="The game data inside this bundle comes from the player's own copy of the game."
else
  GAME_NOTE="The game itself is not included in this bundle."
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                <string>${NAME}</string>
  <key>CFBundleDisplayName</key>         <string>${DISP}</string>
  <key>CFBundleExecutable</key>          <string>NFSU2</string>
  <key>CFBundleIdentifier</key>          <string>${BID}</string>
  <key>CFBundleIconFile</key>            <string>AppIcon</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>${VERSION}.0</string>
  <key>CFBundleVersion</key>             <string>${VER}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key>      <string>11.0</string>
  <key>LSApplicationCategoryType</key>   <string>public.app-category.racing-games</string>
  <key>LSArchitecturePriority</key>      <array><string>arm64</string></array>
  ${BUILDER_KEY}
  <!-- Retina: without this key the window is drawn at 1x and scaled up
       by WindowServer (blurry image). -->
  <key>NSHighResolutionCapable</key>     <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
  <!-- The game folder may be in these directories; text of the permission prompt. -->
  <key>NSDesktopFolderUsageDescription</key>
    <string>To read the game files (SPEED2.EXE).</string>
  <key>NSDocumentsFolderUsageDescription</key>
    <string>To read the game files (SPEED2.EXE).</string>
  <key>NSDownloadsFolderUsageDescription</key>
    <string>To read the game files (SPEED2.EXE).</string>
  <key>NSRemovableVolumesUsageDescription</key>
    <string>To read the game files (SPEED2.EXE).</string>
  <key>NSLocalNetworkUsageDescription</key>
    <string>To play LAN races with other players on this network.</string>
  <key>NSHumanReadableCopyright</key>
    <string>x86 -> ARM64 static recompilation port. ${GAME_NOTE}</string>
</dict>
</plist>
PLIST

clear_attrs

# --- signature ---
# If SIGN_ID is given, sign with a real certificate (for those with an Apple
# Developer account), otherwise ad-hoc.  An ad-hoc signature does NOT PASS
# Gatekeeper: the downloaded bundle is "spctl: rejected", the user has to remove the quarantine.
# Nested executables first (the engines), then the bundle.
for e in "${ENGINES[@]}"; do
  if [ -n "$SIGN_ID" ]; then
    codesign --force --options runtime --sign "$SIGN_ID" --timestamp "$APP/Contents/MacOS/$e" || { echo "codesign FAILED: $e"; exit 1; }
  else
    codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/$e" 2>/dev/null || echo "warning: codesign failed: $e"
  fi
done
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --sign "$SIGN_ID" --timestamp "$APP" \
    && echo "signature: $SIGN_ID" || { echo "codesign FAILED"; exit 1; }
else
  codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
    && echo "signature: ad-hoc (not notarized)" || echo "warning: codesign failed"
fi

# again after signing (codesign can leave attributes behind), same rules
clear_attrs

SZ="$(du -sh "$APP" | cut -f1)"
echo "ready: $APP  ($SZ)"

if [ "$EMBED" = 1 ]; then
  echo "the game is inside the app: it can be moved anywhere (it contains the game, so keep it for yourself)."
  echo "saves: ~/Library/Application Support/NFSU2 Saves"
  exit 0
fi

# --- read-me note for testers ---
if [ "$WITH_DATA" = 1 ]; then
  DATA="The game files come in the folder next to the app (nothing else needed)."
  STEP3="3. Keep $NAME.app and the \"Need for Speed Underground 2\" folder next to
   each other; the app finds the game there by itself.  Move them together."
else
  DATA="Your own copy of the PC game, with one of these SPEED2.EXE files (v1.2
    without the CD check): the European one (4,788,224 bytes) or the North
    American one (4,800,512 bytes).  The app picks the matching engine.
    The US v1.0 disc SPEED2.EXE is copy-protected and cannot run.
    The game files are NOT included."
  STEP3="3. The first time, the window asks where the game is: click
   \"Choose Folder...\" and pick the folder that has SPEED2.EXE in it.
   The app remembers it."
fi
cat > "$ROOT/out/README.txt" <<TXT
$DISP -- native macOS (Apple Silicon) port
================================================================
The game's PC code, rebuilt to run natively on Apple Silicon.
No Wine, no emulator, no virtual machine.

YOU NEED
  - A Mac with Apple Silicon (M1 or later).  Intel Macs can't run it.
  - macOS 11 Big Sur or later.
  - $DATA

INSTALL
1. Drag $NAME.app into the Applications folder.
2. Double-click it.  The app is not from the App Store and not notarized by
   Apple, so the first time macOS stops it:
     - It says it "can't be opened" / "Apple could not verify" it:
       click Done, open System Settings > Privacy & Security, scroll down,
       click "Open Anyway" next to $NAME, then confirm.  (macOS 14 and
       older: right-click the app > Open > Open.)  Only needed once.
     - It says the app "is damaged": open the Terminal app, paste this line,
       press Return, then double-click the app again:

         xattr -dr com.apple.quarantine "/Applications/$NAME.app"

$STEP3
4. Click Play.

THE WINDOW
  Game files      where the game is and whether it is the right version.
  Graphics        Original = the PC look, least power.
                  HD = smoother edges and real reflections; the Mac gets warmer.
                  "Start in full screen" (Cmd-F also switches while playing).
  Portable copy   "Make Copy..." builds one app with the game inside it
                  (about 1.4 GB) that runs on its own, e.g. on another Mac.
                  It contains the game: keep it for yourself.
  Saves / Logs    open those folders.  Logs help when reporting a problem.
  Reset Graphics Settings   the game picks settings for this Mac again.
  If you untick "Show this window when the app opens", the game starts right
  away; hold the Option key while opening the app to see the window again.

PLAYING
  Enter        skip the title screen
  Cmd-F        full screen on/off
  Cmd-Q        quit
  Resolution   in the game: Options > Display.

IF SOMETHING GOES WRONG
  In the window click "Logs" and send the newest nfsu2 log file with
  "Report a Problem" (opens the project's issue page).

SAVES
  Career saves:  ~/Library/Application Support/NFSU2 Saves
  Settings:      ~/.nfsu2_registry
  Both live outside the app and the game folder, so replacing $NAME.app
  with a new version keeps your progress.  To back up, copy them.

  Profile name: on the "Create Profile" screen delete the preset "NAME"
  with the Delete key, type at most 7 letters/digits, press Enter.
TXT
echo "note: $ROOT/out/README.txt"

# --- distribution folder ---
# The app finds the game by itself by scanning the directory the .app is in (and
# the one above).  So the data goes NEXT TO the bundle, not INSIDE it: the
# signature stays intact.  Saves go to Application Support anyway.
DIST="$ROOT/out/NFSU2${TAG}-dist"
rm -rf "$DIST"; mkdir -p "$DIST"
ditto "$APP" "$DIST/$NAME.app"
cp "$ROOT/out/README.txt" "$DIST/"

if [ "$WITH_DATA" = 1 ]; then
  SRC="$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2"
  [ -f "$SRC/SPEED2.EXE" ] || { echo "game data not found: $SRC"; exit 1; }
  echo "copying the game data (large, a few minutes)..."
  # MOVIES: no VP6 decoder, the game skips them anyway (~249 MB)
  rsync -a --exclude='MOVIES/' "$SRC/" "$DIST/Need for Speed Underground 2/"
fi
echo "distribution folder: $DIST  ($(du -sh "$DIST" | cut -f1))"

if [ "$MAKE_ZIP" = 1 ]; then
  ZIP="$ROOT/out/NFSU2${TAG}.zip"; rm -f "$ZIP"
  # ditto: keeps the signature and bundle structure intact (zip -r breaks them)
  ditto -c -k --sequesterRsrc --keepParent "$DIST" "$ZIP"
  echo "distribution archive: $ZIP  ($(du -sh "$ZIP" | cut -f1))"
fi
