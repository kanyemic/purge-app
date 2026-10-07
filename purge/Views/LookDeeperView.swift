import SwiftUI

/// The one place Purge asks for Full Disk Access.
///
/// Purge works without it (see `ScanAccess`), so this is an offer, not a gate:
/// it says what the permission unlocks, what Purge will not do with it, and has
/// a real way out. Onboarding shows it after the first clean; the main window
/// shows it as a sheet from the sidebar notice and the locked tabs.
///
/// When access lands during onboarding, the same view runs the deeper scan and
/// shows what the permission found, right where the user said yes. As a sheet it
/// just closes onto the Overview, whose figures fill in as the unlocked scans run.
struct LookDeeperView: View {
  enum Context {
    /// Last onboarding step. `didClean` is false when the user went to review
    /// the list instead of cleaning, so the opening line can't say "That was".
    case onboarding(didClean: Bool)
    /// A sheet in the main window.
    case sheet
  }

  let context: Context
  /// "Not now". Onboarding finishes; the sheet closes.
  let onNotNow: () -> Void
  /// After the reveal in onboarding, when the user moves on. The sheet calls it as
  /// soon as access lands.
  let onFinished: () -> Void
  /// When "Let Purge in" opens System Settings.
  var onOpenSettings: () -> Void = {}

  private enum Phase {
    case asking
    case scanning
    case revealed(LockedPlacesFindings)
  }

  @EnvironmentObject private var store: PurgeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase: Phase = .asking
  @State private var didOpenSettings = false

  static let contentWidth: CGFloat = 620
  /// Long enough to read "Looking deeper" even when the scan is instant.
  private static let minimumScanDuration: Duration = .milliseconds(1500)

  var body: some View {
    Group {
      switch phase {
      case .asking:
        askingBody
      case .scanning:
        scanningBody
      case .revealed(let findings):
        revealedBody(findings)
      }
    }
    .frame(maxWidth: Self.contentWidth)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: phaseKey)
    .task { await pollUntilGranted() }
  }

  /// `Phase` carries findings that are not `Equatable`; the animation only needs
  /// to know which screen is up.
  private var phaseKey: Int {
    switch phase {
    case .asking: return 0
    case .scanning: return 1
    case .revealed: return 2
    }
  }

  @ViewBuilder
  private var promises: some View {
    LookDeeperPromise(symbol: "eye", text: "只在你同意时才清理")
    LookDeeperPromise(symbol: "icloud.slash", text: "不会离开你的 Mac")
    LookDeeperPromise(symbol: "trash", text: "所有内容都会移入废纸篓")
  }

  private var askingBody: some View {
    VStack(spacing: AppStyle.Spacing.large) {
      VStack(spacing: AppStyle.Spacing.small) {
        OnboardingStepTitle(text: "想让 Purge 深入查看吗？")
          .onboardingBlurIn(index: 0)

        Text(leadText)
          .font(AppStyle.Typography.sectionTitle.weight(.regular))
          .foregroundStyle(AppColors.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .onboardingBlurIn(index: 1)
      }

      // What access unlocks, as tiles, then what Purge promises, as one quiet row.
      // Each promise is something Purge does, not a limit on the permission:
      // Full Disk Access itself can read and write, so "can't" would not be true.
      HStack(spacing: AppStyle.Spacing.small) {
        LookDeeperTile(symbol: "square.stack.3d.up", text: "App Store 应用缓存")
        LookDeeperTile(symbol: "doc.text.magnifyingglass", text: "被遗忘的大文件")
        LookDeeperTile(symbol: "shippingbox", text: "已删除应用的残留")
      }
      .onboardingBlurIn(index: 2)

      VStack(spacing: AppStyle.Spacing.small) {
        // One row where it fits (onboarding); stacked in the narrower sheet.
        ViewThatFits(in: .horizontal) {
          HStack(spacing: AppStyle.Spacing.large) { promises }
          VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) { promises }
        }

        Text("macOS 称其为「完全磁盘访问权限」。你可以随时在「系统设置」中关闭它。")
          .font(AppStyle.Typography.metadata)
          .foregroundStyle(AppColors.textTertiary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .onboardingBlurIn(index: 3)

      VStack(spacing: AppStyle.Spacing.small) {
        OnboardingPrimaryButton(title: "允许 Purge 访问", systemImage: "arrow.up.forward", action: letPurgeIn)
        OnboardingSecondaryButton(title: "暂不", action: onNotNow)
          .keyboardShortcut(.cancelAction)

        if didOpenSettings {
          Text("在「系统设置」中为 Purge 打开权限，然后返回。如果 macOS 提示重新打开 Purge，请照做。")
            .font(AppStyle.Typography.metadata)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
        }
      }
      .onboardingBlurIn(index: 4)
    }
    .transition(OnboardingTransitions.stepTransition(reduceMotion: reduceMotion))
  }

  private var scanningBody: some View {
    VStack(spacing: AppStyle.Spacing.small) {
      OnboardingLoadingStepTitle(baseText: "正在深入查看")
      Text("正在检查之前被锁定的位置。")
        .font(AppStyle.Typography.sectionTitle.weight(.regular))
        .foregroundStyle(AppColors.textSecondary)
    }
    .transition(OnboardingTransitions.stepTransition(reduceMotion: reduceMotion))
  }

  @ViewBuilder
  private func revealedBody(_ findings: LockedPlacesFindings) -> some View {
    VStack(spacing: AppStyle.Spacing.large) {
      if findings.isWorthLeadingWith {
        VStack(spacing: 0) {
          Text(formatBytes(findings.bytes))
            .font(AppStyle.Typography.display)
            .monospacedDigit()
          Text("更多可清理内容，来自之前被锁定的位置")
            .font(AppStyle.Typography.sectionTitle.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .onboardingBlurIn(index: 0)

        VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
          ForEach(Array(findings.categories.enumerated()), id: \.element.id) { index, category in
            OnboardingResultsCategoryRow(
              symbol: category.symbol,
              title: category.title,
              formattedSize: formatBytes(category.bytes)
            )
            .onboardingBlurIn(index: index + 1)
          }
        }
        .frame(maxWidth: 300)

        Text("「大文件」和卸载器现在也已解锁。")
          .font(AppStyle.Typography.callout)
          .foregroundStyle(AppColors.textSecondary)
          .onboardingBlurIn(index: findings.categories.count + 1)
      } else {
        OnboardingStepTitle(text: "Purge 现在可以看到全部内容了")
          .onboardingBlurIn(index: 0)
        Text(Self.smallFindingsMessage(findings))
          .font(AppStyle.Typography.sectionTitle.weight(.regular))
          .foregroundStyle(AppColors.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .onboardingBlurIn(index: 1)
      }

      OnboardingPrimaryButton(title: findings.isWorthLeadingWith ? "带我去看" : "继续") {
        finish(with: findings)
      }
      .padding(.top, AppStyle.Spacing.small)
    }
    .transition(OnboardingTransitions.stepTransition(reduceMotion: reduceMotion))
  }

  static func smallFindingsMessage(_ findings: LockedPlacesFindings) -> String {
    if findings.isPartial {
      return "「大文件」和卸载器已就绪。Purge 仍在检查你的项目，可能会有更多发现。"
    }
    return findings.bytes > 0
      ? "「大文件」和卸载器已就绪，Purge 还发现了一些可清理的内容。"
      : "「大文件」和卸载器已就绪。被锁定的文件夹里没有藏着大文件。"
  }

  private var leadText: String {
    switch context {
    case .onboarding(didClean: true):
      return "刚才只是简单的部分。更多杂物藏在 macOS 锁定的文件夹里。"
    case .onboarding(didClean: false), .sheet:
      return "有些杂物藏在 macOS 锁定的文件夹里。"
    }
  }

  private func letPurgeIn() {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
      didOpenSettings = true
    }
    onOpenSettings()
    openFullDiskAccessSettings()
  }

  /// In onboarding, "Show me" lands on the tab that holds most of what was found.
  private func finish(with findings: LockedPlacesFindings) {
    if case .onboarding = context, findings.isWorthLeadingWith {
      store.selectedTab = findings.categories.first?.title == PurgeStore.devArtifactCategoryTitle
        ? .devTools
        : .appCaches
    }
    onFinished()
  }

  /// macOS grants access to a running process without telling it, so the only way
  /// to notice is to keep probing. Off the main actor, and only while on screen.
  /// Also covers a relaunch: if access is already on when this appears, the
  /// reveal starts straight away.
  private func pollUntilGranted() async {
    while !Task.isCancelled {
      let granted = await store.probeFullDiskAccess()
      if granted != store.hasFullDiskAccess {
        store.applyFullDiskAccess(granted)
      }
      if granted {
        await handleGrant()
        return
      }
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return
      }
    }
  }

  private func handleGrant() async {
    // Claim the grant so a relaunch does not treat it as new.
    store.consumeFullDiskAccessGrant()
    guard case .onboarding = context else {
      // The main window already queues the scans access unlocks, and the Overview
      // shows them landing. A second screen saying the same thing is one too many.
      store.selectedTab = .overview
      onFinished()
      return
    }
    phase = .scanning
    let started = ContinuousClock.now
    let findings = await store.scanLockedPlaces()
    let remaining = Self.minimumScanDuration - (ContinuousClock.now - started)
    if remaining > .zero {
      try? await Task.sleep(for: remaining)
    }
    guard !Task.isCancelled else { return }
    phase = .revealed(findings)
  }
}

/// One thing access unlocks: an icon over two or three words.
private struct LookDeeperTile: View {
  let symbol: String
  let text: String

  var body: some View {
    VStack(spacing: AppStyle.Spacing.xSmall) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(AppColors.textSecondary)
        .frame(height: 24)
        .accessibilityHidden(true)
      Text(text)
        .font(AppStyle.Typography.callout)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, minHeight: 88)
    .padding(.horizontal, AppStyle.Spacing.small)
    .background(AppColors.surfaceCard, in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
        .stroke(AppColors.borderSubtle)
    }
    .accessibilityElement(children: .combine)
  }
}

/// One promise: a small icon and a few words, in a single row with the others.
private struct LookDeeperPromise: View {
  let symbol: String
  let text: String

  var body: some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: symbol)
        // One width for every icon, so stacked promises start their text in line.
        .frame(width: 18)
        .accessibilityHidden(true)
    }
    .font(AppStyle.Typography.callout)
    .foregroundStyle(AppColors.textSecondary)
    .fixedSize()
  }
}

/// `LookDeeperView` as a sheet over the main window.
struct LookDeeperSheet: View {
  @EnvironmentObject private var store: PurgeStore
  @Environment(\.dismiss) private var dismiss

  /// The same width as the app's other sheets. The onboarding step is laid out for
  /// the whole window; over the main window it would read as oversized.
  static let width: CGFloat = 580
  static let padding: CGFloat = 32

  var body: some View {
    LookDeeperView(
      context: .sheet,
      onNotNow: { dismiss() },
      onFinished: { dismiss() }
    )
    .padding(Self.padding)
    .frame(width: Self.width)
    .background(AppColors.surfaceBase)
  }
}

#Preview {
  LookDeeperView(context: .onboarding(didClean: true), onNotNow: {}, onFinished: {})
    .environmentObject(PurgeStore())
    .padding(40)
    .frame(width: AppWindowLayout.width, height: AppWindowLayout.minHeight)
}
