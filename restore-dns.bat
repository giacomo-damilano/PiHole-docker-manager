@echo off
:: ======================================================
::  Pi-hole DNS Restoration Script (Failsafe)
::  Run as Administrator if DNS needs to be reset manually
:: ======================================================

setlocal enabledelayedexpansion

:: ----- FIND ACTIVE NETWORK INTERFACE -----
echo Detecting active network interface...
for /f "tokens=2 delims=:" %%A in ('netsh interface show interface ^| find "Connected"') do (
    set "INTERFACE=%%A"
)
set INTERFACE=%INTERFACE:~1%
echo Using interface: "%INTERFACE%"
echo.

:: ----- CHECK IF BACKUP EXISTS -----
if not exist "%TEMP%\old_dns_only.txt" (
    echo ⚠️  No previous DNS backup found in %TEMP%\old_dns_only.txt
    echo Cannot restore automatically. You may need to reset to DHCP manually.
    echo.
    echo To reset manually, run:
    echo   netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
    pause
    exit /b 1
)

:: ----- READ OLD DNS -----
set OLD_DNS=
for /f "tokens=1" %%A in (%TEMP%\old_dns_only.txt) do (
    if not defined OLD_DNS (
        set OLD_DNS=%%A
    )
)

if not defined OLD_DNS (
    echo ⚠️  Backup file is empty or invalid.
    echo Restoring to DHCP mode...
    netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
    goto END
)

:: ----- RESTORE OLD DNS -----
echo Restoring DNS to previous configuration...
if /i "%OLD_DNS%"=="dhcp" (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" source=dhcp
    echo ✅ DNS restored to DHCP mode.
) else (
    netsh interface ipv4 set dnsservers name="%INTERFACE%" static %OLD_DNS%
    echo ✅ DNS restored to static %OLD_DNS%.
)

:END
echo.
echo ------------------------------------------------------
echo DNS configuration has been restored.
echo ------------------------------------------------------
pause
