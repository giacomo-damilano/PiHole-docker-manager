@echo off
:: ======================================================
::  Pi-hole Docker + DNS Switcher for Windows
::  Run this script as Administrator
:: ======================================================

setlocal enabledelayedexpansion

:: ----- CONFIG -----
set PIHOLE_IP=192.168.1.10        :: IP of your Pi-hole container or host
set BACKUP_DNS=8.8.8.8            :: Secondary DNS (Google, Cloudflare, etc.)
set COMPOSE_FILE=docker-compose.yml
set MAX_WAIT=60                   :: Max wait time in seconds for Docker readiness
set WAIT_INTERVAL=5               :: Interval between checks (seconds)

:: ----- CHECK DOCKER INSTALLED -----
where docker >nul 2>nul
if errorlevel 1 (
    echo ❌ Docker not found in PATH. Please install Docker Desktop or add Docker CLI to PATH.
    pause
    exit /b 1
)

:: ----- WAIT FOR DOCKER TO START -----
echo.
echo Checking if Docker daemon is running...
set /a elapsed=0
:WAIT_DOCKER
docker info >nul 2>nul
if %errorlevel%==0 (
    echo ✅ Docker is running and ready.
) else (
    if %elapsed% GEQ %MAX_WAIT% (
        echo ❌ Docker did not become ready within %MAX_WAIT% seconds.
        pause
        exit /b 1
    )
    echo Waiting for Docker to start... (%elapsed%/%MAX_WAIT%s)
    timeout /t %WAIT_INTERVAL% >nul
    set /a elapsed+=%WAIT_INTERVAL%
    goto WAIT_DOCKER
)

:: ----- FIND ACTIVE NETWORK INTERFACE -----
echo.
echo Detecting active network interface...
for /f "tokens=2 delims=:" %%A in ('netsh interface show interface ^| find "Connected"') do (
    set "INTERFACE=%%A"
)
set INTERFACE=%INTERFACE:~1%
echo Interface found: "%INTERFACE%"
echo.

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
echo.

:: ----- START DOCKER COMPOSE -----
echo Starting Pi-hole container...
docker compose -f "%COMPOSE_FILE%" up -d
if errorlevel 1 (
    echo ❌ Failed to start Docker Compose. Aborting.
    goto END
)

:: ----- SET NEW DNS -----
echo.
echo Setting DNS to use Pi-hole (%PIHOLE_IP%) and backup (%BACKUP_DNS%)...
netsh interface ipv4 set dns name="%INTERFACE%" static %PIHOLE_IP% primary
netsh interface ipv4 add dns name="%INTERFACE%" %BACKUP_DNS% index=2
echo ✅ DNS updated.
echo.

:: ----- MONITOR CONTAINER -----
echo Pi-hole is running. Waiting for container to stop...
:WAITLOOP
timeout /t 10 >nul
docker ps --format "{{.Names}}" | find /i "pihole" >nul
if %errorlevel%==0 goto WAITLOOP

:: ----- RESTORE OLD DNS -----
echo.
echo Pi-hole container stopped. Restoring previous DNS...
if /i "%OLD_DNS%"=="dhcp" (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
) else (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" static %OLD_DNS%
)
echo ✅ DNS restored to %OLD_DNS%.

:END
echo.
echo ------------------------------------------------------
echo All done. Pi-hole stopped, DNS restored.
echo ------------------------------------------------------
pause
