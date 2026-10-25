NFSRef - capturing reference images from the original game
==========================================================

This kit runs the same automated test as the Mac port in the original game on
Windows and saves images of the same frames. No manual screenshots are needed.

1. GAME FOLDER
   Use an exact copy of the game folder from the Mac ("Need for Speed
   Underground 2" - the one containing SPEED2.EXE). Another installation may
   contain a different exe or data files. You can put the folder anywhere; no
   installation is needed.

2. EXTRACT THE KIT
   Extract the contents of this zip into the game folder (next to SPEED2.EXE).
   Three files are added to the SCRIPTS folder: nfsref.asi, nfsref.ini,
   nfsref_registry.txt. No existing files are overwritten.

3. DIAGNOSTIC FIRST (40 seconds)
   Double-click NFSRef_diagnose.bat. The game opens, tries to get through the
   first menus by itself and closes itself after about 40 seconds.
   Send the "NFSRef_output" folder. Once frame counting and key sending are
   verified, move on to step 4.

4. FULL RUN
   Double-click NFSRef_start.bat.
   - The game opens fullscreen. It enters a race from the menus by itself.
   - The game runs at 60 fps and closes itself after about 2.5 minutes
     (frame 8950).
   - Don't touch the keyboard or mouse during this time, and don't switch to
     another window.
   - If a gamepad is connected, unplug it.
   - Sound can stay on.
   - If something goes wrong the game closes itself after 7 minutes at the
     latest; no Task Manager needed.

5. SEND
   An "NFSRef_output" folder is created in the game folder (about 300-400 MB).
   Zip the folder and send it. It contains:
   - frame_XXXXX.bmp     : images of the selected frames
   - frames.csv          : draw count and camera for every frame
   - calls_XXXXX.txt     : all D3D calls and state blocks in four frames
   - rt_XXXXX_*.bmp      : intermediate images in those frames (reflection cube etc.)
   - shaders\            : the game's shaders
   - sound_log.txt, sound_data.bin : what the game writes to DirectSound
   - nfsref_log.txt      : run log (if something goes wrong, the reason is here)

WHAT IT DOES (changes are in the game's memory, only for this run)
   - The game clock advances exactly 1/60 second every frame. So "frame N" is
     always the same moment of the game, independent of the PC's speed.
   - It presses the keys itself. The real keyboard and mouse are ignored.
   - It reads the graphics settings from nfsref_registry.txt. It writes nothing
     to the Windows registry.
   - Save/profile files go into NFSRef_output\save_001. Your existing profile
     is not used and doesn't change.
   - It temporarily moves WidescreenFix aside for the duration of the run and
     puts it back when done.

Antivirus software may warn about an unknown .asi file. The source code is in
the repository: tools/nfsref/nfsref.c
