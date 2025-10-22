@echo off
setlocal EnableExtensions

set "TEST_ROOT=%TEMP%\pihole-docker-loop-tests"
if not exist "%TEST_ROOT%" mkdir "%TEST_ROOT%" >nul 2>&1
if not exist "%TEST_ROOT%\logs" mkdir "%TEST_ROOT%\logs" >nul 2>&1

cls

echo ======================================================
echo Docker readiness loop diagnostic suite
echo ======================================================
echo(

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

echo(
call :RunTest 1 "IF ERRORLEVEL comparison"
call :RunTest 2 "Command chaining with && and ||"
call :RunTest 3 "Separate subroutine with explicit return codes"

echo(
echo Diagnostics complete. Individual logs stored under:
echo    %TEST_ROOT%\logs
echo(
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
cmd /d /c "%SCRIPT%" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
echo ------------------------------------------------------
echo [Test %ID%] Exit code: %RC%
echo(
endlocal & exit /b 0

:WriteTest1
(
    echo @echo off
    echo setlocal EnableExtensions
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set "elapsed=0"
    echo echo [Test 1] Starting IF ERRORLEVEL comparison diagnostic.
    echo :LOOP
    echo docker info ^>nul 2^>nul
    echo if errorlevel 1 goto NOT_READY
    echo echo [Test 1] docker info succeeded.
    echo exit /b 0
    echo :NOT_READY
    echo if %%elapsed%% GEQ %%MAX_WAIT%% goto GIVE_UP
    echo if %%elapsed%% EQU 0 (
    echo^    echo [Test 1] Docker not ready yet. Waiting up to %%MAX_WAIT%% seconds.
    echo^) else (
    echo^    echo [Test 1] Still waiting - %%elapsed%%s elapsed of %%MAX_WAIT%%s.
    echo^)
    echo timeout /t %%WAIT_INTERVAL%% ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto LOOP
    echo :GIVE_UP
    echo echo [Test 1] Timeout reached after %%MAX_WAIT%% seconds.
    echo exit /b 2
) > "%~1"
exit /b 0

:WriteTest2
(
    echo @echo off
    echo setlocal EnableExtensions
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set "elapsed=0"
    echo echo [Test 2] Starting command chaining diagnostic.
    echo :RETRY
    echo docker info ^>nul 2^>nul ^&^& goto READY
    echo if %%elapsed%% GEQ %%MAX_WAIT%% goto GIVE_UP
    echo if %%elapsed%% EQU 0 (
    echo^    echo [Test 2] Docker not ready yet. Waiting up to %%MAX_WAIT%% seconds.
    echo^) else (
    echo^    echo [Test 2] docker info failed; %%elapsed%%s elapsed of %%MAX_WAIT%%s.
    echo^)
    echo timeout /t %%WAIT_INTERVAL%% ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto RETRY
    echo :READY
    echo echo [Test 2] docker info succeeded using command chaining.
    echo exit /b 0
    echo :GIVE_UP
    echo echo [Test 2] Timeout reached after %%MAX_WAIT%% seconds.
    echo exit /b 2
) > "%~1"
exit /b 0

:WriteTest3
(
    echo @echo off
    echo setlocal EnableExtensions
    echo set "MAX_WAIT=12"
    echo set "WAIT_INTERVAL=3"
    echo set "elapsed=0"
    echo echo [Test 3] Starting subroutine-based diagnostic.
    echo :AGAIN
    echo call :ProbeDocker
    echo if errorlevel 1 goto HANDLE_WAIT
    echo echo [Test 3] Docker reported ready from subroutine.
    echo exit /b 0
    echo :HANDLE_WAIT
    echo if %%elapsed%% GEQ %%MAX_WAIT%% goto GIVE_UP
    echo if %%elapsed%% EQU 0 (
    echo^    echo [Test 3] Docker not ready yet. Waiting up to %%MAX_WAIT%% seconds.
    echo^) else (
    echo^    echo [Test 3] Still not ready, %%elapsed%%s elapsed of %%MAX_WAIT%%s.
    echo^)
    echo timeout /t %%WAIT_INTERVAL%% ^>nul
    echo set /a elapsed+=WAIT_INTERVAL
    echo goto AGAIN
    echo :GIVE_UP
    echo echo [Test 3] Timeout reached after %%MAX_WAIT%% seconds.
    echo exit /b 2
    echo :ProbeDocker
    echo docker info ^>nul 2^>nul
    echo if errorlevel 1 exit /b 1
    echo exit /b 0
) > "%~1"
exit /b 0
