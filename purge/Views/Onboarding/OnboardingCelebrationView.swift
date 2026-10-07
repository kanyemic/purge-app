import SwiftUI

struct OnboardingCelebrationView: View {
  let bytesMovedToTrash: Int64
  let onContinue: () -> Void

  @State private var animatedMovedBytes: Double = 0

  var body: some View {
    VStack(spacing: AppStyle.Spacing.large) {
      Spacer(minLength: 0)

      Image(systemName: "sparkles")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(AppColors.textPrimary)
        .symbolRenderingMode(.hierarchical)
        .accessibilityHidden(true)

      VStack(spacing: AppStyle.Spacing.small) {
        if bytesMovedToTrash > 0 {
          Text(formatBytes(Int64(animatedMovedBytes)))
            .font(AppStyle.Typography.display)
            .contentTransition(.numericText())
            .monospacedDigit()
            .accessibilityLabel("\(formatBytes(bytesMovedToTrash)) 已移入废纸篓，尚未释放")

          Text("已移入废纸篓，尚未释放")
            .font(AppStyle.Typography.sectionTitle)
            .foregroundStyle(AppColors.textSecondary)
        } else {
          Text("一切就绪")
            .font(AppStyle.Typography.displaySmall)
        }

        Text(spaceContextLine)
          .font(AppStyle.Typography.body)
          .foregroundStyle(AppColors.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, AppStyle.Spacing.xSmall)
      }
      .frame(maxWidth: OnboardingLayout.contentMaxWidth)

      Spacer(minLength: 0)

      VStack(spacing: AppStyle.Spacing.small) {
        if bytesMovedToTrash > 0 {
          Text("清空废纸篓即可释放这部分空间。")
            .font(AppStyle.Typography.callout)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
        }

        OnboardingPrimaryButton(title: "继续", action: onContinue)
      }
      .frame(maxWidth: OnboardingLayout.contentMaxWidth)
    }
    .padding(.horizontal, OnboardingLayout.horizontalPadding)
    .padding(.vertical, OnboardingLayout.verticalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.surfaceBase)
    .onAppear {
      if bytesMovedToTrash > 0 {
        withAnimation(.easeOut(duration: 0.85)) {
          animatedMovedBytes = Double(bytesMovedToTrash)
        }
      }
    }
  }

  private var spaceContextLine: String {
    guard let item = SizeComparisonCatalog.item(for: bytesMovedToTrash) else {
      return "你的 Mac 又宽松了一些。"
    }
    return "相当于 \(item.label) 的空间。"
  }
}
