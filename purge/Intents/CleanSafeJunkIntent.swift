import AppIntents
import AppKit

/// The menu bar's Clean, from Spotlight or Siri: scans, then moves Safe items
/// in App Caches and Dev Tools to the Trash, where they can be recovered.
/// Check First items are never touched. Only explicit cleaning words lead
/// here; vague ones ("free up space", "clean up my Mac") stay with Scan for
/// Junk, so a loose request never cleans by accident.
struct CleanSafeJunkIntent: AppIntent {
    static let title: LocalizedStringResource = "清理安全垃圾"
    static let description = IntentDescription(
        "扫描垃圾，并将应用缓存和开发工具中标记为安全的项目移入废纸篓，与 Purge 菜单栏中的「清理」相同。标为「先确认」的项目不会被处理。",
        searchKeywords: [
            "清理", "清理垃圾", "安全清理", "清理缓存", "清理我的 Mac",
            "清除垃圾", "清除缓存", "删除垃圾", "移除垃圾",
            "清空缓存", "垃圾清理",
        ]
    )

    /// Opens Purge on the Overview, which shows the cleaning as it happens, and
    /// answers with one line, the form Spotlight keeps inside its panel.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<AttributedString> & ProvidesDialog {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let outcome = await IntentRouter.shared.cleanSafeJunk(reduceMotion: reduceMotion)
        return .result(value: outcome.styledAnswer, dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

extension IntentRouter.CleanOutcome {
    /// 例如「已将 1.61 GB 垃圾移入废纸篓。」，其中体积加粗。
    var styledAnswer: AttributedString {
        guard case .cleaned(let bytes, let failedCount) = self, bytes > 0 else { return AttributedString(dialog) }
        var size = AttributedString(formatBytes(bytes))
        size.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString("已将 ") + size + AttributedString(" 垃圾移入废纸篓。")
            + AttributedString(Self.failureNote(failedCount))
    }

    var dialog: String {
        switch self {
        case .needsSetup:
            return "请先完成 Purge 的初始设置。"
        case .busyCleaning:
            return "Purge 正在清理。"
        case .nothingToClean:
            return "目前没有可清理的垃圾。"
        case .stopped:
            return "扫描在完成前停止，因此没有清理任何内容。"
        case .cleaned(let bytes, let failedCount) where bytes > 0:
            return "已将 \(formatBytes(bytes)) 垃圾移入废纸篓。" + Self.failureNote(failedCount)
        case .cleaned:
            return "Purge 无法将垃圾移入废纸篓。请打开 Purge 查看原因。"
        }
    }

    private static func failureNote(_ failedCount: Int) -> String {
        switch failedCount {
        case 0: return ""
        case 1: return "有 1 个项目无法移动。"
        default: return "有 \(failedCount) 个项目无法移动。"
        }
    }
}
