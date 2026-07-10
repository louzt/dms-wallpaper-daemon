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
    // Enable self-heal polling for external renderer liveness (default: true)
    property bool enableSelfHeal: pluginData.enableSelfHeal ?? true
    // Self-heal poll interval in ms (default: 10000)
    property int healthPollMs: pluginData.healthPollMs ?? 10000
    // Cooldown between relaunch attempts per monitor in seconds (default: 60)
    property int relaunchCooldownSeconds: pluginData.relaunchCooldownSeconds ?? 60

    // ===== INTERNAL STATE =====
    // Path to the restore/random script (configurable or auto-detect)
    // If empty, uses 'waypaper-video-random' from PATH
    property string restoreScript: pluginData.restoreScript || "waypaper-video-random"

    // Path to renderer liveness override file written by the script.
    // XDG_STATE_HOME wins when set; fall back to $HOME/.local/state.
    // Runtime home is captured once at component construction so child
    // Process components (which cannot read root properties during
    // their own `workingDirectory` evaluation) get a stable value.
    property string overridePath: {
        var xdgState = Quickshell.env("XDG_STATE_HOME")
        var base = xdgState && xdgState.length > 0
            ? xdgState
            : (root.runtimeHome + "/.local/state")
        return base + "/lzt/wallpaper-override.json"
    }

    // Effective HOME for child Process workingDirectory. Captured once
    // at construction so we never fall back to a hardcoded operator
    // path on systems where HOME is unset (e.g. minimal containers).
    readonly property string runtimeHome: Quickshell.env("HOME") || "/tmp"

    // Validate a monitor name before interpolating it into a child
    // Process command. The script writes these names to the override
    // file, but defense-in-depth is cheap and a stray shell metachar
    // here would let the self-heal loop run arbitrary commands.
    function safeMonitorName(name) {
        if (typeof name !== "string" || name.length === 0) return ""
        if (!/^[A-Za-z0-9_-]+$/.test(name)) {
            console.warn("WallpaperDaemon: refusing unsafe monitor name:", name)
            return ""
        }
        return name
    }

    // Track if we've already restored
    property bool hasRestored: false

    // Track current wallpapers per monitor
    property var currentWallpapers: ({})

    // Cycling timer object
    property var cycleTimer: null

    // Self-heal timer object
    property var selfHealTimer: null

    // Self-heal last-relaunch timestamp per monitor (ms epoch) for cooldown
    property var healAttempts: ({})

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
        if (!proc) {
            console.warn("WallpaperDaemon: cycleProcessComponent createObject returned null")
            return
        }
        proc.running = true
    }

    Component {
        id: cycleProcessComponent

        Process {
            command: [restoreScript, "--random"]
            workingDirectory: root.runtimeHome

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
        if (!proc) {
            console.warn("WallpaperDaemon: restoreProcessComponent createObject returned null")
            return
        }
        proc.running = true
    }

    Component {
        id: restoreProcessComponent

        Process {
            property var wallpaperPaths: ({})

            command: [restoreScript, "--restore-or-random"]
            workingDirectory: root.runtimeHome

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
        if (!cycleTimer) {
            console.warn("WallpaperDaemon: cyclingTimerComponent createObject returned null")
            return
        }
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
            // Qt.binding so the timer picks up slider changes without
            // being destroyed and recreated. Restart-by-destroy
            // would cancel any in-flight onTriggered and reset the
            // repeat counter, causing an extra cycle at the old
            // interval (the slider-thrash the audit flagged).
            interval: Qt.binding(function() { return cycleInterval * 60 * 1000 })
            repeat: true
            onTriggered: cycleNext()
        }
    }

    // ===== SELF-HEAL =====
    function runSelfHeal() {
        if (!enableSelfHeal) return
        var proc = healReadComponent.createObject(root, {})
        if (!proc) {
            console.warn("WallpaperDaemon: healReadComponent createObject returned null")
            return
        }
        proc.running = true
    }

    Component {
        id: healReadComponent

        Process {
            command: ["cat", overridePath]
            workingDirectory: root.runtimeHome

            stdout: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (!text) return
                    try {
                        var payload = JSON.parse(text)
                        processOverridePayload(payload)
                    } catch (e) {
                        console.warn("WallpaperDaemon: self-heal parse error", e)
                    }
                }
            }

            onExited: (exitCode) => {
                if (exitCode !== 0) {
                    console.info("WallpaperDaemon: self-heal override not readable, code=" + exitCode)
                }
                destroy()
            }
        }
    }

    function processOverridePayload(payload) {
        if (!payload || !payload.overrides) return
        var overrides = payload.overrides
        for (var monitor in overrides) {
            var entry = overrides[monitor]
            if (!entry) continue
            var backend = String(entry.backend || "unknown")
            // Quarantine entry from script means the last launch failed (e.g. PulseAudio SIGSEGV).
            // The plugin should trigger the deterministic fallback (swww image) instead of a
            // bare --restore-only retry that would replay the same crash.
            if (backend === "quarantine") {
                var lastAttempt = healAttempts[monitor] || 0
                var elapsedSec = lastAttempt === 0 ? Infinity : (Date.now() - lastAttempt) / 1000
                if (elapsedSec >= relaunchCooldownSeconds) {
                    var reason = String(entry.quarantine_reason || "launch_failed")
                    var lastProject = String(entry.last_project || "")
                    console.warn("WallpaperDaemon: quarantined", monitor, "reason=" + reason, "last_project=" + lastProject, "- fallback_static")
                    healAttempts[monitor] = Date.now()
                    var safeNameFb = root.safeMonitorName(monitor)
                    if (!safeNameFb) continue
                    var fb = fallbackComponent.createObject(root, {
                        monitorName: safeNameFb,
                        reason: reason
                    })
                    if (!fb) {
                        console.warn("WallpaperDaemon: fallbackComponent createObject returned null")
                        continue
                    }
                    fb.running = true
                } else {
                    console.info("WallpaperDaemon: quarantined", monitor, "in cooldown (" + Math.round(elapsedSec) + "s/" + relaunchCooldownSeconds + "s)")
                }
                continue
            }
            // Live entry: check /proc/<pid> for actual liveness
            if (!entry.pid) continue
            var safeNameProbe = root.safeMonitorName(monitor)
            if (!safeNameProbe) continue
            var probe = pidCheckComponent.createObject(root, {
                monitorName: safeNameProbe,
                rendererPid: Number(entry.pid),
                backend: backend
            })
            if (!probe) {
                console.warn("WallpaperDaemon: pidCheckComponent createObject returned null")
                continue
            }
            probe.running = true
        }
    }

    Component {
        id: pidCheckComponent

        Process {
            property string monitorName: ""
            property int rendererPid: 0
            property string backend: ""

            command: ["sh", "-c", "test -d /proc/" + rendererPid]
            workingDirectory: root.runtimeHome

            onExited: (exitCode) => {
                if (exitCode !== 0) {
                    var lastAttempt = healAttempts[monitorName] || 0
                    var elapsedSec = lastAttempt === 0 ? Infinity : (Date.now() - lastAttempt) / 1000
                    if (elapsedSec >= relaunchCooldownSeconds) {
                        console.warn("WallpaperDaemon: dropped", monitorName, "backend=" + backend, "pid=" + rendererPid, "- relaunching")
                        healAttempts[monitorName] = Date.now()
                        var relaunch = relaunchComponent.createObject(root, {
                            monitorName: monitorName,
                            backend: backend
                        })
                        if (!relaunch) {
                            console.warn("WallpaperDaemon: relaunchComponent createObject returned null")
                        } else {
                            relaunch.running = true
                        }
                    } else {
                        console.info("WallpaperDaemon: dropped", monitorName, "in cooldown (" + Math.round(elapsedSec) + "s/" + relaunchCooldownSeconds + "s)")
                    }
                } else {
                    if (healAttempts[monitorName] !== undefined) {
                        delete healAttempts[monitorName]
                    }
                }
                destroy()
            }
        }
    }

    Component {
        id: relaunchComponent

        Process {
            property string monitorName: ""
            property string backend: ""

            command: [restoreScript, "--mode", "smart", "--monitor", monitorName, "--restore-only", "--verbose"]
            workingDirectory: root.runtimeHome

            stdout: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.info("WallpaperDaemon relaunch output:", text)
                        var wallpapers = parseRestoreOutput(text)
                        if (wallpapers[monitorName]) {
                            syncToDmsWallpaper(monitorName, wallpapers[monitorName])
                        }
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.warn("WallpaperDaemon relaunch error:", text)
                    }
                }
            }

            onExited: (exitCode) => {
                console.info("WallpaperDaemon: relaunch_done monitor=" + monitorName + " code=" + exitCode)
                destroy()
            }
        }
    }

    Component {
        id: fallbackComponent

        Process {
            property string monitorName: ""
            property string reason: ""

            command: {
                var base = [restoreScript, "--mode", "smart", "--monitor", monitorName, "--restore-only", "--verbose"]
                if (fallbackWallpaper && fallbackWallpaper.length > 0) {
                    base.splice(5, 0, "--fallback-wallpaper", fallbackWallpaper)
                }
                return base
            }
            workingDirectory: root.runtimeHome

            stdout: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.info("WallpaperDaemon fallback output:", text)
                        var wallpapers = parseRestoreOutput(text)
                        if (wallpapers[monitorName]) {
                            syncToDmsWallpaper(monitorName, wallpapers[monitorName])
                        }
                    }
                }
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    var text = String(text || "").trim()
                    if (text) {
                        console.warn("WallpaperDaemon fallback error:", text)
                    }
                }
            }

            onExited: (exitCode) => {
                console.info("WallpaperDaemon: fallback_done monitor=" + monitorName + " code=" + exitCode + " reason=" + reason)
                destroy()
            }
        }
    }

    function startSelfHealTimer() {
        if (selfHealTimer) {
            selfHealTimer.running = false
            selfHealTimer.destroy()
        }
        if (!enableSelfHeal) return
        selfHealTimer = selfHealTimerComponent.createObject(root, {})
        selfHealTimer.running = true
        console.info("WallpaperDaemon: Self-heal started, poll=" + healthPollMs + "ms cooldown=" + relaunchCooldownSeconds + "s")
    }

    function stopSelfHealTimer() {
        if (selfHealTimer) {
            selfHealTimer.running = false
            selfHealTimer.destroy()
            selfHealTimer = null
            console.info("WallpaperDaemon: Self-heal stopped")
        }
    }

    Component {
        id: selfHealTimerComponent

        Timer {
            // Qt.binding so the timer picks up slider changes without
            // being destroyed and recreated. Restart-by-destroy would
            // cancel any in-flight onTriggered and reset the repeat
            // counter, causing an extra self-heal poll at the old
            // interval (the slider-thrash the audit flagged).
            interval: Qt.binding(function() { return healthPollMs })
            repeat: true
            onTriggered: runSelfHeal()
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
        // No timer restart: the Qt.binding on the Timer picks up
        // cycleInterval changes directly. Restarting the timer would
        // thrash on every slider step (the audit finding).
    }

    onEnableSelfHealChanged: {
        if (enableSelfHeal) {
            startSelfHealTimer()
        } else {
            stopSelfHealTimer()
        }
    }

    onHealthPollMsChanged: {
        // No timer restart: the Qt.binding on the Timer picks up
        // healthPollMs changes directly. Restarting the timer would
        // thrash on every slider step (the audit finding).
    }

    onRelaunchCooldownSecondsChanged: {
        // No timer restart needed; next probe reads the new value
    }

    // ===== LIFECYCLE =====
    Component.onCompleted: {
        console.info("WallpaperDaemon: Plugin started")
        console.info("WallpaperDaemon: autoRestore=", autoRestore, "syncToDms=", syncToDms, "enableCycling=", enableCycling, "cycleInterval=", cycleInterval, "fallbackWallpaper=", fallbackWallpaper)
        console.info("WallpaperDaemon: enableSelfHeal=", enableSelfHeal, "healthPollMs=", healthPollMs, "relaunchCooldownSeconds=", relaunchCooldownSeconds, "overridePath=", overridePath)

        if (autoRestore) {
            runRestore()
        }

        if (enableCycling) {
            startCyclingTimer()
        }

        if (enableSelfHeal) {
            startSelfHealTimer()
        }
    }

    Component.onDestruction: {
        console.info("WallpaperDaemon: Plugin stopped")
        stopCyclingTimer()
        stopSelfHealTimer()
    }
}
