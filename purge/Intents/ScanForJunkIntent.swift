import AppIntents
import Foundation

/// Named for what it finds: "Scan My Mac" read like a virus scan, and the
/// answer covers only App Caches and Dev Tools.
struct ScanForJunkIntent: AppIntent {
    static let title: LocalizedStringResource = "扫描垃圾"
    /// One action for every way of asking about junk and space: Spotlight
    /// matches typed words against the title, the App Shortcut phrases and
    /// these keywords, so "free up space", "storage full" or "how much can I
    /// free" all find it.
    static let description = IntentDescription(
        "打开 Purge 的总览页并扫描垃圾，告诉你应用缓存和开发工具中有多少可以安全清理。在你于 Purge 中确认之前，不会清理任何内容。",
        searchKeywords: [
            // Cleaning words go to Clean Safe Junk; this keeps the ones that
            // only ask how things stand.
            "垃圾", "扫描", "扫描我的 Mac", "查看垃圾", "查找垃圾",
            "释放空间", "清出空间", "空间", "存储", "存储空间不足", "磁盘已满",
            "磁盘空间", "Mac 已满", "空间不足", "能释放多少",
            "什么占用了空间", "缓存",
        ]
    )

    /// Opens Purge, and answers with one line of text. That is the form
    /// Spotlight keeps inside its own panel: a card, a follow-up question or a
    /// background run moves the action into a separate box. Progress is not
    /// reported: Spotlight shows the action's name while it runs regardless.
    /// Cleaning happens in the window, on the Overview's Clean Safe Items.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AttributedString> & ProvidesDialog {
        let outcome = await IntentRouter.shared.scanMac()
        return .result(value: outcome.styledAnswer, dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

extension IntentRouter.ScanOutcome {
    /// The answer Spotlight shows, with the size in bold.
    var styledAnswer: AttributedString {
        guard case .scanned(let bytes) = self, bytes > 0 else { return AttributedString(dialog) }
        var size = AttributedString(formatBytes(bytes))
        size.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString("发现 ") + size + AttributedString(" 可安全清理的垃圾。")
    }

    var dialog: String {
        switch self {
        case .needsSetup:
            return "请先完成 Purge 的初始设置。"
        case .busyCleaning:
            return "Purge 正在清理，请稍后再扫描。"
        case .scanned(let bytes) where bytes > 0:
            return "发现 \(formatBytes(bytes)) 可安全清理的垃圾。"
        case .scanned:
            return "目前没有可清理的垃圾。"
        case .stopped:
            return "扫描尚未完成就停止了。"
        }
    }
}
