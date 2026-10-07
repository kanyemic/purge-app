import SwiftUI

struct DeletionConfirmSheet: View {
    let candidates: [PurgeStore.DeletionCandidate]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var totalBytes: Int64 {
        candidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var unknownCandidates: [PurgeStore.DeletionCandidate] {
        candidates.filter { $0.safetyInfo.level == .unknown }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Safe + Check First only (shown as lower-risk additions in the elevated layout).
    private var benignCandidates: [PurgeStore.DeletionCandidate] {
        candidates.filter { $0.safetyInfo.level == .safe || $0.safetyInfo.level == .medium }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private var showsElevatedRiskLayout: Bool {
        !unknownCandidates.isEmpty
    }

    /// Check First leads, so a pick the user may not have meant is the first thing read.
    private static let groupedSectionOrder: [SafetyLevel] = [.medium, .safe]

    private var groupedBenign: [(SafetyLevel, [PurgeStore.DeletionCandidate])] {
        let grouped = Dictionary(grouping: benignCandidates, by: { $0.safetyInfo.level })
        return Self.groupedSectionOrder.compactMap { level in
            guard let values = grouped[level], !values.isEmpty else { return nil }
            return (level, values.sorted { $0.sizeBytes > $1.sizeBytes })
        }
    }

    var body: some View {
        Group {
            if showsElevatedRiskLayout {
                elevatedRiskLayout
            } else {
                standardLayout
            }
        }
        .padding(AppStyle.Spacing.large)
        .frame(minWidth: 580, minHeight: showsElevatedRiskLayout ? 520 : 500)
        .background(AppColors.surfaceBase)
    }

    private func locationLabel(for item: PurgeStore.DeletionCandidate) -> String {
        item.subtitle ?? item.path.lastPathComponent
    }

    // MARK: - Standard layout

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                Text("将选中的项目移入废纸篓？")
                    .font(AppStyle.Typography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Purge 会将这些项目移入废纸篓。如果你改变主意，可以随时恢复。")
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    ForEach(groupedBenign, id: \.0) { level, items in
                        sectionHeader(level.displayName)
                        if level == .medium {
                            checkFirstNote(count: items.count)
                        }
                        ForEach(items) { item in
                            candidateCard(item)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 260)

            footer(primaryTitle: "将 \(candidates.count) 项移入废纸篓")
        }
    }

    // MARK: - Elevated (unknown present) layout

    private var elevatedRiskLayout: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.medium) {
            elevatedWarningHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                    if !unknownCandidates.isEmpty {
                        sectionHeader(SafetyLevel.unknown.displayName)
                        Text("Purge 无法分辨这些文件夹是什么。只有在你清楚其中内容时才继续。")
                            .font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(unknownCandidates) { item in
                            candidateCard(item, showsExplanation: true)
                        }
                    }

                    if !benignCandidates.isEmpty {
                        sectionHeader("本次清理中还包含")
                        ForEach(benignCandidates) { item in
                            candidateCard(item)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 260)

            footer(primaryTitle: "继续")
        }
    }

    private var elevatedWarningHeader: some View {
        HStack(alignment: .top, spacing: AppStyle.Spacing.small) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(AppColors.statusCheckText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xxSmall) {
                Text("其中一些无法识别")
                    .font(AppStyle.Typography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Purge 无法识别你选择的每一个文件夹。只有在你确定可以安全删除时才继续。在实际移动之前，你会再确认一次。")
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Shared pieces

    private func checkFirstNote(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.statusCheckText)
                .accessibilityHidden(true)
            Text(count == 1
                ? "这一项可能包含你之后会用到的东西。如果不确定，请取消并取消勾选它。"
                : "这些项目可能包含你之后会用到的东西。如果对其中某一项不确定，请取消并取消勾选它。")
                .font(AppStyle.Typography.metadata)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppStyle.Typography.metadataEmphasis)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
            .padding(.top, AppStyle.Spacing.xSmall)
    }

    /// One deletion candidate as a card: its name, folder, and size, plus a safety
    /// tag and the reinstall hint when there is one. `showsExplanation` adds the
    /// safety explanation, used for the unknown items in the elevated layout.
    private func candidateCard(
        _ item: PurgeStore.DeletionCandidate,
        showsExplanation: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
            HStack(spacing: AppStyle.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppStyle.Typography.rowTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(locationLabel(for: item))
                        .font(AppStyle.Typography.metadata)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let command = item.reinstallCommand, !command.isEmpty {
                        Text(command)
                            .font(AppStyle.Typography.metadata)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: AppStyle.Spacing.xSmall)

                VStack(alignment: .trailing, spacing: AppStyle.Spacing.xxSmall) {
                    Text(item.formattedSize)
                        .font(AppStyle.Typography.metadataEmphasis)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                    safetyTag(for: item.safetyInfo.level)
                }
            }

            if showsExplanation, !item.safetyInfo.explanation.isEmpty {
                Text(item.safetyInfo.explanation)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.small)
        .padding(.vertical, AppStyle.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .fill(AppColors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                .strokeBorder(AppColors.borderSubtle, lineWidth: 1)
        )
    }

    private func safetyTag(for level: SafetyLevel) -> some View {
        let text: String
        let fg: Color
        let bg: Color
        switch level {
        case .safe:
            text = "安全"
            fg = AppColors.statusSafeText
            bg = AppColors.statusSafeFill
        case .medium:
            text = "先确认"
            fg = AppColors.statusCheckText
            bg = AppColors.statusCheckFill
        case .unknown:
            text = "不确定"
            fg = AppColors.statusDangerText
            bg = AppColors.statusDangerFill
        }
        return Text(text)
            .font(AppStyle.Typography.metadataEmphasis)
            .foregroundStyle(fg)
            .padding(.horizontal, AppStyle.Spacing.xSmall)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(bg))
    }

    private func footer(primaryTitle: String) -> some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Text("释放 \(formatBytes(totalBytes))")
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Button("取消", action: onCancel)
                .buttonStyle(.purge(.secondary))
                .keyboardShortcut(.cancelAction)

            Button(primaryTitle) {
                onConfirm()
            }
            .buttonStyle(.purge(.destructive))
            .keyboardShortcut(.defaultAction)
        }
    }
}
