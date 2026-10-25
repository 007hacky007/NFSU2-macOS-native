@echo off
rem NFSRef: capture reference frames from the original game.  Run it in the game folder.
cd /d "%~dp0"
if not exist "SPEED2.EXE" (
  echo ERROR: This file must be in the game folder ^(next to SPEED2.EXE^).
  pause
  exit /b 1
)
if not exist "SCRIPTS\nfsref.asi" (
  echo ERROR: SCRIPTS\nfsref.asi is missing. Extract the whole kit into the game folder.
  pause
  exit /b 1
)
rem WidescreenFix changes the game (FOV, HUD, frame limit); the port has none -> disable temporarily
if not exist "SCRIPTS_nfsref_disabled" mkdir "SCRIPTS_nfsref_disabled"
move /y "SCRIPTS\NFSUnderground2.WidescreenFix.*" "SCRIPTS_nfsref_disabled\" >nul 2>&1
rem the previous output is not deleted, it is kept as NFSRef_output_previous
if exist "NFSRef_output_previous" rmdir /s /q "NFSRef_output_previous"
if exist "NFSRef_output" ren "NFSRef_output" "NFSRef_output_previous"
echo.
echo NFSRef is running. The game will go from the menus into a race by itself and
echo CLOSE ITSELF after about 2.5 minutes (at frame 8950). Do not touch the keyboard/mouse
echo or switch to another window.
echo.
start "" /wait "SPEED2.EXE"
rem put WidescreenFix back
move /y "SCRIPTS_nfsref_disabled\NFSUnderground2.WidescreenFix.*" "SCRIPTS\" >nul 2>&1
rmdir "SCRIPTS_nfsref_disabled" >nul 2>&1
echo.
echo Done. Please zip the "NFSRef_output" folder and send it.
findstr /c:"DONE" "NFSRef_output\nfsref_log.txt" >nul 2>&1 || echo WARNING: the run does not look complete; send nfsref_log.txt anyway.
pause
