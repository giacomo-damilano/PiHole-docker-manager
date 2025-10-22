@echo off
:: ======================================================
::  Pi-hole Docker + DNS Switcher for Windows
::  Run this script as Administrator
:: ======================================================

setlocal EnableExtensions

:: ----- CONFIG -----
REM IP of your Pi-hole container or host
set "PIHOLE_IP=192.168.1.10"
REM Secondary DNS (Google, Cloudflare, etc.)
set "BACKUP_DNS=8.8.8.8"
set "COMPOSE_FILE=docker-compose.yml"
REM Max wait time in seconds for Docker readiness
set "MAX_WAIT=60"
REM Interval between checks (seconds)
set "WAIT_INTERVAL=5"

:: ----- CHECK DOCKER INSTALLED -----
where docker >nul 2>nul
if errorlevel 1 (
    echo "[ERROR] Docker not found in PATH. Please install Docker Desktop or add Docker CLI to PATH."
    pause
    exit /b 1
)

:: ----- WAIT FOR DOCKER TO START -----
call :BlankLine
echo Checking if Docker daemon is running...

:: Try to start the Docker Desktop service if it exists but is not yet running
set "DOCKER_SERVICE_STATE="
for /f "tokens=3" %%S in ('sc query com.docker.service 2^>nul ^| find "STATE"') do set "DOCKER_SERVICE_STATE=%%S"
if defined DOCKER_SERVICE_STATE if /i not "%DOCKER_SERVICE_STATE%"=="RUNNING" call :StartDockerService

set "elapsed=0"
:WAIT_DOCKER
docker info >nul 2>nul
set "rc=%errorlevel%"
if "%rc%"=="0" goto DOCKER_READY

if %elapsed% GEQ %MAX_WAIT% goto DOCKER_TIMEOUT

if %elapsed% EQU 0 goto FIRST_WAIT_MESSAGE
echo Waiting for Docker to start - %elapsed%s elapsed of %MAX_WAIT%s total.
goto AFTER_WAIT_MESSAGE

:FIRST_WAIT_MESSAGE
echo Docker is not ready yet. Waiting up to %MAX_WAIT% seconds for it to respond.

:AFTER_WAIT_MESSAGE
timeout /t %WAIT_INTERVAL% >nul
set /a elapsed+=WAIT_INTERVAL
goto WAIT_DOCKER

:DOCKER_TIMEOUT
echo Docker did not become ready within %MAX_WAIT% seconds.
pause
exit /b 1

:DOCKER_READY
echo Docker is running and ready.

:: ----- FIND ACTIVE NETWORK INTERFACE -----
call :BlankLine
echo Detecting active network interface...
set "INTERFACE="
for /f "skip=3 tokens=1,2,3,*" %%A in ('netsh interface show interface ^| findstr /R "^Enabled"') do (
    if /i "%%B"=="Connected" (
        if not defined INTERFACE (
            set "INTERFACE=%%D"
        )
    )
)

if not defined INTERFACE (
    echo "[ERROR] Unable to determine connected network interface."
    pause
    exit /b 1
)

echo Interface found: "%INTERFACE%"
call :BlankLine

:: ----- STORE CURRENT DNS SETTINGS -----
echo Backing up current DNS settings...
netsh interface ipv4 show dnsservers name="%INTERFACE%" > "%TEMP%\old_dns.txt"
findstr /R "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" "%TEMP%\old_dns.txt" > "%TEMP%\old_dns_only.txt"
set OLD_DNS=

for /f "usebackq tokens=1" %%A in ("%TEMP%\old_dns_only.txt") do (
    if not defined OLD_DNS (
        set OLD_DNS=%%A
    )
)

if not defined OLD_DNS (
    echo No static DNS detected, assuming DHCP mode.
    set OLD_DNS=dhcp
)

echo Previous DNS stored: %OLD_DNS%
call :BlankLine

:: ----- START DOCKER COMPOSE -----
echo Starting Pi-hole container...
docker compose -f "%COMPOSE_FILE%" up -d
if errorlevel 1 (
    echo "[ERROR] Failed to start Docker Compose. Aborting."
    goto END
)

:: ----- SET NEW DNS -----
call :BlankLine
echo Setting DNS to use Pi-hole (%PIHOLE_IP%) and backup (%BACKUP_DNS%)...
netsh interface ipv4 set dns name="%INTERFACE%" static %PIHOLE_IP% primary
netsh interface ipv4 add dns name="%INTERFACE%" %BACKUP_DNS% index=2
echo "[OK] DNS updated."
call :BlankLine

:: ----- MONITOR CONTAINER -----
echo Pi-hole is running. Waiting for container to stop...
:WAITLOOP
timeout /t 10 >nul
docker ps --format "{{.Names}}" | find /i "pihole" >nul
if not errorlevel 1 goto WAITLOOP

:: ----- RESTORE OLD DNS -----
call :BlankLine
echo Pi-hole container stopped. Restoring previous DNS...
if /i "%OLD_DNS%"=="dhcp" (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
) else (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" static %OLD_DNS%
)
echo "[OK] DNS restored to %OLD_DNS%."

:END
call :BlankLine
echo ------------------------------------------------------
echo All done. Pi-hole stopped, DNS restored.
echo ------------------------------------------------------
pause
goto :EOF

:BlankLine
echo.
exit /b

:StartDockerService
echo Starting Docker Desktop service ^(requires Docker Desktop installed^)...
net start com.docker.service >nul 2>nul
exit /b
