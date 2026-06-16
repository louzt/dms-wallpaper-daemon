import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ===== SETTINGS =====
    // Auto-restore on startup (default: true)
    property bool autoRestore: pluginData.autoRestore ?? true
    // Sync wallpaper state to DMS via IPC (default: true)
    property bool syncToDms: pluginData.syncToDms ?? true
    // Enable cycling (default: false)
    property bool enableCycling: pluginData.enableCycling ?? false
    // Cycle interval in minutes (default: 30)
    property int cycleInterval: (pluginData.cycleInterval ?? 30)
    // Fallback wallpaper path (default: empty = use last active)
    property string fallbackWallpaper: (pluginData.fallbackWallpaper || "")

    // ===== INTERNAL STATE =====
    // Path to the restore/random script (configurable or auto-detect)
    // If empty, uses 'waypaper-video-random' from PATH
    property string restoreScript: pluginData.restoreScript || "waypaper-video-random"

    // Track if we've already restored
    property bool hasRestored: false

    // Track current wallpapers per monitor
    property var currentWallpapers: ({})

    // Cycling timer object
    property var cycleTimer: null

    // ===== PARSE OUTPUT =====
    function parseRestoreOutput(output) {
        var lines = output.split("\n")
        var results = {}
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            // Match lines like: event=apply monitor=HDMI-A-1 project=we:xxx ...
            // or event=resume monitor=HDMI-A-1 project=we:xxx ...
            if (line.startsWith("event=apply ") || line.startsWith("event=resume ") || line.startsWith("event=done ")) {
                var monitorMatch = line.match(/monitor=([^\s]+)/)
                var pathMatch = line.match(/--wallpaper\s+([^\s]+)/)
                if (monitorMatch && pathMatch) {
                    results[monitorMatch[1]] = pathMatch[1]
                }
            }
        }
        return results
    }

    // ===== SYNC TO DMS =====
    function syncToDmsWallpaper(outputName, wallpaperPath) {
        if (!syncToDms) return
        try {
            Process.runCommand("wallpaperDaemon.sync", ["dms", "ipc", "wallpaper", "setFor", outputName, wallpaperPath], function(output, exitCode) {
                if (exitCode === 0) {
                    console.info("WallpaperDaemon: DMS synced", outputName)
                } else {
                    console.warn("WallpaperDaemon: DMS sync failed for", outputName, output)
                }
            }, 0, 5000)
        } catch(e) {
            console.warn("WallpaperDaemon: DMS sync error", e)
        }
    }

    function syncAllToDms(wallpapers) {
        for (var monitor in wallpapers) {
            syncToDmsWallpaper(monitor, wallpapers[monitor])
        }
    }

    // ===== CYCLE NEXT =====
    function cycleNext() {
        console.info("WallpaperDaemon: Cycling to next wallpaper...")
        var proc = cycleProcessComponent.createObject(root, {})
        proc.running = true
    }

    Component {
        id: cycleProcessComponent

        Process {
            command: [restoreScript, "--random"]
            workingDirectory: "/home/lou"

            stdout: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.info("WallpaperDaemon cycle output:", text)
                        var wallpapers = parseRestoreOutput(text)
                        if (Object.keys(wallpapers).length > 0) {
                            syncAllToDms(wallpapers)
                        }
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.warn("WallpaperDaemon cycle error:", text)
                    }
                }
            }

            onExited: (exitCode) => {
                console.info("WallpaperDaemon: Cycle completed with exit code", exitCode)
                destroy()
            }
        }
    }

    // ===== RESTORE =====
    function runRestore() {
        if (hasRestored) {
            console.info("WallpaperDaemon: Already restored, skipping")
            return
        }

        console.info("WallpaperDaemon: Starting wallpaper restore...")

        var proc = restoreProcessComponent.createObject(root, {})
        proc.running = true
    }

    Component {
        id: restoreProcessComponent

        Process {
            property var wallpaperPaths: ({})

            command: [restoreScript, "--restore-or-random"]
            workingDirectory: "/home/lou"

            stdout: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.info("WallpaperDaemon restore output:", text)
                        wallpaperPaths = parseRestoreOutput(text)
                        if (Object.keys(wallpaperPaths).length > 0) {
                            syncAllToDms(wallpaperPaths)

                            // Set fallback to first wallpaper if not configured
                            if (!fallbackWallpaper) {
                                var firstMonitor = Object.keys(wallpaperPaths)[0]
                                var fallbackPath = wallpaperPaths[firstMonitor]
                                if (fallbackPath) {
                                    // Store in plugin settings for next boot
                                    pluginData.fallbackWallpaper = fallbackPath
                                }
                            }
                        }
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.warn("WallpaperDaemon restore error:", text)
                    }
                }
            }

            onExited: (exitCode) => {
                hasRestored = true
                console.info("WallpaperDaemon: Restore completed with exit code", exitCode)
                destroy()
            }
        }
    }

    // ===== CYCLING TIMER =====
    function startCyclingTimer() {
        if (cycleTimer) {
            cycleTimer.running = false
            cycleTimer.destroy()
        }
        if (!enableCycling) return

        cycleTimer = cyclingTimerComponent.createObject(root, {})
        cycleTimer.running = true
        console.info("WallpaperDaemon: Cycling started, interval =", cycleInterval, "minutes")
    }

    function stopCyclingTimer() {
        if (cycleTimer) {
            cycleTimer.running = false
            cycleTimer.destroy()
            cycleTimer = null
            console.info("WallpaperDaemon: Cycling stopped")
        }
    }

    Component {
        id: cyclingTimerComponent

        Timer {
            interval: cycleInterval * 60 * 1000  // minutes to ms
            repeat: true
            onTriggered: cycleNext()
        }
    }

    // ===== WATCH FOR SETTINGS CHANGES =====
    onAutoRestoreChanged: {
        if (autoRestore && !hasRestored) {
            runRestore()
        }
    }

    onEnableCyclingChanged: {
        if (enableCycling) {
            startCyclingTimer()
        } else {
            stopCyclingTimer()
        }
    }

    onCycleIntervalChanged: {
        if (enableCycling) {
            startCyclingTimer()  // Restart with new interval
        }
    }

    // ===== LIFECYCLE =====
    Component.onCompleted: {
        console.info("WallpaperDaemon: Plugin started")
        console.info("WallpaperDaemon: autoRestore=", autoRestore, "syncToDms=", syncToDms, "enableCycling=", enableCycling, "cycleInterval=", cycleInterval, "fallbackWallpaper=", fallbackWallpaper)

        if (autoRestore) {
            runRestore()
        }

        if (enableCycling) {
            startCyclingTimer()
        }
    }

    Component.onDestruction: {
        console.info("WallpaperDaemon: Plugin stopped")
        stopCyclingTimer()
    }
}
