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

### Option 1: Clone to plugins directory

```bash
git clone https://github.com/louzt/dms-wallpaper-daemon.git ~/.config/DankMaterialShell/plugins/wallpaperDaemon
```

### Option 2: Manual

Copy `plugin.json`, `WallpaperDaemon.qml`, and `WallpaperDaemonSettings.qml` to:

```
~/.config/DankMaterialShell/plugins/wallpaperDaemon/
```

## Enable the plugin

```bash
dms ipc plugins enable wallpaperDaemon
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

1. On DMS startup, the plugin runs the restore script
2. The script applies wallpapers via Waypaper
3. The plugin syncs active wallpapers to DMS via `dms ipc wallpaper setFor`
4. If cycling is enabled, a timer triggers `--random` at the configured interval

## Troubleshooting

### Wallpapers show as grey at startup

1. Make sure Waypaper is installed and working: `waypaper --restore`
2. Check the restore script path in plugin settings
3. Check DMS logs: `journalctl --user -u dms.service`

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
