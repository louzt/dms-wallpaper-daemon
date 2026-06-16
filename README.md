# DMS Wallpaper Daemon

A DankMaterialShell plugin that restores Waypaper wallpapers at startup and syncs with DMS session.

## Features

- **Auto-restore wallpapers** on DMS startup
- **Sync to DMS** via IPC so other components know the active wallpaper
- **Optional wallpaper cycling** with configurable interval
- **Fallback wallpaper** when Waypaper fails
- **Works with any Waypaper backend** (linux-wallpaperengine, mpvpaper, swww, etc.)

## Requirements

- [DankMaterialShell (DMS)](https://github.com/SomeSomeone/DankMaterialShell)
- [Waypaper](https://github.com/anufrievroman/waypaper)
- `waypaper-video-random` script (optional, for advanced restore/random features)

## Installation

### 1. Install the plugin

```bash
git clone https://github.com/louzt/dms-wallpaper-daemon.git ~/.config/DankMaterialShell/plugins/wallpaperDaemon
dms ipc plugins enable wallpaperDaemon
```

### 2. Create the restore service (recommended)

For wallpaper restoration at boot, create `~/.config/systemd/user/waypaper-restore.service`:

```ini
[Unit]
Description=Restore Waypaper wallpapers
PartOf=niri.service
After=niri.service dms.service
Requisite=niri.service

[Service]
Type=oneshot
Environment=XDG_SESSION_TYPE=wayland
Environment=WAYLAND_DISPLAY=wayland-1
Environment=NIRI_SOCKET=/run/user/1001/niri.wayland-1.sock
ExecStart=/path/to/waypaper-video-random --restore-or-random --restore-only
Restart=on-failure
RestartSec=5

[Install]
WantedBy=niri.service
```

**Important:** `linux-wallpaperengine` requires Wayland session environment variables. Without them, it will crash with:
```
Cannot read environment variable XDG_SESSION_TYPE, window server detection failed
```

Adjust `NIRI_SOCKET` path for your system (check `ls /run/user/1001/niri*.sock`).

Then enable:
```bash
systemctl --user daemon-reload
systemctl --user enable --now waypaper-restore.service
```

## Configuration

Access settings via **DMS Settings → Plugins → Wallpaper Daemon**:

| Setting | Default | Description |
|---------|---------|-------------|
| Auto-restore on startup | `true` | Automatically restore wallpapers when DMS starts |
| Sync to DMS | `true` | Synchronize wallpaper state to DMS via IPC |
| Enable cycling | `false` | Periodically change wallpapers |
| Cycle interval | `30 min` | How often to cycle wallpapers |
| Fallback wallpaper | *(empty)* | Path to image shown when Waypaper fails |
| Restore script | *(empty)* | Path to `waypaper-video-random` script |

## Waypaper Video Random

This plugin is designed to work with [`waypaper-video-random`](https://github.com/louzt/waypaper-video-random), a script that:

- Restores the last wallpaper per monitor
- Falls back to random wallpaper if no restore state exists
- Filters Wallpaper Engine projects by compatibility tags
- Supports per-output playlists

## How it works

1. On boot, `waypaper-restore.service` runs the restore script
2. The script applies wallpapers via Waypaper (with correct env vars)
3. The plugin syncs active wallpapers to DMS via `dms ipc wallpaper setFor`
4. If cycling is enabled, a timer triggers `--random` at the configured interval

## Troubleshooting

### Wallpapers show as grey at startup

1. Make sure the restore service is running:
   ```bash
   systemctl --user status waypaper-restore.service
   ```

2. Check the restore logs:
   ```bash
   journalctl --user -u waypaper-restore.service
   ```

3. Verify environment variables are set in the service file:
   ```bash
   grep -i environment ~/.config/systemd/user/waypaper-restore.service
   ```

4. Test manually:
   ```bash
   waypaper --restore
   ```

### linux-wallpaperengine crashes immediately

This usually means missing Wayland environment variables. The restore service **must** have:
- `XDG_SESSION_TYPE=wayland`
- `WAYLAND_DISPLAY=wayland-1`
- `NIRI_SOCKET=/run/user/1001/niri.wayland-1.sock` (adjust for your user)

### Cycling not working

1. Enable cycling in plugin settings
2. Make sure `waypaper-video-random` supports `--random` flag
3. Check that playlists are configured in `~/.config/waypaper/video-smart-rules.json`

### DMS doesn't show wallpaper

Make sure **Sync to DMS** is enabled in plugin settings.

## License

MIT

## Author

[lou](https://github.com/louzt)
