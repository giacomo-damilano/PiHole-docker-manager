@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "TEST_ROOT=%TEMP%\pihole-docker-loop-tests"
if not exist "%TEST_ROOT%" mkdir "%TEST_ROOT%"
if not exist "%TEST_ROOT%\logs" mkdir "%TEST_ROOT%\logs"

cls

echo ======================================================
echo Docker readiness loop diagnostic suite
echo ======================================================
echo.
where docker >nul 2>nul
if errorlevel 1 (
    echo [FATAL] Docker CLI not found in PATH. Install Docker Desktop or add docker.exe to PATH.
    exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
    echo [INFO] Initial docker info probe FAILED (daemon not yet available).
) else (
    echo [INFO] Initial docker info probe SUCCEEDED (daemon already reachable).
)

echo.
call :RunTest 1 "Multi-line IF/ELSE with ellipsis status message"
call :RunTest 2 "IF NOT ERRORLEVEL with status variable"
call :RunTest 3 "FOR /L loop capturing !errorlevel!"
call :RunTest 4 "Command chaining using explicit ERRORLEVEL variable"

echo.
echo Diagnostics complete. Individual logs stored under:
echo    %TEST_ROOT%\logs
echo.
exit /b 0

:RunTest
setlocal
set "ID=%~1"
set "TITLE=%~2"
set "SCRIPT=%TEST_ROOT%\test%ID%.bat"
set "LOG=%TEST_ROOT%\logs\test%ID%.log"
call :WriteTest%ID% "%SCRIPT%"
if errorlevel 1 (
    endlocal & echo [Test %ID%] Failed to generate helper script. & exit /b 1
)

echo ------------------------------------------------------
echo [Test %ID%] %TITLE%
echo Script: %SCRIPT%
echo Log:     %LOG%
echo ------------------------------------------------------
cmd /d /v:on /c "%SCRIPT%" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
echo ------------------------------------------------------
echo [Test %ID%] Exit code: %RC%
echo.
endlocal & exit /b 0

:WriteTest1
setlocal DisableDelayedExpansion
(
    echo @echo off
    echo setlocal EnableExtensions EnableDelayedExpansion
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set /a elapsed=0
    echo echo [Test 1] Starting multi-line IF/ELSE loop diagnostic.
    echo :LOOP
    echo docker info ^>nul 2^>nul
    echo if errorlevel 1 (
    echo^    if !elapsed! GEQ !MAX_WAIT! (
    echo^        echo [Test 1] Timeout reached inside multi-line IF/ELSE block.
    echo^        exit /b 2
    echo^    ^) else (
    echo^        echo [Test 1] Docker not ready yet... elapsed=!elapsed!s of !MAX_WAIT!s total.
    echo^    ^)
    echo^) else (
    echo^    echo [Test 1] Docker responded successfully.
    echo^    exit /b 0
    echo^)
    echo timeout /t !WAIT_INTERVAL! ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto LOOP
) > "%~1"
endlocal
exit /b 0

:WriteTest2
setlocal DisableDelayedExpansion
(
    echo @echo off
    echo setlocal EnableExtensions EnableDelayedExpansion
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set /a elapsed=0
    echo set "status_msg="
    echo echo [Test 2] Starting IF NOT ERRORLEVEL loop diagnostic.
    echo :LOOP
    echo docker info ^>nul 2^>nul
    echo if not errorlevel 1 goto READY
    echo if !elapsed! GEQ !MAX_WAIT! (
    echo^    echo [Test 2] Timeout reached using IF NOT ERRORLEVEL pattern.
    echo^    exit /b 2
    echo^)
    echo if !elapsed! EQU 0 (
    echo^    set "status_msg=[Test 2] Docker not ready on first attempt."
    echo^) else (
    echo^    set "status_msg=[Test 2] Docker still not ready after !elapsed!s of !MAX_WAIT!s."
    echo^)
    echo echo !status_msg!
    echo timeout /t !WAIT_INTERVAL! ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto LOOP
    echo :READY
    echo echo [Test 2] Docker responded successfully via IF NOT ERRORLEVEL.
    echo exit /b 0
) > "%~1"
endlocal
exit /b 0

:WriteTest3
setlocal DisableDelayedExpansion
(
    echo @echo off
    echo setlocal EnableExtensions EnableDelayedExpansion
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set /a attempts=MAX_WAIT / WAIT_INTERVAL
    echo if !MAX_WAIT! LSS 1 set "MAX_WAIT=1"
    echo if !WAIT_INTERVAL! LSS 1 set "WAIT_INTERVAL=1"
    echo if !attempts! LSS 1 set "attempts=1"
    echo echo [Test 3] Starting FOR /L loop diagnostic capturing !errorlevel!.
    echo for /l %%%%I in (0,1,!attempts!) do (
    echo^    docker info ^>nul 2^>nul
    echo^    set "rc=!errorlevel!"
    echo^    if !rc! EQU 0 (
    echo^        echo [Test 3] Docker responded successfully at iteration %%%%I (rc=!rc!).
    echo^        exit /b 0
    echo^    ^)
    echo^    if %%%%I GEQ !attempts! (
    echo^        echo [Test 3] Timeout reached after %%%%I iterations (rc=!rc!).
    echo^        exit /b 2
    echo^    ^)
    echo^    echo [Test 3] Docker not ready (iteration %%%%I, rc=!rc!).
    echo^    timeout /t !WAIT_INTERVAL! ^>nul
    echo^)
    echo exit /b 2
) > "%~1"
endlocal
exit /b 0

:WriteTest4
setlocal DisableDelayedExpansion
(
    echo @echo off
    echo setlocal EnableExtensions EnableDelayedExpansion
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set /a elapsed=0
    echo echo [Test 4] Starting explicit ERRORLEVEL capture with command chaining.
    echo :LOOP
    echo docker info ^>nul 2^>nul
    echo set "rc=!errorlevel!"
    echo if !rc! EQU 0 (
    echo^    echo [Test 4] docker info succeeded (rc=!rc!). Exiting loop.
    echo^    exit /b 0
    echo^)
    echo if !elapsed! GEQ !MAX_WAIT! (
    echo^    echo [Test 4] Timeout reached after !elapsed!s using command chaining pattern (last rc=!rc!).
    echo^    exit /b 2
    echo^)
    echo echo [Test 4] docker info failed with rc=!rc!, waiting !WAIT_INTERVAL!s before retry.
    echo timeout /t !WAIT_INTERVAL! ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto LOOP
) > "%~1"
endlocal
exit /b 0
