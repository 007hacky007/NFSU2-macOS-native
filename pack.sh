#!/bin/bash
# Build the out/NFSU2.app bundle (or out/NFSU2 HD.app with --hd).
#
#   ./pack.sh                 the port only (~35 MB) -- the game data is the user's
#   ./pack.sh --with-data     also copy the game data next to it (~1.5 GB)
#   ./pack.sh --zip           also produce NFSU2.zip for distribution
#   ./pack.sh --embed         PERSONAL single-piece app: the game data is embedded
#                             INSIDE the bundle (out/personal/, ~1.4 GB).  Since it
#                             contains the game itself it
#                             CANNOT BE DISTRIBUTED; no distribution folder / zip is made.
#   ./pack.sh --hd            "NFSU2 HD.app" from the HD build (graphics improvements;
#                             separate bundle id, separate log, sits next to the original)
#
# The game data does NOT go into the bundle BY DEFAULT: the app asks for the
# folder on first launch and remembers the choice.  That keeps the bundle small
# and everyone runs it with their own installation.
#
# Saves (career profiles) are, in EVERY bundle, OUTSIDE the app and the game
# folder, in ~/Library/Application Support/NFSU2 Kayitlar; settings in
# ~/.nfsu2_registry.  When a new version is shipped and the .app or the game
# folder is replaced, the player's progress isn't lost (runtime/bundle.m).
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"

WITH_DATA=0; MAKE_ZIP=0; HD=0; EMBED=0; SIGN_ID="${SIGN_ID:-}"
for a in "$@"; do
  case "$a" in
    --with-data) WITH_DATA=1 ;;
    --zip)       MAKE_ZIP=1 ;;
    --hd)        HD=1 ;;
    --embed)     EMBED=1 ;;
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
[ -x "$BIN" ] || { echo "build first: ./build.sh && ./link.sh  ($BIN missing)"; exit 1; }

if [ "$EMBED" = 1 ] && { [ "$WITH_DATA" = 1 ] || [ "$MAKE_ZIP" = 1 ]; }; then
  echo "--embed is for personal use; it can't be combined with --with-data / --zip"; exit 1
fi
OUTDIR="$ROOT/out"; [ "$EMBED" = 1 ] && OUTDIR="$ROOT/out/personal"
mkdir -p "$OUTDIR"
APP="$OUTDIR/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/NFSU2"
chmod +x "$APP/Contents/MacOS/NFSU2"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- icon ---
if [ -x "$ROOT/.venv/bin/python" ]; then
  "$ROOT/.venv/bin/python" "$ROOT/tools/mkicon.py" "$APP/Contents/Resources/AppIcon.icns" >/dev/null
else
  echo "warning: no .venv, icon not generated"
fi

# --- embedded game data (--embed only) ---
# cp -c: APFS clone.  Takes NO extra space on the same disk and finishes
# instantly; if cloning isn't supported cp falls back to a normal copy by itself.
if [ "$EMBED" = 1 ]; then
  SRC="$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2"
  [ -f "$SRC/SPEED2.EXE" ] || { echo "game data not found: $SRC"; exit 1; }
  echo "embedding the game data in the bundle..."
  cp -Rc "$SRC" "$APP/Contents/Resources/Game"
  # MOVIES: no VP6 decoder, the game skips them anyway (~249 MB).
  # dinput8.dll / SCRIPTS / server.*: Windows plugins, not loaded by the native port.
  rm -rf "$APP/Contents/Resources/Game/MOVIES" "$APP/Contents/Resources/Game/SCRIPTS" \
         "$APP/Contents/Resources/Game/dinput8.dll" "$APP/Contents/Resources/Game/server.dll" \
         "$APP/Contents/Resources/Game/server.cfg" "$APP/Contents/Resources/Game/SafeMode.bat"
  find "$APP/Contents/Resources/Game" -name .DS_Store -delete
fi

VER="$(date +%Y.%m.%d)"
# Version tracking (see link.sh): shows in Finder like "2.0 (2026.10.18)".
VERSION="$(tr -cd '0-9' < "$ROOT/VERSION" 2>/dev/null)"; VERSION="${VERSION:-0}"
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
  <key>NSHumanReadableCopyright</key>
    <string>x86 -> ARM64 static recompilation port. The game itself is not included in this bundle.</string>
</dict>
</plist>
PLIST

# --- signature ---
# If SIGN_ID is given, sign with a real certificate (for those with an Apple
# Developer account), otherwise ad-hoc.  An ad-hoc signature does NOT PASS
# Gatekeeper: the downloaded bundle is "spctl: rejected", the user has to remove the quarantine.
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --sign "$SIGN_ID" --timestamp "$APP" \
    && echo "signature: $SIGN_ID" || { echo "codesign FAILED"; exit 1; }
else
  codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
    && echo "signature: ad-hoc (not notarized)" || echo "warning: codesign failed"
fi

# clear extended attributes (quarantine etc. coming from the source tree)
xattr -cr "$APP" 2>/dev/null || true

SZ="$(du -sh "$APP" | cut -f1)"
echo "ready: $APP  ($SZ)"

if [ "$EMBED" = 1 ]; then
  echo "personal single-piece app ready (DON'T DISTRIBUTE: it contains the game itself)."
  echo "saves: ~/Library/Application Support/NFSU2 Kayitlar"
  exit 0
fi

# --- read-me note for testers ---
if [ "$WITH_DATA" = 1 ]; then
  DATA="The game files come in the folder next to it (nothing else needed)."
  STEP3="3. Open the app.  IMPORTANT: keep $NAME.app and the
   \"Need for Speed Underground 2\" folder next to it in the SAME place; the app
   looks for the game next to itself.  You can move the two together."
else
  DATA="Your own NFSU2 installation.  The game files are NOT INCLUDED in this bundle."
  STEP3="3. Open the app.  On first launch it asks for the folder the game is
   installed in (the folder containing SPEED2.EXE).  The choice is remembered."
fi
cat > "$ROOT/out/README.txt" <<TXT
$DISP -- native macOS (Apple Silicon) port
================================================================
The x86 code was statically recompiled to ARM64.  No Wine, no emulator.

REQUIREMENTS
  - An Apple Silicon Mac (M1 or later).  Intel Macs can't run it.
  - macOS 11 Big Sur or later.
  - $DATA

INSTALLATION
1. Drag $NAME.app into the Applications folder.
2. Open Terminal and run this line:

     xattr -dr com.apple.quarantine "/Applications/$NAME.app"

   This step is REQUIRED.  Since the app isn't notarized by Apple, macOS
   refuses to open it after downloading (it says "damaged" or "the developer
   cannot be verified").  The command only removes the download tag.
$STEP3

USAGE
  Enter        skip the title screen
  Cmd-F        fullscreen
  Cmd-Q        quit
  Resolution   from the game's own menu: Options > Display.
               The 1920x1080 row in the list is for widescreen.

IF SOMETHING GOES WRONG
  Log:  ~/Library/Logs/NFSU2/nfsu2${TAG}.log        (the previous one: nfsu2${TAG}-previous.log)
  Send this file, it says what happened.

  To choose the game folder again:
     defaults delete $BID

SAVES
  Career saves:  ~/Library/Application Support/NFSU2 Kayitlar
  Settings:      ~/.nfsu2_registry
  Both live OUTSIDE the app and the game folder: when a new version comes
  out, replacing $NAME.app (or the game folder) doesn't delete your
  progress.  To back up, copying this folder and this file is enough.

  Profile name: typed on the "Create Profile" screen.  Delete the preset
  "NAME" in the box with the Delete (backspace) key, type at most 7
  letters/digits, Enter.
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
