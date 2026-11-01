# NFSU2 Builder - design

Date: 2026-11-01. Status: agreed in conversation, ready for planning.

## Why

This fork publishes no ready-made `NFSU2.app`. The translated game code is made from each player's own `SPEED2.EXE`, so every player builds the app on their own Mac. Today that means Terminal, the Xcode command line tools, a Python with the right packages, `tools/gen_v2.sh`, `build.sh`, `link.sh` and `pack.sh`. That loses most players.

NFSU2 Builder is a small app that a player double-clicks. It shows in plain words what is missing, fixes each item with one button, and builds `NFSU2.app` from the player's own game copy. It follows the NFSV Builder (`../NFSV/builder`, its design `../NFSV/docs/superpowers/specs/2026-10-30-nfsv-builder-design.md` and plan `../NFSV/docs/superpowers/plans/2026-10-31-nfsv-builder.md`) as closely as NFSU2 allows. Where this document says nothing, do what the NFSV Builder does.

## What gets built

1. **NFSU2 Builder.app**: a native Swift app (SwiftPM, `builder/` with `BuilderCore` and `NFSU2Builder`, as in NFSV) with a checklist and a build progress view.
2. **A GitHub Actions release pipeline**: on a `v*` tag it tests, builds the Builder, packs it in a DMG and publishes a GitHub Release with `NFSU2-Builder.dmg` and its SHA-256.
3. **A DMG** with the NFSV illustrated background (the drawn "Not Opened" alert, Privacy & Security, Open Anyway), renamed for NFSU2.
4. **README update**: the Builder becomes the way to get the game; the Terminal build stays documented for power users and LLM agents.

## Goals

- A player never opens Terminal.
- Every missing item is a green/amber/red row with a button that resolves it.
- One build logic: the Builder drives the same scripts as the Terminal build (`tools/gen_v2.sh`, `build.sh`, `link.sh`, `pack.sh`, `tools/install_from_discs.py`). No second implementation of lifting, compiling or packaging. Small non-interactive entry points (a check command, structured progress) may be added to the existing tools.
- Releases are automatic from a `v*` tag.
- The player knows before launching that macOS blocks the unsigned app, and which buttons to press.

## Non-goals

- A ready-made `NFSU2.app` anywhere: not on Releases, not in CI artifacts, not in the DMG.
- Notarization or Developer ID signing. Everything is ad-hoc signed (`codesign --sign -`).
- Intel Macs.
- Removing the command line tools requirement (clang and swiftc must run on the player's Mac).
- Replacing `build.sh` and the other scripts.

## Anti-goals (failure even if it works)

- Downloading the game, a game executable, a no-CD executable or a crack, or linking to where one can be found. The Builder and its docs name the accepted executables (version, size, SHA-256) and nothing more.
- Removing or getting around copy protection.
- Any EA code, game asset, translated function or executable in the repo, CI artifacts, DMG or Builder bundle.
- Changing the player's own game copy (folder, disc images, archives), their saves, or any Python they already have.
- Telemetry or any network traffic beyond the downloads named here.
- Personal data of the owner anywhere in the app, DMG, workflow or release (published under `007hacky007`).
- Em-dashes or en-dashes in user-facing text or docs (hyphen-minus only). No AI attribution in commits, release notes or docs.
- Dark "warez" styling or scary wording.

## The game copy

Facts this design rests on (verified 2026-11-01 on the EU discs, EA's UK v1.2 patch and the two supported folders):

- The build accepts exactly two executables, both v1.2 without the CD check:

  | `SPEED2.EXE` | Size | SHA-256 |
  |---|---|---|
  | European v1.2, no CD check | 4,788,224 | `8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297` |
  | North American v1.2, no CD check | 4,800,512 | `f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7` |

- The retail disc executable (EU 5,987,980 bytes, US v1.0 5,987,981) is SafeDisc-protected. EA's official v1.2 patch keeps SafeDisc (patched EU file: 5,987,979 bytes, `stxt774`/`stxt371` sections, encrypted code), so it cannot be used either. The Builder never downloads EA's patch: it would not help.
- The official v1.2 patch changes only three files: `SPEED2.EXE`, `server.dll` and `FRONTEND/FrontB.lzc`. The other 1,213 files of the EU disc are byte-identical before and after.
- Either region's data works with either supported executable: the runtime picks the region from the data (README, "US data works with the supported executable").
- `tools/install_from_discs.py` turns the two disc images (`.cue`/`.bin`, `.iso`, or disc folders) into a normal game folder.

### Step 1: game data

**Choose...** (and drag and drop) accepts a game folder, the two disc images (`.iso`, `.cue` + `.bin`, or disc folders), or an `NFSU2.app` with the game inside (an update, below).

- **Blocking (red):** only what the build and the first start need: the core files the game loads at startup, checked by name. The builder derives the exact list from what the game opens on boot (the file-access log of a boot run is one way).
- **Checked, never blocking:** every other file is compared with the known releases (a manifest of path, size and SHA-256 per known release, committed in the repo; the EU disc set, the EU v1.2 set and the NA set at least). Files that match are green. Files that differ or are unknown (another language, a repack, mods) give an amber note, for example: "This copy has 12 files that differ from the releases we know (another language or mods). It should work; if something looks wrong, report it with Copy details." Extra files are ignored.
- **`SPEED2.EXE` inside the data:** if it matches one of the two checksums, step 2 is done (green). Otherwise it is ignored; if it is the disc or official-patch version, the note says so in plain words ("This is the copy-protected disc version. The build needs v1.2 without the CD check.").
- **`server.dll`:** v1.0 or v1.2, both fine. Missing or unknown: amber, "LAN hosting may not work".

### Step 2: game program (only when step 1 did not provide it)

- **Choose...** accepts either the `SPEED2.EXE` file itself, or an archive (zip, rar, 7z). An archive is unpacked into a private temporary folder and searched (including subfolders) for a file matching one of the two checksums. Nothing from the archive is run, and nothing else from it is used. macOS's built-in `bsdtar` reads zip and rar; 7z may need a small bundled tool (builder's call).
- A file that matches neither checksum is refused with what it is, when known (disc version, official patch, unknown).
- **Which copy works?** lists the two accepted executables with size and SHA-256, and says the data can come from the discs of either region.

### The game inside the app

`NFSU2.app` carries the whole game, like the owner's other ports (NFSV, NFSMW, NFSIV): `Contents/Resources/Game` holds the verified data plus the supported `SPEED2.EXE` (about 1.8 GB). The app needs no game folder and can be moved anywhere; the launcher finds the game inside it first (`Paths.embeddedGame`).

- `tools/builder_cli.py` stages the data in the workspace (`out/game`): APFS clones of a folder on the same volume (a copy from another volume), or the discs unpacked with `install_from_discs.py`, with the chosen `SPEED2.EXE` put in. `pack.sh --embed` (with `GAME_DIR`) clones the staged tree into the app, and the staging copy is removed. The whole game goes in, Windows-only extras (`SCRIPTS`, `dinput8.dll`, `SafeMode.bat`) included; only `.DS_Store` files and macOS code (bundles, by extension or with `Contents/Info.plist`, scripts by extension or `#!`, libraries, Mach-O files, which could hide in a downloaded repack) are left out, and no game file stays executable. The game data keeps its quarantine: copies keep it (a copy that lost it stops the build), and files unpacked from a disc image or zip get the quarantine of the image or zip (`tools/quarantine.py`).
- The player's own copy is never written to. The Builder writes no launcher setting (no `OyunDizini`) and makes no `~/Games/NFSU2`.
- On the same disk the game costs no extra space (clones). Unpacked discs, a folder on another disk, or a destination on another disk count against the free-space check.
- Nothing may be written inside the app (it would break the ad-hoc signature): the engine writes only to its save layer (`~/Library/Application Support/NFSU2 Saves`), and the launcher makes language packs for a game inside the app in `~/Library/Application Support/NFSU2/LanguagePacks`, passed to the engine as `NFSU2_LANGPACKS`. With the game inside, the launcher offers no game folder to change.

### Updates

- The Builder writes its version into the app's `Info.plist` as `NFSBuilderVersion` (the same key in all four ports).
- On start the Builder looks for an `NFSU2.app` in the saved destination, else `/Applications`. If the game inside it passes the usual checks, it is preselected as the game data (and its `SPEED2.EXE` as the program); the row says it uses the game inside the current app, and the button reads **Update NFSU2.app (old -> new)**. If the game inside is missing or changed, the row falls back to the player's own choice with a short note. Everything the pipeline needs (`SPEED2.EXE` and `server.dll`) is in the bundled tree, so no original copy is asked for.
- The old app is only read. The new app is built completely in the workspace (its game cloned from the old one) and only then swapped in; on the same volume it is moved next to the old app and swapped in one step. If the old app is running, the Builder asks to quit it first.
- The launcher of a stamped app asks GitHub once a day (Settings > More > **Check for updates**, on by default; off makes no request) for the latest release, with User-Agent `NFSU2-Launcher`, 5 s at most, silently on failure. A newer Builder shows a notice with **What's new**, **Download** (the DMG's address in the browser) and **Not now** (hidden until a newer version).

## The Builder app

### Window

Same single-window checklist as NFSV (layout A), same status lights (green ready, amber handled or informational, red blocking, grey checking), same **Build NFSU2.app** button (**Update NFSU2.app** when one is replaced) enabled only when nothing is red.

| Row | Green when | Not green | Button |
|---|---|---|---|
| Mac | Apple Silicon, macOS 11+ | Red with the reason | none |
| Xcode command line tools | `clang`, `swiftc` and `codesign` found | Red, "needed to compile the game on your Mac, about 2 GB from Apple" | **Install...** (`xcode-select --install`), re-checks itself |
| Build tools (Python) | private Python + `requirements.txt` packages | Red with the download size | **Install** |
| Game data | step 1 passed | Red until chosen or when blocking files are missing; amber notes | **Choose...** |
| Game program | step 2 passed (or step 1 provided it) | Red until chosen | **Choose...**, **Which copy works?** |
| Destination | `/Applications` (or the chosen folder) writable: only where `NFSU2.app` goes | Red if not writable | **Change...** |
| Free disk space | enough on the workspace volume (and the destination's, when another one), counting the game where it cannot be cloned | Red with how much is needed | none |

### Building

Pressing **Build NFSU2.app** shows the progress view (as NFSV): stage the game data, lift (`tools/gen_v2.sh`), compile and link the original and HD engines (`build.sh`, `link.sh`), build the launcher and pack (`pack.sh`), sign. Only the engines for the player's executable are built (EU or NA, original and HD). Structured progress from the scripts, not scraped text; **Cancel** stops cleanly. The builder measures the real build time on an M1 Pro and puts it in the UI and README.

### When it finishes

As NFSV: `NFSU2.app` in the destination (an older one is replaced once the new one is complete; if it is running, ask the player to quit it first), with the text that the game is inside the app and the app can be moved anywhere, **Play**, **Show in Finder**, **Remove build files** (keeps the private Python). Failure: the step in plain words, the log, **Copy log**, **Try again**.

Saves and settings are outside the app (`~/Library/Application Support/NFSU2 Saves`, `~/.nfsu2_registry`), so replacing the app keeps the player's progress.

### Where it works

- Workspace `~/Library/Application Support/NFSU2 Builder/<version>/`: the bundled build sources are copied there and the scripts run with that copy as the repo root.
- Private Python `~/Library/Application Support/NFSU2 Builder/python/`: python-build-standalone `aarch64-apple-darwin` `install_only`, URL and SHA-256 pinned in the source; packages from `requirements.txt` into the workspace `.venv`.
- Never touches `/usr/bin/python3`, Homebrew or anything on `PATH`.

### Bundled sources

From the tagged commit, exactly what the build needs (`build.sh`, `link.sh`, `pack.sh`, `run.sh` if used, `tools/`, `runtime/`, `launcher/`, `app/` if present, `requirements.txt`, `VERSION`); not `tests/`, `docs/`, `screenshots/`, `gen/`, `out/`. Confirmed by a full build from the bundled copy on both EU and NA executables.

### Look

Native macOS look, light and dark. App icon as NFSV's (bright blue gradient, white generic coupe), not a real car or brand. The `NFSU2.app` it builds keeps its icon from the player's own `SPEED2.EXE` (`pack.sh` already does this).

## Distribution

- **DMG:** NFSV's final layout and background, with "NFSV Builder" replaced by "NFSU2 Builder". No Applications shortcut; the Builder runs from the DMG. The three bottom lines as in NFSV.
- **Release pipeline:** `.github/workflows/release.yml` on `v*` tags, GitHub-hosted Apple Silicon runner: run the tests that need no game copy, build the Builder (arm64, macOS 11+, version from the tag, bundled sources, ad-hoc signed), build the DMG with `dmgbuild`, publish the Release with the unversioned asset `NFSU2-Builder.dmg` and its SHA-256. Default `GITHUB_TOKEN` only.

## README

- The fork section points to the Builder as the only way to get the app. Upstream's "Releases page" links in the README point at upstream's builds; reword them so a reader of this fork is not sent there for this fork's app.
- A "Build from Terminal" section keeps the current instructions.
- The game-versions table stays; add the official-patch finding (v1.2 keeps SafeDisc) and that any region's data works.

## Open risks to verify early

The NFSV list applies unchanged: Open Anyway from a mounted DMG, quarantine on files the Builder writes (the private Python, the workspace and the built app), App Translocation, writing to `/Applications` without admin rights. Also:

- `swiftc` from the command line tools must build the launcher (it does today with `pack.sh`).
- The v1.0 `FrontB.lzc` and v1.0 `server.dll` with a v1.2 executable: menus, a race and one LAN host-and-leave cycle, on EU and NA. If something breaks, the data step turns that file's note into a clear warning.

## Left to the builder

SwiftUI vs AppKit details, how Swift talks to the scripts, the core file list, the exact disk and download numbers, error wording beyond the examples, how 7z is read.
