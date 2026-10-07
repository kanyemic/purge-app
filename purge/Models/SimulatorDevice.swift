import Foundation

nonisolated struct SimulatorDevice: Identifiable, Hashable {
    let id: UUID
    let deviceName: String
    let runtimeVersion: String
    let isAvailable: Bool
    let lastBootedAt: Date?
    /// `nil` while folder sizing is still running.
    var sizeOnDisk: Int64?
    let folderURL: URL
    var isSelected: Bool
    let safetyInfo: SafetyInfo

    var formattedSize: String {
        guard let sizeOnDisk else { return "正在计算…" }
        return formatBytes(sizeOnDisk)
    }

    static func safetyInfo(
        isAvailable: Bool,
        lastBootedAt: Date?,
        deviceName: String,
        runtimeVersion: String
    ) -> SafetyInfo {
        let headline = "\(deviceName) · \(runtimeVersion)"
        // The safety badge already says whether it is safe, so the explanation
        // only covers when it was last used and what deleting costs. `simctl
        // delete` removes the device and its apps and data; the runtime stays.
        let cost = "会删除它的应用和数据。"
        if !isAvailable {
            return SafetyInfo(
                level: .safe,
                headline: headline,
                // CoreSimulator marks a device unavailable for more than one reason
                // (missing runtime, unsupported device type), so don't name one.
                explanation: "Xcode 已无法运行此设备。\(cost)",
                recoverySteps: "",
                reinstallCommand: nil
            )
        }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast

        // simctl omits lastBootedAt for some devices that have been used, so a
        // missing date does not mean the device was never booted.
        guard let lastUsed = lastBootedAt else {
            return SafetyInfo(
                level: .safe,
                headline: headline,
                explanation: "最近使用时间未知。\(cost)",
                recoverySteps: "",
                reinstallCommand: nil
            )
        }

        let level: SafetyLevel = lastUsed >= thirtyDaysAgo ? .medium : .safe
        let monthsAgo = Calendar.current.dateComponents([.month], from: lastUsed, to: Date()).month ?? 0
        let explanation: String
        if monthsAgo < 1 {
            explanation = "最近一个月内使用过。\(cost)"
        } else {
            // Chinese has no plural form, but the singular branch stays so the count
            // still reads from one place and can diverge if the wording changes.
            let months = monthsAgo == 1 ? "1 个月" : "\(monthsAgo) 个月"
            explanation = "上次使用是在 \(months)前。\(cost)"
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
