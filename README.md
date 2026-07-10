# DMS Wallpaper Daemon

A DankMaterialShell plugin that restores Waypaper wallpapers at startup and syncs with DMS session. Includes `waypaper-video-random` for intelligent restore with wallpaper engine compatibility.

## Features

- **Auto-restore wallpapers** on DMS startup
- **Sync to DMS** via IPC so other components know the active wallpaper
- **Optional wallpaper cycling** with configurable interval
- **Fallback wallpaper** when Waypaper fails
- **Smart restore** — verifies mpvpaper is showing the correct wallpaper before skipping
- **Self-heal polling** — detects dead external renderers and relaunches them automatically
- **Works with any Waypaper backend** (linux-wallpaperengine, mpvpaper, swww, etc.)

## Replaces waypaperd.service

This plugin **replaces** the legacy `waypaperd.service` daemon. If you have it installed, disable it:

```bash
systemctl --user disable --now waypaperd.service
```

The plugin provides the same functionality (restore on boot + cycling) but integrated into DMS with a settings UI.

## Requirements

- [DankMaterialShell (DMS)](https://github.com/SomeSomeone/DankMaterialShell)
- [Waypaper](https://github.com/anufrievroman/waypaper)

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

# Enable and start
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
| Enable self-heal | `true` | Poll renderer liveness and relaunch dropped monitors |
| Health poll interval | `10000 ms` | How often to scan `/proc/<pid>` (1000–60000) |
| Relaunch cooldown | `60 s` | Minimum seconds between relaunches per monitor (10–600) |

## How it works

1. On boot, `waypaper-restore.service` runs before DMS
2. It uses `waypaper-video-random` (bundled) to restore wallpapers with correct Wayland environment
3. The script verifies each monitor — if mpvpaper is running but showing wrong wallpaper, it restores the correct one
4. When DMS starts, the plugin syncs wallpaper state via IPC
5. If cycling is enabled, the plugin triggers `--random` at the configured interval

## Bundled: waypaper-video-random

This plugin includes `waypaper-video-random`, a script that:

- Restores the last wallpaper per monitor from persistent state
- Falls back to random wallpaper if no restore state exists
- **Verifies mpvpaper is showing the correct wallpaper** before skipping (fixes session resume issues)
- Filters Wallpaper Engine projects by compatibility tags
- Supports per-output playlists

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

3. Test manually:
   ```bash
   XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-1 waypaper --restore
   ```

### linux-wallpaperengine crashes immediately

The restore service **must** have these environment variables:
- `XDG_SESSION_TYPE=wayland`
- `WAYLAND_DISPLAY=wayland-1`

These are set in the bundled service file.

### linux-wallpaperengine SIGSEGV in PulseAudioPlaybackRecorder

If `linux-wallpaperengine` crashes with stack frames inside
`PulseAudioPlaybackRecorder::update` / `pa_server_info_cb` even when
`linux_wallpaperengine_silent = True`, the audio path is still loaded.
Disable audio processing explicitly in `~/.config/waypaper/config.ini`:

```ini
linux_wallpaperengine_silent = True
linux_wallpaperengine_no_audio_processing = True
linux_wallpaperengine_disable_particles = True
```

`--silent` only mutes output volume; it does not skip PulseAudio
initialization. `--no-audio-processing` actually bypasses the recorder
and is required to avoid the SIGSEGV.

## Self-heal (v1.1.0+)

The plugin polls the renderer liveness file written by
`waypaper-video-random` (at
`$XDG_STATE_HOME/lzt/wallpaper-override.json`, default
`~/.local/state/lzt/wallpaper-override.json`). For each monitor whose
recorded PID is missing (`/proc/<pid>` gone) and outside the cooldown
window, the plugin relaunches the renderer via:

```bash
waypaper-video-random --mode smart --monitor <name> --restore-only --verbose
```

Then it syncs the recovered wallpaper to DMS via
`dms ipc wallpaper setFor <output> <path>`.

### Settings (DMS Settings → Plugins → Wallpaper Daemon)

| Setting | Default | Description |
|---------|---------|-------------|
| Enable self-heal | `true` | Poll renderer liveness and relaunch dropped monitors |
| Health poll interval | `10000 ms` | How often to scan `/proc/<pid>` (1000–60000) |
| Relaunch cooldown | `60 s` | Minimum seconds between relaunches per monitor (10–600) |

### Override file format

```json
{
  "version": 1,
  "updated_at": "2026-07-10T15:42:01",
  "overrides": {
    "HDMI-A-1": {"backend": "linux-wallpaperengine", "pid": 12345, "since": 1752149521}
  }
}
```

The script writes this file atomically (`tmp` + `replace`) every time a
monitor receives a successful `apply_wallpaper()` result. The plugin
reads it on each poll cycle and uses `/proc/<pid>` directory existence
as the liveness signal.

### Cycling not working

1. Enable cycling in plugin settings
2. Make sure playlists are configured in `~/.config/waypaper/video-smart-rules.json`

### DMS doesn't show wallpaper

Make sure **Sync to DMS** is enabled in plugin settings.

## File Structure

```
wallpaperDaemon/
├── plugin.json                    # Plugin manifest
├── WallpaperDaemon.qml           # Main daemon component
├── WallpaperDaemonSettings.qml   # Settings UI
├── waypaper-video-random         # Restore/random script (bundled)
├── systemd/
│   └── waypaper-restore.service  # Boot-time restore service
└── README.md
```

## License

MIT

## Author

[lou](https://github.com/louzt)
