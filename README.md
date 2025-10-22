# Pi-hole Docker Manager

This repository contains cross-platform helper scripts that start a Pi-hole container with Docker Compose while temporarily switching your host's DNS configuration to point at Pi-hole. When the container stops, the scripts restore the previous DNS settings to avoid connectivity issues.

The project now ships automation for:

- **Windows** (original `run-pihole.bat` and `restore-dns.bat`)
- **Linux with NetworkManager** (`run-pihole-linux.sh`, `restore-dns-linux.sh`)
- **Debian with systemd-resolved** (`run-pihole-debian.sh`, `restore-dns-debian.sh`)
- **macOS** (`run-pihole-macos.sh`, `restore-dns-macos.sh`)

> **Tip:** Every script accepts the same optional environment variables before execution:
>
> - `PIHOLE_IP` – The IP address that clients should use for Pi-hole (default `192.168.1.10`).
> - `BACKUP_DNS` – Space-separated list of fallback resolvers (default `8.8.8.8`).
> - `COMPOSE_FILE` – Path to the Docker Compose file (default `docker-compose.yml`).
> - `MAX_WAIT` / `WAIT_INTERVAL` – How long to wait for Docker to become ready.

## Prerequisites

- Docker Engine and Docker Compose plugin installed and running.
- Administrative/root privileges (all scripts modify system DNS configuration).
- For Linux NetworkManager hosts: `nmcli` must be available.
- For Debian hosts: `systemd-resolved` must be running and `resolvectl` available.
- For macOS: Docker Desktop for Mac and the `networksetup` utility (included with macOS).

Ensure the scripts are executable before running them (Linux, Debian, macOS):

```bash
chmod +x run-pihole-linux.sh restore-dns-linux.sh \
        run-pihole-debian.sh restore-dns-debian.sh \
        run-pihole-macos.sh restore-dns-macos.sh
```

## Windows workflow

1. Edit `run-pihole.bat` to set `PIHOLE_IP`, `BACKUP_DNS`, and `COMPOSE_FILE` for your environment.
2. Right-click **Run as administrator** to start Pi-hole. The script backs up your current DNS, launches Docker Compose, and applies the Pi-hole DNS servers.
3. The script monitors the Pi-hole container. When it exits (or you close the window), DNS settings are restored.
4. If you ever need to revert DNS manually, run `restore-dns.bat` as administrator. It reads the backup created in `%TEMP%` by the runner.

## Linux workflow (NetworkManager)

Scripts: `run-pihole-linux.sh`, `restore-dns-linux.sh`

1. Export any overrides (optional), e.g. `export PIHOLE_IP=192.168.1.20`.
2. Execute with sudo: `sudo ./run-pihole-linux.sh`.
3. The script waits for Docker, detects the active NetworkManager connection, stores the DNS configuration under `~/.local/state/pihole-docker-manager/old_dns_linux.env`, starts the Pi-hole stack, and replaces DNS servers with Pi-hole and the configured backup.
4. When the Pi-hole container stops, DNS is restored automatically. Interrupting the script (`Ctrl+C`) also triggers restoration via shell traps.
5. If you need to restore manually, run `sudo ./restore-dns-linux.sh`.

## Debian workflow (systemd-resolved)

Scripts: `run-pihole-debian.sh`, `restore-dns-debian.sh`

1. Ensure `systemd-resolved` manages `/etc/resolv.conf` and `resolvectl` is present.
2. (Optional) Override environment variables, e.g. `export BACKUP_DNS="1.1.1.1 1.0.0.1"`.
3. Run `sudo ./run-pihole-debian.sh`. The script saves DNS and search domain information for the default interface in `~/.local/state/pihole-docker-manager/old_dns_debian.env`, launches Docker Compose, and sets Pi-hole plus backup DNS servers through `resolvectl`.
4. DNS state is restored automatically when the container exits or the script terminates.
5. To revert manually, execute `sudo ./restore-dns-debian.sh`.

## macOS workflow

Scripts: `run-pihole-macos.sh`, `restore-dns-macos.sh`

1. Optionally export overrides such as `PIHOLE_IP`.
2. Run `sudo ./run-pihole-macos.sh`. The script determines your primary service using `route get default` + `networksetup`, stores existing DNS/search domains in `~/Library/Application Support/PiHoleDockerManager/old_dns_macos.env`, launches Docker Compose, and points DNS to Pi-hole followed by your backup resolvers.
3. When Pi-hole stops, DNS and search domains are restored. Interruptions also trigger restoration.
4. To revert manually at any time, run `sudo ./restore-dns-macos.sh`.

## Scheduling the scripts at startup

The scripts can be scheduled to launch Pi-hole automatically at boot/login. Adjust paths as needed.

### Windows (Task Scheduler)

1. Open **Task Scheduler** → **Create Task**.
2. Run with highest privileges and configure for **Windows 10/11**.
3. Trigger: **At startup** or **At log on** of any user.
4. Action: `Start a program` with `Program/script` set to `C:\Windows\System32\cmd.exe` and **Add arguments**: `/c "cd /d C:\path\to\PiHole-docker-manager && run-pihole.bat"`.
5. Configure **Stop task if it runs longer than** if desired, and enable **Run task as soon as possible after a scheduled start is missed**.

### Linux (systemd user service)

Create `~/.config/systemd/user/pihole-docker.service`:

```ini
[Unit]
Description=Pi-hole Docker Manager (NetworkManager)
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
ExecStart=/usr/bin/sudo /path/to/PiHole-docker-manager/run-pihole-linux.sh
TimeoutStopSec=30
Restart=on-failure

[Install]
WantedBy=default.target
```

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now pihole-docker.service
```

> If you prefer a system-wide service, move the unit to `/etc/systemd/system/` and drop `--user`. Remember to allow the service user to run the script with passwordless sudo.

### Debian (systemd service with resolvectl)

Create `/etc/systemd/system/pihole-docker.service`:

```ini
[Unit]
Description=Pi-hole Docker Manager (Debian)
After=network-online.target docker.service systemd-resolved.service
Wants=network-online.target docker.service systemd-resolved.service

[Service]
Type=simple
ExecStart=/usr/local/bin/run-pihole-debian.sh
Environment=PIHOLE_IP=192.168.1.10
Environment=BACKUP_DNS=8.8.8.8 1.1.1.1
# Ensure the script is executable and owned by root
WorkingDirectory=/path/to/PiHole-docker-manager
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Reload and enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pihole-docker.service
```

> The service runs as root by default. If you run it under another account, configure `/etc/sudoers.d/` to allow `resolvectl` and `docker` without prompting for a password.

### macOS (launchd agent)

Create `~/Library/LaunchAgents/com.example.pihole-docker.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.example.pihole-docker</string>
    <key>ProgramArguments</key>
    <array>
      <string>/usr/bin/sudo</string>
      <string>/path/to/PiHole-docker-manager/run-pihole-macos.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/pihole-docker.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pihole-docker.err</string>
  </dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.example.pihole-docker.plist
```

`launchd` agents run as the logged-in user. Ensure that user can run `sudo /path/to/run-pihole-macos.sh` without a password by configuring `/etc/sudoers` appropriately, or replace `sudo` with a wrapper script that uses `launchctl asuser` and `do shell script` with administrator privileges.

## Troubleshooting

- If Docker is not ready when a script starts, it retries until the configured `MAX_WAIT` expires.
- Use the companion `restore-dns-*.sh` scripts if a crash or forced shutdown leaves DNS pointing at Pi-hole.
- The backup files live in the directories listed above; deleting them prevents automatic restoration, so keep them intact until DNS is restored.

## License

This project is distributed under the MIT license.
