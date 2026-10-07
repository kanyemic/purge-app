//
//  PurgeUpdater.swift
//  purge
//
//  汉化版说明：本文件原用于包装 Sparkle，以支持后台定时检查和用户主动触发的
//  “检查更新”。由于本构建是本地汉化版，上游英文发行版会覆盖中文界面，
//  这里停用了所有更新检查入口，仅保留对外接口以维持现有调用方不变。
//

import AppKit
import Combine
import Sparkle

@MainActor
final class PurgeUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// 汉化版：始终为 false，更新检查已被停用。保留属性以兼容现有观察方。
    @Published private(set) var automaticallyChecksForUpdates = false

    /// 汉化版：始终为 false，因此“检查更新”入口会保持不可用状态。
    @Published private(set) var canCheckForUpdates = false

    /// Sparkle 持久化自动检查开关时使用的偏好项名称。
    private static let automaticChecksDefaultsName = "SUEnableAutomaticChecks"

    override init() {
        super.init()
        // 汉化版：不启动 Sparkle 更新控制器，从根源上阻止上游更新。
        // 同时清理可能已持久化的用户开关，避免旧偏好重新启用自动检查。
        UserDefaults.standard.removeObject(forKey: Self.automaticChecksDefaultsName)
        automaticallyChecksForUpdates = false
        canCheckForUpdates = false
    }

    /// 汉化版：忽略任何启用自动检查的请求。
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        _ = enabled
        automaticallyChecksForUpdates = false
    }

    /// 汉化版：更新检查已停用，此处不再触发 Sparkle。
    func checkForUpdates() {}

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        // Optional hook; Sparkle clears the session when the update driver finishes.
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        // Sparkle already ends the session when the update driver aborts.
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        // Session is fully complete; safe to start another user-initiated check.
    }
}
