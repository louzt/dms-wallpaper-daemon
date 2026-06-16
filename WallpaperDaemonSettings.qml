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
