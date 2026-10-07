import AppIntents

struct UninstallAppIntent: AppIntent {
    static let title: LocalizedStringResource = "卸载应用"
    static let description = IntentDescription(
        "在 Purge 中打开这个应用的卸载确认，列出应用本身以及它遗留的全部内容。在你于 Purge 中确认之前，不会删除任何内容。",
        searchKeywords: [
            "卸载", "移除", "删除", "清掉", "清理", "卸载应用",
            "移除应用", "删除应用", "应用", "应用程序", "残留",
        ]
    )
    static let openAppWhenRun = true

    @Parameter(title: "应用")
    var app: InstalledAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("用 Purge 卸载 \(\.$app)")
    }

    init() {}

    init(app: InstalledAppEntity) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Not awaited: loading the app list can take a while, and Spotlight
        // would wait on it. The window shows the progress instead.
        let app = app
        Task { await IntentRouter.shared.showUninstaller(appID: app.id, name: app.name) }
        return .result()
    }
}
