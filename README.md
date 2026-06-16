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

### 2. Install the restore service (recommended)

This restores wallpapers at boot, before DMS loads.

```bash
# Copy the service file
cp ~/.config/DankMaterialShell/plugins/wallpaperDaemon/systemd/waypaper-restore.service \
   ~/.config/systemd/user/

# Edit the service to match your setup:
# - Set the correct NIRI_SOCKET path (check: ls /run/user/$(id -u)/niri*.sock)
# - Set the correct path to waypaper-video-random

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable --now waypaper-restore.service
```

### 3. Verify

```bash
# Check service status
systemctl --user status waypaper-restore.service

# See restored wallpapers
ps aux | grep -E 'mpvpaper|linux-wallpaperengine' | grep -v grep
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

1. On boot, `waypaper-restore.service` runs before DMS
2. It restores wallpapers via waypaper with correct Wayland environment
3. When DMS starts, the plugin syncs wallpaper state via IPC
4. If cycling is enabled, the plugin triggers `--random` at the configured interval

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

3. Find your NIRI socket:
   ```bash
   ls /run/user/$(id -u)/niri*.sock
   ```

4. Update the `NIRI_SOCKET` in the service file, then:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart waypaper-restore.service
   ```

5. Test manually:
   ```bash
   XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-1 waypaper --restore
   ```

### linux-wallpaperengine crashes immediately

This usually means missing Wayland environment variables. The restore service **must** have:
- `XDG_SESSION_TYPE=wayland`
- `WAYLAND_DISPLAY=wayland-1`
- `NIRI_SOCKET` pointing to your niri socket

### Cycling not working

1. Enable cycling in plugin settings
2. Make sure `waypaper-video-random` supports `--random` flag
3. Check that playlists are configured in `~/.config/waypaper/video-smart-rules.json`

### DMS doesn't show wallpaper

Make sure **Sync to DMS** is enabled in plugin settings.

## File Structure

```
wallpaperDaemon/
├── plugin.json                    # Plugin manifest
├── WallpaperDaemon.qml           # Main daemon component
├── WallpaperDaemonSettings.qml   # Settings UI
├── systemd/
│   └── waypaper-restore.service # Boot-time restore service (install manually)
└── README.md
```

## License

MIT

## Author

[lou](https://github.com/louzt)
