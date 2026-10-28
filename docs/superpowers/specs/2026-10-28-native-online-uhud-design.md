# Native NA runtime, UHUD and online play

The user approved adopting the newer nfsu2-web native code, dropping EU executable support, and adding UHUD and online play through the existing Mac launcher. Source: sibling nfsu2-web at cc3b3df. Target: NFSU2Recomp at b237c9d.

## Intended behavior

- Run the supported North American v1.2 executable natively on Apple Silicon through Metal.
- Reuse the donor's compiler, memory management, controller support, VP6 playback, frame pacing, widescreen fixes and regression tools as a coordinated native core upgrade.
- Keep the Swift launcher and portable-copy workflow. Keep existing saves and registry accessible without overwriting them. Retain original and HD engine choices.
- Offer Offline and Online in the launcher. Online accepts a compatible server URL and an explicitly entered player name. Default to Offline; never derive an online identity from host account details or the user's profile. Verify the relay locally, without joining a public server.
- Support the same relay protocol as browser players: free roam, and the game's online/LAN race traffic. Implement a native WebSocket transport and the required bridge rather than embedding a browser.
- Offer Original/UHUD textures in the launcher. Read an existing uhud.pak or the extracted UHUD assets from the supplied game folder; support importing a prepared pack. Leave game files unmodified. Preserve original dimensions for guest APIs and font/cursor measurements.
- Adapt the donor's ps_2_0 coordinate initialization fix to Metal and verify rendering.

## Implementation choices

Use the donor native runtime as the baseline because its compiler, allocation, hooks and multiplayer modules depend on one another. Preserve launcher source and adapt its configuration/environment interface. Use platform Foundation networking for TLS/WebSocket support, with no new external runtime dependency. An offline or failed connection must not prevent the launcher or offline game from working.

The user selected configurable servers and local verification. Defaults are wss://nfsu2.xyz/lan with queue/resume and https://nfsu2.xyz/players for player and crew counts. Their game folder contains the NA executable, server.dll and TEXPACKS/uhud.pak. Generated game C, assets and binaries remain ignored. Preserve donor copyright and MIT notices in a third-party notice. No publication, deployment or git commits with personal identity are authorized by this plan.

## Verification

Build the native runtime, both engines and the launcher. Run imported ISA/function tests and relevant heap, controller and networking units. Exercise scripted headless quick races, career/movie flows and texture selection where available. Use a local relay for handshake, traffic and disconnection tests, and verify two clients if feasible. Document any unavailable visual or physical-controller checks precisely.
