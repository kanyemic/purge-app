import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PurgeStore
    @EnvironmentObject private var updater: PurgeUpdater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var prefs = ScheduledCleaningPreferenceStore.shared
    @ObservedObject private var startup = StartupPreferenceStore.shared
    @ObservedObject private var helper = PrivilegedHelperPreferenceStore.shared
    @ObservedObject private var registrar = ScheduledCleaningRegistrar.shared
    @ObservedObject private var history = CleanupHistoryStore.shared
    @ObservedObject private var removedApps = RemovedAppMonitor.shared
    @AppStorage(DevToolsStalenessOption.userDefaultsKey)
    private var devToolsStalenessThresholdRaw = DevToolsStalenessOption.defaultOption.rawValue
    @AppStorage(AppearanceMode.userDefaultsKey)
    private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage(DeveloperMode.userDefaultsKey)
    private var developerModeEnabled = false
    var showsPageHeader = true
    /// When true, the parent owns scrolling and the macOS 26 progressive scroll-edge blur.
    var usesExternalScrollContainer = false

    @State private var loginItemFailure: LoginItemFailure?
    @State private var isRunningScheduledCleanNow = false
    @State private var scheduledCleanNowMessage: String?
    @State private var isCleaningHistoryExpanded = false
    @State private var showClearHistoryConfirmation = false
    @State private var showCustomIntervalSheet = false
    @State private var selectedHistoryEntry: CleanupHistoryEntry?
    /// Session cache of on-disk sizes for excluded paths, keyed by path. No entry
    /// means the size is still loading.
    @State private var excludedPathSizes: [String: ExcludedPathSize] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: showsPageHeader ? 28 : 0) {
                if showsPageHeader {
                    Text("设置")
                        .font(AppStyle.Typography.pageTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    startupSection
                    deletedAppsSection
                    protectedAppRemovalSection
                    appearanceSection
                    cleaningScheduleSection
                    devToolsSection
                    excludedAppsSection
                    updatesSection
                    cleaningHistorySection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.horizontal, settingsHorizontalContentInset)
        .padding(.top, contentTopPadding)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: usesExternalScrollContainer ? nil : .infinity, alignment: .topLeading)
        .background(AppColors.surfaceBase)
        .onAppear {
            startup.refreshLoginItemStatus()
            helper.refresh()
        }
        // The user can turn the login item off in System Settings without telling
        // us; re-read on the way back in so the switch isn't stale. The privileged
        // helper is enabled in that same pane, so re-read it here too.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startup.refreshLoginItemStatus()
            clearLoginItemFailureIfResolved()
            helper.refresh()
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            CleanupHistoryDetailView(entry: entry)
        }
        .confirmationDialog(
            "清空清理历史记录？",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空历史记录", role: .destructive) {
                history.clear()
                CleanupLedgerStore.shared.clear(
                    keepingTotal: store.totalMovedToTrashBytes,
                    firstSeenAt: UserDefaults.standard.object(forKey: FirstRunGate.firstSeenAtKey) as? Date
                )
                isCleaningHistoryExpanded = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除这台 Mac 上所有已保存的清理记录，且无法撤销。")
        }
        .onChange(of: devToolsStalenessThresholdRaw) { _ in
            // Through the queue, so it waits its turn behind a running scan.
            store.requestScan(.cachesAndDevTools)
        }
        .alert(
            "计划清理",
            isPresented: Binding(
                get: { scheduledCleanNowMessage != nil },
                set: { if !$0 { scheduledCleanNowMessage = nil } }
            )
        ) {
            Button("好") { scheduledCleanNowMessage = nil }
        } message: {
            Text(scheduledCleanNowMessage ?? "")
        }
    }

    /// The four states the secure-removal helper can be in. Held as one value so the
    /// status line's icon, tint, message and action stay in lockstep, and so the
    /// layout can animate on a single `Equatable` key as the state changes.
    private enum HelperPhase: Equatable {
        case on
        case awaitingApproval
        case failed
        case off
    }

    private var helperPhase: HelperPhase {
        if helper.isEnabled { return .on }
        if helper.needsApproval { return .awaitingApproval }
        if helper.lastRegistrationFailed { return .failed }
        return .off
    }

    private var protectedAppRemovalSection: some View {
        settingsSection("受保护的应用移除") {
            // A switch, like every other setting, so the control never changes shape
            // between states. Turning it on registers the helper (which then waits on
            // approval in System Settings); turning it off unregisters it.
            settingsToggleRow(
                title: "无需密码移除管理员锁定的应用",
                caption: helperCaption,
                isOn: helperEnabledBinding
            )

            settingsSectionDivider

            // One status line that always sits here, so the message and its one action
            // (Open System Settings, when approval is pending) stay in a fixed place
            // rather than moving around beside the control.
            helperStatusCard
                .padding(16)
        }
    }

    private var helperCaption: String {
        """
        某些应用安装在管理员账户下，无法自行移入废纸篓。只有在应用需要时，Purge 才会请你启用它的安全移除辅助工具。项目仍会移入废纸篓，你也可以随时在这里关闭。
        """
    }

    /// The switch reads on for both `.on` and `.awaitingApproval`: once the user asks
    /// for the helper, its intent stays on while System Settings approval is pending,
    /// and turning the switch back off during that wait cancels the request.
    private var helperEnabledBinding: Binding<Bool> {
        Binding(
            get: { helper.isEnabled || helper.needsApproval },
            set: { helper.setEnabled($0) }
        )
    }

    private var helperStatusCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: helperStatusIcon)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(helperStatusTint)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(helperStatusMessage)
                .font(scheduleStatusSecondaryFont)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action = helperStatusAction {
                Button(action.title, action: action.perform)
                    .buttonStyle(.purge(.secondary, size: .small))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: helperPhase)
    }

    private var helperStatusIcon: String {
        switch helperPhase {
        case .on: return "checkmark.seal.fill"
        case .awaitingApproval, .failed: return "exclamationmark.triangle.fill"
        case .off: return "lock"
        }
    }

    private var helperStatusTint: Color {
        switch helperPhase {
        case .on: return AppColors.statusSafeText
        case .awaitingApproval, .failed: return AppColors.statusCheckText
        case .off: return AppColors.textSecondary
        }
    }

    private var helperStatusMessage: String {
        switch helperPhase {
        case .on:
            return "已开启。管理员锁定的应用无需密码即可移入废纸篓。"
        case .awaitingApproval:
            return "仍需在「系统设置」中批准。"
        case .failed:
            return "设置未完成。请再次开启以重试。"
        case .off:
            return "已关闭。首次需要时，Purge 会请求批准。"
        }
    }

    /// The one inline action the status line ever shows. Only pending approval needs a
    /// button the switch can't stand in for; every other state leaves this nil so the
    /// row keeps the same shape.
    private var helperStatusAction: (title: String, perform: () -> Void)? {
        switch helperPhase {
        case .awaitingApproval:
            return ("打开系统设置", { helper.openLoginItemsSettings() })
        case .on, .failed, .off:
            return nil
        }
    }

    private var appearanceSection: some View {
        settingsSection("外观") {
            settingsControlRow(
                title: "主题",
                caption: "选择浅色或深色外观，或跟随系统设置。"
            ) {
                appearanceOptions
            }
        }
    }

    private var appearanceOptions: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                AppearanceOptionButton(
                    mode: mode,
                    isSelected: currentAppearanceMode == mode
                ) {
                    appearanceModeRaw = mode.rawValue
                }
            }
        }
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var startupSection: some View {
        settingsSection("启动") {
            settingsToggleRow(
                title: "在菜单栏中保留 Purge",
                caption: menuBarModeCaption,
                captionAnimatesTextChanges: true,
                isOn: Binding(
                    get: { startup.showsMenuBarIcon },
                    set: { shown in
                        // A failed switch leaves the menu bar mode on and the login
                        // row showing, so the warning lands under the row at fault.
                        loginItemFailure = startup.setShowsMenuBarIcon(shown) ? nil : .disable
                    }
                )
            )

            // Both only make sense with an icon to click, so they are not offered
            // without one. Leaving the menu bar turns them off (`setShowsMenuBarIcon`).
            if startup.showsMenuBarIcon {
                Group {
                    settingsSectionDivider

                    settingsToggleRow(
                        title: "登录时启动 Purge",
                        caption: "Purge 随 Mac 启动并在菜单栏中待命。在你点击图标前不会打开窗口。",
                        warning: loginItemFailure?.message,
                        isOn: launchAtLoginBinding
                    )

                    settingsSectionDivider

                    settingsToggleRow(
                        title: "隐藏程序坞图标",
                        caption: """
                            Purge 仅从菜单栏运行。点击菜单栏图标可重新打开这个窗口。\
                            隐藏程序坞图标后应用菜单也会消失，因此 ⌘Q 不会退出。请使用菜单栏下拉菜单中的「退出」。
                            """,
                        isOn: hideDockIconBinding
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(scheduleLayoutAnimation, value: startup.showsMenuBarIcon)
    }

    private var menuBarModeCaption: String {
        startup.showsMenuBarIcon
            ? "关闭窗口后 Purge 仍会运行，你可以从菜单栏进行扫描和清理。"
            : "Purge 在你需要时打开，关闭窗口时退出。"
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { startup.launchesAtLogin },
            set: { newValue in
                loginItemFailure = startup.setLaunchesAtLogin(newValue)
                    ? nil
                    : (newValue ? .enable : .disable)
            }
        )
    }

    /// The warning outlives the attempt that caused it, so it has to go once the
    /// user has fixed things in System Settings, or it sits under a switch that
    /// now shows the state they asked for.
    private func clearLoginItemFailureIfResolved() {
        switch loginItemFailure {
        case .enable where startup.launchesAtLogin, .disable where !startup.launchesAtLogin:
            loginItemFailure = nil
        default:
            break
        }
    }

    private var hideDockIconBinding: Binding<Bool> {
        Binding(
            get: { startup.hidesDockIcon },
            set: { startup.setHidesDockIcon($0) }
        )
    }

    private var deletedAppsSection: some View {
        settingsSection("已删除的应用") {
            settingsToggleRow(
                title: "应用被删除时检查残留",
                caption: deletedAppsCaption,
                isOn: Binding(
                    get: { removedApps.isEnabled },
                    set: { removedApps.setEnabled($0) }
                )
            )

            settingsSectionDivider

            // Like the helper's, one status line that always sits here. A watcher
            // macOS blocked or that stopped misses every removal in silence, so
            // this says so, with the one action that fixes it.
            deletedAppsStatusCard
                .padding(16)
        }
        .onAppear { removedApps.refreshAgentStatus() }
    }

    private var deletedAppsCaption: String {
        """
        当应用从「应用程序」中消失时（例如在访达中拖入废纸篓），Purge 会展示它留下的文件，即使 Purge 已退出。在你确认之前不会移动任何内容。启用时，一个小的后台监控进程会保持运行；你可以随时在这里关闭它。
        """
    }

    private var deletedAppsStatusCard: some View {
        let health = removedApps.watcherHealth
        return HStack(alignment: .top, spacing: 8) {
            Group {
                if health == .checking || removedApps.isRestartingWatcher {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: deletedAppsStatusIcon(health))
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(deletedAppsStatusTint(health))
                }
            }
            .frame(width: 16, alignment: .center)
            .padding(.top, 1)
            .accessibilityHidden(true)

            Text(deletedAppsStatusMessage(health))
                .font(scheduleStatusSecondaryFont)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let fixTitle = health.fixTitle {
                Button(removedApps.isRestartingWatcher ? "正在重启…" : fixTitle) {
                    removedApps.fixWatcher()
                }
                .buttonStyle(.purge(.secondary, size: .small))
                .disabled(removedApps.isRestartingWatcher)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: health)
    }

    private func deletedAppsStatusIcon(_ health: WatcherHealth) -> String {
        switch health {
        case .running: return "checkmark.seal.fill"
        case .needsApproval, .notRunning, .failedToStart: return "exclamationmark.triangle.fill"
        case .off, .checking: return "eye.slash"
        }
    }

    private func deletedAppsStatusTint(_ health: WatcherHealth) -> Color {
        switch health {
        case .running: return AppColors.statusSafeText
        case .needsApproval, .notRunning, .failedToStart: return AppColors.statusCheckText
        case .off, .checking: return AppColors.textSecondary
        }
    }

    private func deletedAppsStatusMessage(_ health: WatcherHealth) -> String {
        switch health {
        case .off:
            return "已关闭。在 Purge 之外删除的应用不会被发现。"
        case .checking:
            return "正在检查后台监控进程。"
        case .running:
            return "已开启。Purge 正在监控被删除的应用。"
        case .notRunning:
            // A restart that does not stick means something outside Purge stops
            // the watcher, so point at the switch macOS keeps for it.
            return (health.problemMessage ?? "")
                + " 如果它再次停止，请检查「系统设置」>「登录项」中 Purge 是否已开启。"
        case .needsApproval, .failedToStart:
            return health.problemMessage ?? ""
        }
    }

    private var cleaningScheduleSection: some View {
        settingsSection("清理计划") {
            settingsToggleRow(
                title: "运行自动清理",
                caption: scheduleSummary,
                captionAnimatesTextChanges: true,
                isOn: autoCleanEnabledBinding
            )

            settingsSectionDivider

            settingsPickerRow(
                title: "频率",
                selection: frequencySelectionBinding,
                options: ScheduledCleaningFrequency.allCases,
                optionLabel: \.displayName
            )
            .disabled(!prefs.isEnabled)
            .sheet(isPresented: $showCustomIntervalSheet) {
                CustomCleaningIntervalSheet(
                    initialAmount: prefs.customIntervalAmount,
                    initialUnit: prefs.customIntervalUnit,
                    onCancel: { showCustomIntervalSheet = false },
                    onConfirm: { amount, unit in
                        prefs.customIntervalAmount = amount
                        prefs.customIntervalUnit = unit
                        prefs.frequency = .custom
                        showCustomIntervalSheet = false
                    }
                )
            }

            settingsSectionDivider

            TimelineView(.periodic(from: Date(), by: 60)) { context in
                ScheduleStatusAnimatedHeight(
                    reduceMotion: reduceMotion,
                    animation: scheduleLayoutAnimation
                ) {
                    cleaningScheduleStatusCard(referenceDate: context.date)
                }
                .padding(16)
            }

            if prefs.isEnabled && developerModeEnabled {
                settingsSectionDivider

                runScheduledCleanNowRow
            }
        }
    }

    private var updatesSection: some View {
        settingsSection("更新") {
            settingsToggleRow(
                title: "自动检查更新",
                caption: updatesSummary,
                isOn: automaticUpdateChecksBinding
            )
        }
    }

    private var updatesSummary: String {
        """
        Purge 每天检查一次，并在有新版本时显示更新窗口。未经你确认不会安装任何内容，且每次下载都会验证签名。
        """
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.setAutomaticallyChecksForUpdates($0) }
        )
    }

    /// Verification affordance: runs the real scheduled-clean pipeline now (same
    /// safe rules and staleness thresholds) so users don't have to wait out a full
    /// interval to confirm automatic cleaning works.
    private var runScheduledCleanNowRow: some View {
        settingsControlRow(
            title: "测试计划",
            caption: """
                立即运行一次计划清理以确认它正常工作。它使用上方相同的安全规则，并计入本周期的一次清理。
                """
        ) {
            runScheduledCleanNowButton
        }
    }

    private var runScheduledCleanNowButton: some View {
        Button(action: runScheduledCleanNow) {
            HStack(spacing: 6) {
                if isRunningScheduledCleanNow {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isRunningScheduledCleanNow ? "正在清理…" : "立即运行")
            }
        }
        .buttonStyle(.purge(.secondary))
        .disabled(isRunningScheduledCleanNow || store.isDeleting)
    }

    private func runScheduledCleanNow() {
        guard !isRunningScheduledCleanNow else { return }
        isRunningScheduledCleanNow = true
        Task {
            let summary = await ScheduledCleaningRegistrar.shared.runScheduledCleanNow()
            isRunningScheduledCleanNow = false
            scheduledCleanNowMessage = Self.scheduledCleanNowMessage(for: summary)
        }
    }

    private static func scheduledCleanNowMessage(
        for summary: PurgeStore.ScheduledCleaningSummary?
    ) -> String {
        guard let summary else {
            return "自动清理已关闭，因此没有运行。请先开启再重试。"
        }
        if summary.deletedCount == 0 {
            return """
            当前没有内容符合你的安全设置——计划本身是正常的，只是暂时没有可安全清理的内容。
            """
        }
        return "已将 \(summary.deletedCount) 个项目移入废纸篓，约 \(formatBytes(summary.bytesMovedToTrash))。清空废纸篓即可释放空间。"
    }

    /// Recent cleanup activity, so scheduled cleans are visible in the app instead
    /// of only in a passing notification.
    private var cleaningHistorySection: some View {
        // The only header-level control in Settings: it acts on the whole list
        // below, not on a single setting, so it can't live on a row.
        settingsSection("清理历史记录") {
            // Quiet: it sits in a section header and asks for confirmation before
            // anything happens, so it shouldn't pull the eye like a row's control.
            Button("清空历史记录") {
                showClearHistoryConfirmation = true
            }
            .buttonStyle(.purge(.quiet, size: .small))
            .disabled(history.archive.entries.isEmpty)
        } content: {
            Group {
                if displayedHistoryEntries.isEmpty {
                    Text("尚未记录任何清理。自动和手动清理会显示在这里。")
                        .font(scheduleStatusSecondaryFont)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                } else {
                    ForEach(Array(displayedHistoryEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            settingsSectionDivider
                        }
                        Button {
                            selectedHistoryEntry = entry
                        } label: {
                            CleanupHistorySummaryRow(entry: entry)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    if hasMoreHistoryEntries {
                        settingsSectionDivider

                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                isCleaningHistoryExpanded.toggle()
                            }
                        } label: {
                            cleaningHistoryExpandRow
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var displayedHistoryEntries: [CleanupHistoryEntry] {
        if isCleaningHistoryExpanded {
            history.archive.entries
        } else {
            Array(history.archive.entries.prefix(6))
        }
    }

    private var hasMoreHistoryEntries: Bool {
        history.archive.entries.count > 6
    }

    private var cleaningHistoryExpandRow: some View {
        HStack(spacing: 10) {
            Text(isCleaningHistoryExpanded ? "收起" : "显示全部")
                .font(AppStyle.Typography.body)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isCleaningHistoryExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 12)
        }
        .padding(.horizontal, 16)
        .frame(height: AppStyle.Row.compactHeight)
        .contentShape(Rectangle())
    }

    private var devToolsSection: some View {
        settingsSection("开发者项目") {
            settingsPickerRow(
                title: "视为陈旧的期限",
                caption: currentDevToolsStalenessOption.description,
                selection: devToolsStalenessSelectionBinding,
                options: DevToolsStalenessOption.allCases,
                optionLabel: \.label
            )
        }
    }

    /// Settings section for scan exclusions. Purely subtractive: un-excluding only restores
    /// eligibility when the path still passes the normal allowlist gate.
    private var excludedAppsSection: some View {
        settingsSection("从扫描中排除") {
            settingsControlRow(
                title: "已排除的路径",
                caption: "扫描会跳过这些文件和文件夹及其中的所有内容。在此添加文件夹，或右键点击任意扫描结果并选择「从扫描中排除」。"
            ) {
                Button(action: chooseFoldersToExclude) {
                    Label("添加文件夹\u{2026}", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.purge(.secondary))
            }

            let entries = excludedEntries

            if entries.isEmpty {
                settingsSectionDivider

                Text("未排除任何内容")
                    .font(scheduleStatusPrimaryFont)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(16)
            } else {
                ForEach(entries, id: \.path) { entry in
                    settingsSectionDivider

                    excludedPathRow(entry: entry)
                }

                settingsSectionDivider

                excludedTotalRow(entries: entries)
            }
        }
    }

    private var excludedEntries: [ExcludedPathEntry] {
        ExcludedPathsStore.allEntries()
    }

    private func excludedPathRow(entry: ExcludedPathEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(scheduleStatusPrimaryFont)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(entry.path)
                    .font(AppStyle.Typography.micro.weight(.regular).monospaced())
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            excludedSizeLabel(forPath: entry.path)

            Button {
                removeExclusion(entry: entry)
            } label: {
                Label("移除 \(entry.displayName)", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .imageScale(.small)
            }
            .buttonStyle(.purge(.secondary, size: .small, width: .square))
            .help("从排除列表中移除。下次扫描时 \(entry.displayName) 会重新被扫描。")
        }
        .padding(16)
        .task(id: entry.path) {
            await loadExcludedSizeIfNeeded(forPath: entry.path)
        }
    }

    @ViewBuilder
    private func excludedSizeLabel(forPath path: String) -> some View {
        switch excludedPathSizes[path] {
        case .measured(let bytes):
            excludedSizeText(formatBytes(bytes))
        case .missing:
            excludedSizeText("未找到")
        case .unmeasurable:
            excludedSizeText("无法测量")
                .help("Purge 无法读取这个文件夹来测量它。它仍会被排除。")
        case nil:
            SkeletonBar(width: 56, height: 12)
                .shimmering()
        }
    }

    private func excludedSizeText(_ text: String) -> some View {
        Text(text)
            .font(scheduleStatusSecondaryFont)
            .foregroundStyle(AppColors.textSecondary)
            .monospacedDigit()
    }

    private func excludedTotalRow(entries: [ExcludedPathEntry]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("总计")
                .font(scheduleStatusPrimaryFont)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 12)

            let total = ExcludedPathsTotal.compute(paths: entries.map(\.path), sizes: excludedPathSizes)
            if total.isComplete {
                // A folder `du` couldn't read makes the sum a floor, not a total.
                Text(total.hasUnmeasured ? "至少 \(formatBytes(total.bytes))" : formatBytes(total.bytes))
                    .font(scheduleStatusPrimaryFont)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
            } else {
                // Summing while rows still load would show a number that looks final.
                SkeletonBar(width: 72, height: 14)
                    .shimmering()
            }
        }
        .padding(16)
    }

    private func loadExcludedSizeIfNeeded(forPath path: String) async {
        guard excludedPathSizes[path] == nil else { return }
        let url = URL(fileURLWithPath: path)
        let size = await Task.detached(priority: .utility) { () -> ExcludedPathSize in
            guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
            // Not `directoryByteSize`, which reports a failed reading as 0.
            return FolderSizing.directoryByteSizeIfMeasurable(at: url).map(ExcludedPathSize.measured) ?? .unmeasurable
        }.value
        // Removed while it was measuring: writing the size back would leave a stale
        // figure that a re-add in this session would show instead of measuring again.
        guard store.excludedPaths.contains(path) else { return }
        excludedPathSizes[path] = size
    }

    /// Lets someone exclude a folder before it ever shows up in a scan, which is the
    /// usual case for an archive kept on purpose (#46). A plain panel, not a sheet:
    /// Settings can be embedded in the main window or live in its own.
    private func chooseFoldersToExclude() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "排除"
        panel.message = "Purge 不会扫描或清理你所选文件夹中的任何内容。"
        panel.begin { response in
            guard response == .OK else { return }
            store.excludeFoldersFromScans(panel.urls)
        }
    }

    private func removeExclusion(entry: ExcludedPathEntry) {
        store.removeExclusion(path: URL(fileURLWithPath: entry.path))
        excludedPathSizes.removeValue(forKey: entry.path)
    }

    // MARK: - Shared settings layout
    //
    // Every section in Settings speaks the same language: a plain headline above a
    // card, and inside the card one row per setting — title, optional caption
    // underneath, control on the trailing edge. Section headers never carry a
    // setting's own control (the only exception is Cleaning History's "Clear
    // history", which acts on the whole list rather than on one setting).

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSection(title, accessory: { EmptyView() }, content: content)
    }

    private func settingsSection<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title)
                    .font(AppStyle.Typography.headline)

                Spacer(minLength: 12)

                accessory()
            }

            settingsSectionCard(content: content)
        }
    }

    /// Title plus supporting copy, the left half of every settings row.
    private func settingsRowLabel(
        title: String,
        caption: String?,
        warning: String? = nil,
        animatesCaptionChanges: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)

            if let caption {
                Text(caption)
                    .settingsCaption()
                    .contentTransition(animatesCaptionChanges ? scheduleTextTransition : .identity)
                    .animation(animatesCaptionChanges ? scheduleTextAnimation : nil, value: caption)
            }

            if let warning {
                Text(warning)
                    .font(AppStyle.Typography.metadata)
                    .foregroundStyle(AppColors.statusCheckText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggleRow(
        title: String,
        caption: String? = nil,
        warning: String? = nil,
        captionAnimatesTextChanges: Bool = false,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            settingsRowLabel(
                title: title,
                caption: caption,
                warning: warning,
                animatesCaptionChanges: captionAnimatesTextChanges
            )
        }
        .toggleStyle(.switch)
        .tint(AppColors.statusSafeText)
        .padding(16)
    }

    private func settingsControlRow<Control: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            settingsRowLabel(title: title, caption: caption)

            control()
        }
        .padding(16)
    }

    private func settingsPickerRow<Option: Hashable>(
        title: String,
        caption: String? = nil,
        selection: Binding<Option>,
        options: [Option],
        optionLabel: @escaping (Option) -> String
    ) -> some View {
        settingsControlRow(title: title, caption: caption) {
            SettingsMenuPicker(
                selection: selection,
                options: options,
                optionLabel: optionLabel,
                accessibilityTitle: title
            )
        }
    }

    private func cleaningScheduleStatusCard(referenceDate: Date) -> some View {
        Group {
            if prefs.isEnabled {
                nextCleanStatusRow(referenceDate: referenceDate)
            } else {
                autoCleanDisabledStatus
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(scheduleStatusTransition)
        .animation(scheduleLayoutAnimation, value: prefs.isEnabled)
        .animation(scheduleLayoutAnimation, value: nextScheduledCleanDate.timeIntervalSinceReferenceDate)
    }

    private var autoCleanDisabledStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.Spacing.xSmall) {
            Text("自动清理已关闭。开启后可自动保持你的 Mac 整洁。")
                .font(scheduleStatusSecondaryFont)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("开启", action: enableAutoClean)
                .buttonStyle(.purge(.secondary, size: .small))
        }
    }

    private func nextCleanStatusRow(referenceDate: Date) -> some View {
        let isDueToday = Calendar.current.isDate(nextScheduledCleanDate, inSameDayAs: referenceDate)
        let display = nextCleanDisplay(referenceDate: referenceDate)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    scheduleStatusLabel("下次清理", showsDueDot: isDueToday)

                    Text(display.primary)
                        .font(scheduleStatusPrimaryFont)
                        .foregroundStyle(AppColors.textPrimary)
                        .contentTransition(scheduleTextTransition)
                        .animation(scheduleTextAnimation, value: display.primary)

                    if let secondary = display.secondary {
                        Text(secondary)
                            .font(scheduleStatusTertiaryFont)
                            .foregroundStyle(AppColors.textTertiary)
                            .contentTransition(scheduleTextTransition)
                            .animation(scheduleTextAnimation, value: secondary)
                    }
                }
            }

            lastCleanStatusRow(referenceDate: referenceDate)
        }
    }

    private func lastCleanStatusRow(referenceDate: Date) -> some View {
        Text(lastCleanSummaryText(referenceDate: referenceDate))
            .settingsCaption()
    }

    private func lastCleanSummaryText(referenceDate: Date) -> String {
        guard let outcome = registrar.lastOutcome else {
            return "上次清理：尚未运行过计划清理。"
        }
        let relative = relativeDateText(for: outcome.date, referenceDate: referenceDate)
        guard outcome.deletedCount > 0 else {
            return "上次清理：没有可安全清理的内容，\(relative)。"
        }
        return "上次清理：已将 \(formatBytes(outcome.bytesMovedToTrash)) 移入废纸篓，\(relative)。"
    }

    private func scheduleStatusLabel(_ title: String, showsDueDot: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(scheduleStatusLabelFont)
                .foregroundStyle(AppColors.textSecondary)

            if showsDueDot {
                Circle()
                    .fill(AppColors.textPrimary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
        }
    }

    private var settingsHorizontalContentInset: CGFloat { AppDetailPageLayout.horizontalInset }

    private var contentTopPadding: CGFloat {
        if usesExternalScrollContainer {
            // macOS 26 reserves this clearance inside the scroll-edge bar instead, so that
            // rows scrolling up dissolve below the title rather than at its baseline.
            if #available(macOS 26.0, *) { return 0 }
            return AppDetailPageLayout.clearanceBelowHeader
        }
        return showsPageHeader ? AppDetailPageLayout.topContentInset : AppStyle.Spacing.medium
    }

    private var contentBottomPadding: CGFloat {
        if usesExternalScrollContainer {
            return AppStyle.Spacing.large
        }
        return AppDetailPageLayout.verticalPadding
    }

    private var currentDevToolsStalenessOption: DevToolsStalenessOption {
        DevToolsStalenessOption(rawValue: devToolsStalenessThresholdRaw) ?? .defaultOption
    }

    private var devToolsStalenessSelectionBinding: Binding<DevToolsStalenessOption> {
        Binding(
            get: {
                DevToolsStalenessOption(rawValue: devToolsStalenessThresholdRaw) ?? .defaultOption
            },
            set: { newValue in
                devToolsStalenessThresholdRaw = newValue.rawValue
            }
        )
    }

    private var settingsSectionDivider: some View {
        InsetCardDivider()
    }

    private func settingsSectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColors.fillSecondary,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.lg, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
    }

    private var scheduleSummary: String {
        """
        每\(prefs.frequency.summaryPhrase(customAmount: prefs.customIntervalAmount, customUnit: prefs.customIntervalUnit))，我们会静默清理与「清理安全项目」按钮相同的安全项目——安全缓存和陈旧的开发产物。你的实际工作内容绝不会被删除。
        """
    }

    private var nextScheduledCleanDate: Date {
        ScheduledCleaningRegistrar.shared.nextCleanDate()
    }

    private var scheduleStatusLabelFont: Font {
        AppStyle.Typography.metadataEmphasis
    }

    private var scheduleStatusPrimaryFont: Font {
        AppStyle.Typography.body
    }

    private var scheduleStatusSecondaryFont: Font {
        AppStyle.Typography.callout
    }

    private var scheduleStatusTertiaryFont: Font {
        AppStyle.Typography.metadata
    }

    private var scheduleTextTransition: ContentTransition {
        reduceMotion ? .identity : .numericText()
    }

    private var scheduleTextAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    private var scheduleLayoutAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)
    }

    private var scheduleStatusTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .modifier(
            active: ScheduleStatusBlurTransition(blur: 8, opacity: 0),
            identity: ScheduleStatusBlurTransition(blur: 0, opacity: 1)
        )
    }

    private var autoCleanEnabledBinding: Binding<Bool> {
        Binding(
            get: { prefs.isEnabled },
            set: { newVal in
                Task { await prefs.setEnabled(newVal, animation: scheduleLayoutAnimation) }
            }
        )
    }

    /// Selecting "Custom" never writes `.custom` directly — it opens the interval
    /// popup, and `.custom` is only committed when the user saves there. Re-selecting
    /// Custom re-opens the popup with the saved values, doubling as the edit path.
    private var frequencySelectionBinding: Binding<ScheduledCleaningFrequency> {
        Binding(
            get: { prefs.frequency },
            set: { newVal in
                if newVal == .custom {
                    showCustomIntervalSheet = true
                } else {
                    prefs.frequency = newVal
                }
            }
        )
    }

    private func enableAutoClean() {
        Task { await prefs.setEnabled(true, animation: scheduleLayoutAnimation) }
    }

    /// Two complementary descriptions of the next-clean date: a prominent line and a
    /// faded supporting line. When the date is a named day (Today/Tomorrow/Yesterday)
    /// the friendly word leads and the exact date supports it; otherwise the exact
    /// date leads and the relative distance supports it. This guarantees the two
    /// lines never read the same, so a clean due today no longer shows "Today" twice.
    private func nextCleanDisplay(referenceDate: Date) -> (primary: String, secondary: String?) {
        let date = nextScheduledCleanDate
        let absolute = formattedDate(date)
        let relative = relativeDateText(for: date, referenceDate: referenceDate)

        if isNamedRelativeDay(date, referenceDate: referenceDate) {
            return (primary: relative, secondary: absolute)
        }
        return (primary: absolute, secondary: relative)
    }

    /// Whether `relativeDateText` would render `date` as Today, Tomorrow, or
    /// Yesterday relative to `referenceDate`. Mirrors that helper's calendar logic.
    private func isNamedRelativeDay(_ date: Date, referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: referenceDate) { return true }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: tomorrow) { return true }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) { return true }
        return false
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

struct SettingsMenuPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let optionLabel: (Option) -> String
    let accessibilityTitle: String
    var fillsWidth = false

    private var labelMinWidth: CGFloat { fillsWidth ? 0 : 120 }

    var body: some View {
        AppDropdown(
            options: options,
            selection: selection,
            optionLabel: optionLabel,
            onSelect: { selection = $0 }
        ) {
            HStack(spacing: 8) {
                Text(optionLabel(selection))
                    .lineLimit(1)

                Spacer(minLength: fillsWidth ? 8 : 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(minWidth: labelMinWidth)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(SettingsPickerButtonStyle())
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(optionLabel(selection))
    }
}

private struct SettingsPickerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppStyle.Typography.body)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: AppStyle.Control.height)
            .background(
                configuration.isPressed ? AppColors.fillSecondary : AppColors.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: 0.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct AppearanceOptionButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                thumbnail
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                            .strokeBorder(AppColors.borderStrong, lineWidth: 0.5)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous)
                                .inset(by: -3)
                                .strokeBorder(AppColors.textPrimary, lineWidth: 2)
                        }
                    }

                Text(mode.displayName)
                    .font(AppStyle.Typography.metadata.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(mode.displayName) 外观")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var thumbnail: some View {
        Image(mode.thumbnailAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: AppStyle.Radius.sm, style: .continuous))
    }
}

private struct ScheduleStatusBlurTransition: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private enum ScheduleStatusHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScheduleStatusAnimatedHeight<Content: View>: View {
    let reduceMotion: Bool
    let animation: Animation?
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat?

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ScheduleStatusHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(ScheduleStatusHeightKey.self) { newHeight in
                guard newHeight > 0 else { return }
                if height == nil {
                    height = newHeight
                } else if abs((height ?? 0) - newHeight) > 0.5 {
                    if let animation, !reduceMotion {
                        withAnimation(animation) {
                            height = newHeight
                        }
                    } else {
                        height = newHeight
                    }
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
    }
}

private extension ScheduledCleaningFrequency {
    func summaryPhrase(customAmount: Int, customUnit: CustomCleaningIntervalUnit) -> String {
        switch self {
        case .weekly:
            return "一周"
        case .monthly:
            return "一个月"
        case .quarterly:
            return "三个月"
        case .custom:
            return customUnit.phrase(amount: customAmount)
        }
    }

}

/// Which way a login item change failed, so the warning names the right action.
private enum LoginItemFailure {
    case enable
    case disable

    var message: String {
        switch self {
        case .enable: "无法开启。请检查「系统设置」中的「登录项」。"
        case .disable: "无法关闭。请检查「系统设置」中的「登录项」。"
        }
    }
}
