import SwiftUI

/// Popup shown when "Custom" is picked in the Cleaning Schedule frequency menu.
/// Lets the user set their own repeat interval as a number plus a unit
/// (days / weeks / months). Values are committed through `onConfirm` only when
/// the user saves, so canceling never leaves a half-configured schedule.
struct CustomCleaningIntervalSheet: View {
    let initialAmount: Int
    let initialUnit: CustomCleaningIntervalUnit
    let onCancel: () -> Void
    let onConfirm: (Int, CustomCleaningIntervalUnit) -> Void

    @State private var amountText: String
    @State private var unit: CustomCleaningIntervalUnit
    @FocusState private var amountFieldFocused: Bool

    init(
        initialAmount: Int,
        initialUnit: CustomCleaningIntervalUnit,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Int, CustomCleaningIntervalUnit) -> Void
    ) {
        self.initialAmount = initialAmount
        self.initialUnit = initialUnit
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _amountText = State(initialValue: String(initialAmount))
        _unit = State(initialValue: initialUnit)
    }

    private var parsedAmount: Int? {
        guard
            let amount = Int(amountText.trimmingCharacters(in: .whitespaces)),
            amount >= 1,
            amount <= ScheduledCleaningPreferenceStore.customIntervalAmountLimit
        else { return nil }
        return amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.large) {
            VStack(alignment: .leading, spacing: AppStyle.Spacing.xSmall) {
                Text("自定义清理计划")
                    .font(AppStyle.Typography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("选择你自己的间隔。Purge 会按这个节奏静默清理同样的安全项目。")
                    .font(AppStyle.Typography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppStyle.Spacing.small) {
                TextField("", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(AppStyle.Typography.body.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .focused($amountFieldFocused)
                    .frame(width: 34)
                    .padding(.horizontal, 8)
                    .frame(height: AppStyle.Control.height)
                    .background(
                        AppColors.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppStyle.Radius.md, style: .continuous)
                            .strokeBorder(
                                amountFieldFocused ? AppColors.textPrimary : AppColors.borderSubtle,
                                lineWidth: amountFieldFocused ? 1 : 0.5
                            )
                    }
                    .accessibilityLabel("每")

                SettingsMenuPicker(
                    selection: $unit,
                    options: CustomCleaningIntervalUnit.allCases,
                    optionLabel: { $0.displayName },
                    accessibilityTitle: "单位"
                )

                Spacer()
            }

            footer
        }
        .padding(AppStyle.Spacing.large)
        .frame(minWidth: 420)
        .background(AppColors.surfaceBase)
        // Clicking anywhere off the field drops its focus ring.
        .contentShape(Rectangle())
        .onTapGesture { amountFieldFocused = false }
        // Don't grab focus (and auto-select the number) when the sheet opens.
        // The sheet assigns first responder after onAppear, so clear it on the
        // next runloop tick to land after that assignment.
        .onAppear {
            DispatchQueue.main.async { amountFieldFocused = false }
        }
    }

    private var footer: some View {
        HStack(spacing: AppStyle.Spacing.small) {
            Text("每 \(intervalPhrase)")
                .font(AppStyle.Typography.metadataEmphasis)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Button("取消", action: onCancel)
                .buttonStyle(.purge(.secondary))
                .keyboardShortcut(.cancelAction)

            Button("存储") {
                if let amount = parsedAmount {
                    onConfirm(amount, unit)
                }
            }
            .buttonStyle(.purge(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(parsedAmount == nil)
        }
    }

    private var intervalPhrase: String {
        guard let amount = parsedAmount else { return "…" }
        return unit.phrase(amount: amount)
    }
}
