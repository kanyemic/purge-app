import AppIntents

/// Three actions, on purpose: the jobs people reach for from Spotlight or Siri
/// are checking for junk, cleaning it, and removing an app. Opening a tab, a
/// separate "how much" answer and a size for Shortcuts are left out: each adds
/// a choice without saving a step. Every phrase names the app, since App
/// Shortcuts only match that way; Spotlight also matches the search keywords
/// on each action, which need no app name.
nonisolated struct PurgeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanForJunkIntent(),
            phrases: [
                "用 \(.applicationName) 扫描垃圾",
                "用 \(.applicationName) 查找垃圾",
                "用 \(.applicationName) 释放空间",
                "用 \(.applicationName) 清理我的 Mac",
                "\(.applicationName) 能释放多少空间",
                "\(.applicationName) 能清出多少空间",
                "用 \(.applicationName) 检查存储空间",
                "用 \(.applicationName) 扫描我的 Mac",
                "\(.applicationName) 扫描",
            ],
            shortTitle: "扫描垃圾",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CleanSafeJunkIntent(),
            phrases: [
                "用 \(.applicationName) 清理垃圾",
                "用 \(.applicationName) 清理安全垃圾",
                "用 \(.applicationName) 清除垃圾",
                "用 \(.applicationName) 清除缓存",
                "用 \(.applicationName) 删除垃圾",
                "\(.applicationName) 清理",
            ],
            shortTitle: "清理安全垃圾",
            systemImageName: "trash.fill"
        )
        AppShortcut(
            intent: UninstallAppIntent(),
            phrases: [
                // Phrases with the app expand once per installed app, and the
                // system caps the total, so only two of them name the app.
                "用 \(.applicationName) 卸载 \(\.$app)",
                "用 \(.applicationName) 移除 \(\.$app)",
                "用 \(.applicationName) 卸载应用",
                "用 \(.applicationName) 移除应用",
                "用 \(.applicationName) 删除应用",
                "用 \(.applicationName) 清掉应用",
            ],
            shortTitle: "卸载应用",
            systemImageName: "trash"
        )
    }
}

extension PurgeAppShortcuts {
    /// Re-reads the installed apps behind "Uninstall <app> with Purge". Here so
    /// callers need not import AppIntents.
    static func refreshAppList() {
        updateAppShortcutParameters()
    }
}
