@echo off
setlocal enabledelayedexpansion

rem ====================================================================
rem  LGN widefield pipeline - one-click launcher
rem
rem  Double-click this file (or its desktop shortcut) to start MATLAB and
rem  open the pipeline window. Nothing needs to be typed.
rem
rem  If MATLAB is installed somewhere unusual, set MATLAB_EXE below to the
rem  full path of matlab.exe and the search is skipped.
rem ====================================================================

set "MATLAB_EXE="

set "PIPE_DIR=%~dp0"
if "%PIPE_DIR:~-1%"=="\" set "PIPE_DIR=%PIPE_DIR:~0,-1%"

title LGN widefield pipeline
echo.
echo   LGN widefield pipeline
echo   ------------------------------------------------------------
echo   Folder: %PIPE_DIR%
echo.

rem ---- 1. explicit override ------------------------------------------
if not "%MATLAB_EXE%"=="" goto :found

rem ---- 2. matlab on the PATH ------------------------------------------
where matlab.exe >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where matlab.exe') do (
        set "MATLAB_EXE=%%i"
        goto :found
    )
)

rem ---- 3. standard install locations, newest release first ------------
for %%R in ("%ProgramFiles%\MATLAB" "%ProgramFiles(x86)%\MATLAB" "C:\MATLAB") do (
    if exist %%~R (
        for /f "delims=" %%V in ('dir /b /o-n "%%~R" 2^>nul') do (
            if exist "%%~R\%%V\bin\matlab.exe" (
                set "MATLAB_EXE=%%~R\%%V\bin\matlab.exe"
                goto :found
            )
        )
    )
)

echo   MATLAB could not be found automatically.
echo.
echo   Open this file in Notepad and set MATLAB_EXE near the top to the
echo   full path of matlab.exe, for example:
echo       set "MATLAB_EXE=C:\Program Files\MATLAB\R2023b\bin\matlab.exe"
echo.
pause
exit /b 1

:found
echo   MATLAB: %MATLAB_EXE%
echo   Starting - the pipeline window opens in a few seconds.
echo.

start "" "%MATLAB_EXE%" -nosplash -sd "%PIPE_DIR%" -r "try, run('%PIPE_DIR%\wf_pipeline_launch.m'); catch e, disp(getReport(e)); end"

exit /b 0
