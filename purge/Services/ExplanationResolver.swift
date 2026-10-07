import Foundation

/// Ordered resolution: user override -> bundled DB -> tier list -> unknown.
/// User overrides are keyed by exact path and trump every automatic source.
///
/// Guesses left in `ai_cache.json` by the removed AI classifier are deliberately not
/// read. They outranked the reviewed list, so a guess could mark a folder Safe that
/// the bundled data never vetted, and only on Macs that ran an early build.
enum ExplanationResolver {
    nonisolated static let unsureExplanation = "我们无法识别这个文件夹。建议保持原样。"

    /// Resolution order:
    /// 1. `user_overrides.json` keyed by exact path (when provided)
    /// 2. Bundled `explanations.json`
    /// 3. `SafetyTierList`
    /// 4. Return unknown
    nonisolated static func initialSafetyForCacheFolder(
        folderName: String,
        friendlyHeadline: String,
        path: URL? = nil
    ) -> SafetyInfo {
        if let path,
           let override = UserOverridesStore.read(path: path) {
            return UserOverridesStore.safetyInfo(from: override, friendlyHeadline: friendlyHeadline)
        }
        if let record = ExplanationDatabase.matchBundledDatabase(folderName: folderName) {
            return ExplanationDatabase.safetyInfo(from: record)
        }
        if let tierLevel = SafetyTierList.evaluate(folderName: folderName, path: path) {
            return tierSafetyInfo(level: tierLevel, headline: friendlyHeadline)
        }
        return SafetyInfo(
            level: .unknown,
            headline: friendlyHeadline,
            explanation: unsureExplanation,
            recoverySteps: "",
            reinstallCommand: nil
        )
    }

    nonisolated static func tierSafetyInfo(level: SafetyLevel, headline: String) -> SafetyInfo {
        let explanation: String
        switch level {
        case .safe:
            explanation = "这是已知的缓存文件夹，应用或开发工具会自动重新生成。"
        case .medium:
            explanation = "这个文件夹可能涉及同步数据或面向用户的应用数据。删除通常是安全的，但可能带来不便。"
        case .unknown:
            explanation = unsureExplanation
        }
        return SafetyInfo(
            level: level,
            headline: headline,
            explanation: explanation,
            recoverySteps: "",
            reinstallCommand: nil
        )
    }
}
