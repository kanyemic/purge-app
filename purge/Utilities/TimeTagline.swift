import Foundation

/// Builds the completion tagline shown on the cleanup overlay:
/// "done in [time] · [quip]".
enum TimeTagline {
    struct Selection: Equatable {
        let line: String
        let factPart: String
        let quip: String
    }

    private static let lastShownQuipKey = "cleanCompletion.lastShownTimeQuip"

    /// One-shot convenience: picks a non-repeating quip and records it as last shown.
    static func line(for seconds: Double, defaults: UserDefaults = .standard) -> String {
        let selection = select(for: seconds, defaults: defaults)
        store(selection, defaults: defaults)
        return selection.line
    }

    /// Pure pick (no UserDefaults write) so callers can choose in `init` and
    /// persist in `onAppear`, mirroring the previous encouragement picker.
    static func select(for seconds: Double, defaults: UserDefaults = .standard) -> Selection {
        let options = quips(for: seconds)
        let lastShown = defaults.string(forKey: lastShownQuipKey)
        var pick = options.randomElement() ?? options[0]
        if pick == lastShown, let reroll = options.randomElement() {
            pick = reroll
        }
        let fact = "用时 \(timeText(for: seconds))"
        return Selection(line: "\(fact) · \(pick)", factPart: fact, quip: pick)
    }

    static func store(_ selection: Selection, defaults: UserDefaults = .standard) {
        defaults.set(selection.quip, forKey: lastShownQuipKey)
    }

    static func timeText(for seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.1f 秒", max(0.1, seconds))
        }
        let whole = Int(seconds.rounded())
        if whole < 60 {
            // Chinese has no plural form; the branch stays so a single second and
            // several still share one formatting site.
            return whole == 1 ? "1 秒" : "\(whole) 秒"
        }
        return "\(whole / 60)分\(whole % 60)秒"
    }

    static func quips(for seconds: Double) -> [String] {
        switch seconds {
        case ..<3:
            return [
                "快到你没看清",
                "真够快的",
                "一气呵成",
                "比等咖啡还快"
            ]
        case ..<15:
            return [
                "干脆利落",
                "行云流水",
                "来了就清完了"
            ]
        case ..<60:
            return [
                "等得值",
                "这次清得干净",
                "深度清理，完成"
            ]
        default:
            return [
                "这次清得真不少",
                "繁重的活，交给它了",
                "你的 Mac 说谢谢"
            ]
        }
    }
}
