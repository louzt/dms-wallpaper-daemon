import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wallpaperDaemon"

    StyledText {
        text: "Waypaper Daemon"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: "Restores Waypaper wallpapers at startup and syncs with DMS session."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextSecondary
    }

    ToggleSetting {
        settingKey: "autoRestore"
        label: I18n.tr("Auto-restore on startup")
        description: I18n.tr("Automatically restore wallpapers when DMS starts")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "syncToDms"
        label: I18n.tr("Sync to DMS")
        description: I18n.tr("Synchronize wallpaper state to DMS session data via IPC")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "enableCycling"
        label: I18n.tr("Enable wallpaper cycling")
        description: I18n.tr("Periodically change wallpapers using the configured interval")
        defaultValue: false
    }

    SliderSetting {
        settingKey: "cycleInterval"
        label: I18n.tr("Cycle interval")
        description: I18n.tr("How often to cycle wallpapers")
        minimum: 5
        maximum: 120
        defaultValue: 30
        unit: I18n.tr("min")
    }

    StyledText {
        text: I18n.tr("Self-heal")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "enableSelfHeal"
        label: I18n.tr("Enable self-heal")
        description: I18n.tr("Poll the renderer liveness override file and relaunch dropped external wallpaper renderers (e.g. linux-wallpaperengine after PulseAudio crash)")
        defaultValue: true
    }

    SliderSetting {
        settingKey: "healthPollMs"
        label: I18n.tr("Health poll interval")
        description: I18n.tr("How often to check renderer PIDs (1000-60000 ms)")
        minimum: 1000
        maximum: 60000
        defaultValue: 10000
        unit: I18n.tr("ms")
    }

    SliderSetting {
        settingKey: "relaunchCooldownSeconds"
        label: I18n.tr("Relaunch cooldown")
        description: I18n.tr("Minimum seconds between relaunch attempts per monitor")
        minimum: 10
        maximum: 600
        defaultValue: 60
        unit: I18n.tr("s")
    }

    StringSetting {
        settingKey: "fallbackWallpaper"
        label: I18n.tr("Fallback wallpaper path")
        description: I18n.tr("Absolute path to an image to show when Waypaper fails. Leave empty to use the last active wallpaper.")
        placeholder: "/home/user/Pictures/wallpaper.jpg"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "restoreScript"
        label: I18n.tr("Restore script path")
        description: I18n.tr("Path to the waypaper restore/random script. Defaults to waypaper-video-random if empty.")
        placeholder: "waypaper-video-random"
        defaultValue: ""
    }

    StyledText {
        text: "Restore Script: " + (root.pluginData?.restoreScript || "waypaper-video-random (auto-detected)")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextSecondary
    }

    StyledText {
        text: "Fallback: " + (root.pluginData?.fallbackWallpaper || "last active wallpaper (auto)")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextSecondary
    }
}
