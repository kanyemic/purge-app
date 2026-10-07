import UserNotifications

enum ScheduledCleanupNotifier {
    static func requestAuthorizationIfNeeded() async -> Bool {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    static func notifyNothingEligible() async {
        await deliver(title: "计划清理已完成", body: "目前没有符合你安全设置的项目，稍后会再试。")
    }

    static func notifyScheduledCleanFinished(bytesMovedToTrash: Int64, deletedCount: Int) async {
        let space = formatBytes(bytesMovedToTrash)
        // 中文量词不随数量变化，因此与英文的两个分支等价。
        let noun = "项"
        await deliver(
            title: "计划清理已完成",
            body: "已将 \(deletedCount) \(noun)移到废纸篓，约 \(space)。清空废纸篓即可释放这部分空间。"
        )
    }

    static func notifyScheduledCleanFailed() async {
        await deliver(
            title: "计划清理",
            body: "自动清理过程中出现问题。方便时打开 Purge 重试。"
        )
    }

    private static func deliver(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.75, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().add(request) { _ in cont.resume() }
        }
    }
}

/// Shows banners while the Purge window is visible and routes notification
/// actions (currently the menu-scan Clean button) back into the app.
final class ScheduledNotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScheduledNotificationPresentationDelegate()

    /// Invoked on the main actor when the menu-scan Clean action is tapped.
    var onCleanAction: (@MainActor () -> Void)?

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == MenuScanNotifier.cleanActionIdentifier {
            let handler = onCleanAction
            Task { @MainActor in handler?() }
        }
        completionHandler()
    }
}
