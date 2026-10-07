import Foundation

/// Read-only summary of what Purge may clean, derived from the live safety definitions.
/// Presentation only: no changes to deletion behavior.
enum SafetyAllowlistSummary {

    struct Category: Identifiable {
        let id: String
        let icon: String
        let title: String
        let description: String
        let backingCount: Int
    }

    private enum CategoryID {
        static let appCaches = "app-caches"
        static let browserCaches = "browser-caches"
        static let devCaches = "dev-caches"
        static let systemJunk = "system-junk"
    }

    static var allowedCategories: [Category] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let whitelistedPrefixes = DeletionSafetyPolicy.whitelistedAbsolutePrefixes(home: home)

        let appSupportCacheCount = CacheDiscoveryPaths.applicationSupportDirectCacheNames.count
        let libraryCachesIncluded = whitelistedPrefixes.contains { $0.hasSuffix("/Library/Caches") } ? 1 : 0

        let browserCacheCount =
            CacheDiscoveryPaths.chromiumProfileCacheNames.count
            + CacheDiscoveryPaths.chromiumProfileRelativePaths.count

        let devCacheCount = DeletionSafetyPolicy.whitelistedFolderNames.count

        let logsPrefix = "\(home)/Library/Logs"
        let systemJunkCount = whitelistedPrefixes.filter {
            $0 == logsPrefix || $0.hasPrefix(logsPrefix + "/")
        }.count

        return [
            Category(
                id: CategoryID.appCaches,
                icon: "app.badge",
                title: "应用缓存",
                description: "~/Library/Caches 与 Application Support 下可重新生成的缓存文件夹",
                backingCount: appSupportCacheCount + libraryCachesIncluded
            ),
            Category(
                id: CategoryID.browserCaches,
                icon: "globe",
                title: "各配置文件的浏览器缓存",
                description: "按浏览器配置文件区分的 Chromium 配置缓存与 Service Worker 存储",
                backingCount: browserCacheCount
            ),
            Category(
                id: CategoryID.devCaches,
                icon: "hammer",
                title: "常见开发缓存",
                description: "可重新构建的项目产物，例如 node_modules、DerivedData 与构建输出",
                backingCount: devCacheCount
            ),
            Category(
                id: CategoryID.systemJunk,
                icon: "doc.text",
                title: "日志与崩溃报告",
                description: "~/Library/Logs 下的用户日志与诊断报告",
                backingCount: systemJunkCount
            )
        ]
    }

    static var boundaryLine: String {
        var parts: [String] = []

        if !DeletionSafetyPolicy.systemCacheDeletionPrefixes.isEmpty {
            parts.append("任何需要管理员权限的内容")
        }

        let protectedContainerCount =
            DeletionSafetyPolicy.protectedContainerBundleIDs.count
            + DeletionSafetyPolicy.protectedSystemCacheFolderNames.count
            + DeletionSafetyPolicy.protectedLogFolderNames.count
        if protectedContainerCount > 0 {
            parts.append("受保护的容器")
        }

        let personalLabels = personalFileBoundaryLabels
        if !personalLabels.isEmpty {
            parts.append("个人文件（\(personalLabels.joined(separator: "、"))）")
        }

        guard !parts.isEmpty else {
            return "Purge 绝不触碰：白名单以外的路径"
        }

        return "Purge 绝不触碰：\(parts.joined(separator: "、"))"
    }

    /// Friendly labels for user-content roots pulled from never-delete policy paths.
    private static var personalFileBoundaryLabels: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        func label(for path: String) -> String? {
            guard path.hasPrefix(home + "/") else { return nil }
            let relative = String(path.dropFirst(home.count + 1))
            let top = relative.split(separator: "/").first.map(String.init) ?? relative
            switch top {
            case "Documents": return "文稿"
            case "Desktop": return "桌面"
            case "Downloads": return "下载"
            case "Pictures": return "图片"
            case "Music": return "音乐"
            case "Movies": return "影片"
            case "Library":
                let sub = relative.split(separator: "/").dropFirst().first.map(String.init) ?? ""
                switch sub {
                case "Keychains": return "钥匙串"
                case "Preferences": return "偏好设置"
                case "Mail": return "邮件"
                case "Application Support": return "应用支持"
                default: return nil
                }
            default:
                return top.lowercased()
            }
        }

        var seen = Set<String>()
        var labels: [String] = []

        for path in DeletionSafetyPolicy.neverDeleteExactPaths(home: home) + DeletionSafetyPolicy.neverDeletePrefixes(home: home) {
            guard path.hasPrefix(home) else { continue }
            guard let label = label(for: path), seen.insert(label).inserted else { continue }
            labels.append(label)
        }

        return labels
    }
}
