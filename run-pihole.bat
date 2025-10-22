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
    echo [ERROR] Docker not found in PATH. Please install Docker Desktop or add Docker CLI to PATH.
    pause
    exit /b 1
)

:: ----- WAIT FOR DOCKER TO START -----
echo(
echo Checking if Docker daemon is running...

:: Try to start the Docker Desktop service if it exists but is not yet running
set "DOCKER_SERVICE_STATE="
for /f "tokens=3" %%S in ('sc query com.docker.service 2^>nul ^| find "STATE"') do set "DOCKER_SERVICE_STATE=%%S"
if defined DOCKER_SERVICE_STATE (
    if /i not "%DOCKER_SERVICE_STATE%"=="RUNNING" (
        echo Starting Docker Desktop service (requires Docker Desktop installed)...
        net start com.docker.service >nul 2>nul
    )
)

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
echo(
echo Detecting active network interface...
for /f "tokens=2 delims=:" %%A in ('netsh interface show interface ^| find "Connected"') do (
    set "INTERFACE=%%A"
)
set INTERFACE=%INTERFACE:~1%
echo Interface found: "%INTERFACE%"
echo(

:: ----- STORE CURRENT DNS SETTINGS -----
echo Backing up current DNS settings...
netsh interface ipv4 show dnsservers name="%INTERFACE%" > "%TEMP%\old_dns.txt"
findstr /R "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" "%TEMP%\old_dns.txt" > "%TEMP%\old_dns_only.txt"
set OLD_DNS=

for /f "tokens=1" %%A in (%TEMP%\old_dns_only.txt) do (
    if not defined OLD_DNS (
        set OLD_DNS=%%A
    )
)

if not defined OLD_DNS (
    echo No static DNS detected, assuming DHCP mode.
    set OLD_DNS=dhcp
)

echo Previous DNS stored: %OLD_DNS%
echo(

:: ----- START DOCKER COMPOSE -----
echo Starting Pi-hole container...
docker compose -f "%COMPOSE_FILE%" up -d
if errorlevel 1 (
    echo [ERROR] Failed to start Docker Compose. Aborting.
    goto END
)

:: ----- SET NEW DNS -----
echo(
echo Setting DNS to use Pi-hole (%PIHOLE_IP%) and backup (%BACKUP_DNS%)...
netsh interface ipv4 set dns name="%INTERFACE%" static %PIHOLE_IP% primary
netsh interface ipv4 add dns name="%INTERFACE%" %BACKUP_DNS% index=2
echo [OK] DNS updated.
echo(

:: ----- MONITOR CONTAINER -----
echo Pi-hole is running. Waiting for container to stop...
:WAITLOOP
timeout /t 10 >nul
docker ps --format "{{.Names}}" | find /i "pihole" >nul
if not errorlevel 1 goto WAITLOOP

:: ----- RESTORE OLD DNS -----
echo(
echo Pi-hole container stopped. Restoring previous DNS...
if /i "%OLD_DNS%"=="dhcp" (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
) else (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" static %OLD_DNS%
)
echo [OK] DNS restored to %OLD_DNS%.

:END
echo(
echo ------------------------------------------------------
echo All done. Pi-hole stopped, DNS restored.
echo ------------------------------------------------------
pause
