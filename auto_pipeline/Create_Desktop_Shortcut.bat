@echo off
rem ====================================================================
rem  Puts a "Run WF Pipeline" shortcut on the desktop pointing at
rem  Run_WF_Pipeline.bat. Run this once; after that the desktop icon is
rem  the only thing you need to touch.
rem ====================================================================

set "TARGET=%~dp0Run_WF_Pipeline.bat"
set "LINK=%USERPROFILE%\Desktop\Run WF Pipeline.lnk"

if not exist "%TARGET%" (
    echo Could not find Run_WF_Pipeline.bat next to this file.
    pause
    exit /b 1
)

powershell -NoProfile -Command ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut('%LINK%');" ^
  "$s.TargetPath = '%TARGET%';" ^
  "$s.WorkingDirectory = '%~dp0';" ^
  "$s.IconLocation = 'shell32.dll,137';" ^
  "$s.Description = 'Run the LGN widefield analysis pipeline';" ^
  "$s.Save()"

if exist "%LINK%" (
    echo Shortcut created:
    echo   %LINK%
) else (
    echo Shortcut creation failed. You can drag Run_WF_Pipeline.bat to the
    echo desktop with the right mouse button and choose "Create shortcuts here".
)

echo.
pause
