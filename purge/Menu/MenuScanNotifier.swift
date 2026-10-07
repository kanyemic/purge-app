import UserNotifications

/// Surfaces the outcome of a menu-initiated scan (and its follow-up clean) as a
/// user notification. Used only when the status item is off screen — e.g. an
/// auto-hiding menu bar — so feedback never disappears with the bar. The junk
/// result carries a Clean action that routes through the same safe-clean path
/// as the menu's "Clean Safe Files".
enum MenuScanNotifier {
    static let categoryIdentifier = "purge.menuScan.result"
    static let cleanActionIdentifier = "purge.menuScan.clean"

    /// Registers the result category + Clean action. Idempotent; safe to call
    /// on every launch.
    static func configure() {
        let clean = UNNotificationAction(
            identifier: cleanActionIdentifier,
            title: "清理安全项目",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [clean],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func notifyScanResult(readyBytes bytes: Int64) async {
        guard await ScheduledCleanupNotifier.requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "扫描完成"
        if bytes > 0 {
            content.body = "\(formatBytes(bytes)) 可清理。"
            content.categoryIdentifier = categoryIdentifier
        } else {
            content.body = "没有可清理的内容。"
        }
        content.sound = .default
        await deliver(content)
    }

    static func notifyCleaned(bytesMovedToTrash bytes: Int64) async {
        guard await ScheduledCleanupNotifier.requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "已将 \(formatBytes(bytes)) 移入废纸篓"
        content.body = "清空废纸篓即可释放空间。"
        content.sound = .default
        await deliver(content)
    }

    private static func deliver(_ content: UNMutableNotificationContent) async {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().add(request) { _ in cont.resume() }
        }
    }
}
