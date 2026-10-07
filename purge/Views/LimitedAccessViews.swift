import SwiftUI

// The main window's cues while Full Disk Access is off. Every one reads the store's
// single `hasFullDiskAccess` value and opens the same `LookDeeperSheet`, so none of
// them can go stale or ask in its own words.

/// Stands in for a tab that cannot work without Full Disk Access.
struct LockedFeatureView: View {
    enum Feature {
        case largeFiles
        case uninstaller

        var title: String {
            switch self {
            case .largeFiles: return "「大文件」需要查看你的文件夹内部"
            case .uninstaller: return "卸载器需要完整访问权限"
            }
        }

        var message: String {
            switch self {
            case .largeFiles:
                return "大文件往往位于「下载」「文稿」和「桌面」中，在你允许 Purge 查看之前，macOS 会一直锁定这些位置。Purge 只会把它们展示给你，绝不会自行清理。"
            case .uninstaller:
                return "应用会在 macOS 锁定的文件夹里留下设置和缓存。没有访问权限时，Purge 只能删除应用，却把这些残留留下来，因此它会等到能完整处理时再动手。"
            }
        }

        var symbol: String {
            switch self {
            case .largeFiles: return "doc.viewfinder"
            case .uninstaller: return "shippingbox"
            }
        }
    }

    let feature: Feature
    @EnvironmentObject private var store: PurgeStore

    var body: some View {
        VStack(spacing: AppStyle.Spacing.medium) {
            Image(systemName: feature.symbol)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)

            VStack(spacing: AppStyle.Spacing.xSmall) {
                Text(feature.title)
                    .font(AppStyle.Typography.sectionTitle)
                    .multilineTextAlignment(.center)

                Text(feature.message)
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                store.isLookDeeperPresented = true
            } label: {
                Label("深入查看", systemImage: "lock.open")
            }
            .buttonStyle(.purge(.primary))
        }
        .frame(maxWidth: 440)
        .padding(AppStyle.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Sits beside Scan on App Caches and Dev Tools, where the list is real but partial.
struct LookDeeperHeaderButton: View {
    @EnvironmentObject private var store: PurgeStore

    var body: some View {
        Button {
            store.isLookDeeperPresented = true
        } label: {
            Label("深入查看", systemImage: "lock.open")
        }
        .buttonStyle(.purge(.secondary))
        .help("有些位置仍被锁定。让 Purge 深入查看。")
    }
}

/// A slim tappable card in the sidebar, on every tab, until access is granted. The
/// whole card is the button, like the suggestion rows at the top of System Settings,
/// so it reads as "there when you're ready" rather than a warning.
struct LimitedScanNotice: View {
    @EnvironmentObject private var store: PurgeStore

    var body: some View {
        Button {
            store.isLookDeeperPresented = true
        } label: {
            HStack(spacing: AppStyle.Spacing.xSmall) {
                Image(systemName: "lock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("受限扫描")
                        .font(AppStyle.Typography.callout.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("让 Purge 深入查看")
                        .font(AppStyle.Typography.metadataEmphasis)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppStyle.Spacing.small)
            .padding(.vertical, AppStyle.Spacing.xSmall + 2)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .fill(AppColors.fillSecondary)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous))
        }
        .buttonStyle(LimitedScanNoticeButtonStyle())
        .accessibilityLabel("受限扫描。让 Purge 深入查看。")
        .transition(.opacity)
    }
}

private struct LimitedScanNoticeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
