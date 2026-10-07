import Foundation

enum ScheduledCleaningFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .quarterly: return "每 3 个月"
        case .custom: return "自定义"
        }
    }

    /// Seconds between repeats (local notification + graceful activation sweep).
    /// For `.custom` this is a fallback only — the engine reads the persisted
    /// interval via `ScheduledCleaningPreferenceStore.effectiveRepeatIntervalSeconds`.
    var repeatIntervalSeconds: TimeInterval {
        switch self {
        case .weekly: return 7 * 24 * 60 * 60
        case .monthly: return 30 * 24 * 60 * 60
        case .quarterly: return 90 * 24 * 60 * 60
        case .custom: return 30 * 24 * 60 * 60
        }
    }
}

enum CustomCleaningIntervalUnit: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "天"
        case .week: return "周"
        case .month: return "个月"
        }
    }

    var singularDisplayName: String {
        switch self {
        case .day: return "天"
        case .week: return "周"
        case .month: return "个月"
        }
    }

    /// "every X" phrase for this unit at the given amount, e.g. "天" or "2 周".
    func phrase(amount: Int) -> String {
        amount == 1
            ? singularDisplayName
            : "\(amount) \(displayName)"
    }

    var seconds: TimeInterval {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        }
    }
}

enum DevToolsStalenessOption: Int, Codable, CaseIterable, Identifiable {
    case oneMonth = 30
    case threeMonths = 90
    case sixMonths = 180
    case twelveMonths = 365
    case twoYears = 730
    case showAll = 0

    static let userDefaultsKey = "devTools.stalenessThreshold"
    static let defaultOption: DevToolsStalenessOption = .sixMonths

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneMonth: return "1 个月"
        case .threeMonths: return "3 个月"
        case .sixMonths: return "6 个月"
        case .twelveMonths: return "12 个月"
        case .twoYears: return "2 年"
        case .showAll: return "显示全部"
        }
    }

    var description: String {
        switch self {
        case .showAll:
            return "所有检测到的项目都会出现在开发者项目中，不管上次使用是什么时候，正在使用中的除外。"
        case .oneMonth, .threeMonths, .sixMonths, .twelveMonths, .twoYears:
            return "在这段时间内没有动过的项目会出现在开发者项目中供清理。编辑项目中的任何文件或在项目中执行 git 操作都算作动过，正在使用中的项目永远不会出现。选择「显示全部」可以忽略时间显示所有检测到的项目。"
        }
    }

    nonisolated static func currentThresholdDays(userDefaults: UserDefaults = .standard) -> Int {
        let raw = userDefaults.integer(forKey: userDefaultsKey)
        if raw == showAll.rawValue {
            return showAll.rawValue
        }
        return DevToolsStalenessOption(rawValue: raw)?.rawValue ?? defaultOption.rawValue
    }
}
