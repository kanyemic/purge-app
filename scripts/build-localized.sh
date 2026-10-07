#!/usr/bin/env bash
# 汉化版本地构建脚本。
#
# 用途：在本机把 Purge 汉化版编译成可运行的 Purge.app，并可选打包成 ZIP / DMG。
# 与上游 scripts/make-dmg.sh 的区别：本脚本不要求 Apple 开发者账号，
# 不做公证（notarize），使用临时的 ad-hoc 签名，产物仅供自用。
#
# 用法：
#   ./scripts/build-localized.sh              # 只编译并导出 Purge.app
#   ./scripts/build-localized.sh --zip        # 额外生成 ZIP
#   ./scripts/build-localized.sh --dmg        # 额外生成 DMG（需要 create-dmg）
#   ./scripts/build-localized.sh --zip --dmg  # 两者都生成
#
# 前置条件：
#   - 已安装完整 Xcode.app（不能只有 Command Line Tools），并能执行 xcodebuild
#   - 可选：brew install create-dmg（仅 --dmg 需要）
#
# 产物默认落在 ./build-localized/。

set -euo pipefail

ZIP=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    --zip) ZIP=1 ;;
    --dmg) DMG=1 ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "未知参数：$arg" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT_DIR="$REPO_ROOT/build-localized"
ARCHIVE_PATH="$OUT_DIR/Purge.xcarchive"
EXPORT_DIR="$OUT_DIR/export"
APP="$EXPORT_DIR/Purge.app"

# 先确认真的是完整 Xcode，而不是 Command Line Tools。
# 只装了 CLT 时 xcodebuild 会先报 "requires Xcode"，但错误信息出现得较晚，
# 这里提前失败，避免浪费一次完整编译时间。
DEV_DIR="$(xcode-select -p || true)"
if [[ "$DEV_DIR" != *".app/Contents/Developer"* ]]; then
  cat >&2 <<EOF
当前活动的开发者目录不是完整 Xcode：

  $DEV_DIR

Purge 是多 target 的 SwiftUI 应用，还依赖 Swift Package（Sparkle），
仅凭 Command Line Tools 无法编译。请先安装完整 Xcode：

  1. 从 App Store 或 https://developer.apple.com/download/all/ 安装 Xcode
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. sudo xcodebuild -license accept

安装后重新运行本脚本即可。
EOF
  exit 1
fi

command -v xcodebuild >/dev/null || { echo "找不到 xcodebuild。" >&2; exit 1; }

echo "==> 机器信息"
xcodebuild -version
sw_vers

# 每次构建都清掉旧产物，避免残留的 archive 误导后续步骤。
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> 解析 Swift Package 依赖（Sparkle）"
xcodebuild -resolvePackageDependencies \
  -project purge.xcodeproj \
  -scheme purge

echo "==> 编译并归档（Release）"
# CODE_SIGN_IDENTITY="-" 表示 ad-hoc 签名：本机可以正常启动，但分发到其他
# 机器会被 Gatekeeper 拦下。自行分发时对方需要右键打开或在“系统设置 >
# 隐私与安全性”里放行。
xcodebuild archive \
  -project purge.xcodeproj \
  -scheme purge \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO

echo "==> 导出 Purge.app"
# 用 -exportArchive 而不是直接拷 archive 里的 .app：这样能保证
# Helper / Watch 这些内嵌 target 的相对结构与 Info.plist 都被正确处理。
EXPORT_PLIST="$OUT_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>mac-application</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>-</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
</dict>
</plist>
PLIST

mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates || {
    echo "==> 导出失败，退回到直接使用 archive 内的 .app"
    APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/Purge.app"
    [ -d "$APP_IN_ARCHIVE" ] || { echo "archive 里也没有 Purge.app，构建失败。" >&2; exit 1; }
    cp -R "$APP_IN_ARCHIVE" "$APP"
  }

[ -d "$APP" ] || { echo "没有生成 Purge.app。" >&2; exit 1; }

echo "==> 重新为嵌入框架与主程序注入 ad-hoc 签名及库验证放行"
# 在 ad-hoc 签名下，主程序与 Sparkle 均无统一 Team ID。macOS dyld 会因为
# Library Validation 阻止加载 Sparkle.framework 从而触发 EXC_CRASH。
# 必须先对 Frameworks 进行 deep 签名，再对主程序注入 disable-library-validation entitlements。
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -type d -name "*.framework" -exec codesign --force --deep -s - {} +
fi
codesign --force -s - --entitlements "$REPO_ROOT/scripts/adhoc.entitlements" "$APP"

echo "==> 校验产物"
INFO_PLIST="$APP/Contents/Info.plist"
# 用 plutil 而不是 defaults read：defaults 对含空格的相对路径不可靠，
# 且读布尔时会归一化成 0/1，plutil raw 保留原语义。
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
echo "    Purge.app 版本：$VERSION（build $BUILD）"
echo "    自动更新开关：$(plutil -extract SUEnableAutomaticChecks raw -o - "$INFO_PLIST" 2>/dev/null || echo '未设置')"
echo "    更新源：$(plutil -extract SUFeedURL raw -o - "$INFO_PLIST" 2>/dev/null | sed 's/^$/<空，已停用>/')"

# ad-hoc 签名在 --deep 校验下应当是有效的；失败说明内嵌 target 没签好。
codesign --verify --deep --strict "$APP" && echo "    签名校验：通过（ad-hoc）"

RESULT="$APP"

if [[ $ZIP -eq 1 ]]; then
  ZIP_PATH="$OUT_DIR/Purge-汉化版-$VERSION.zip"
  echo "==> 打包 ZIP"
  # ditto 会保留扩展属性与符号链接，比 zip 更适合 .app。
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
  echo "    $ZIP_PATH"
  RESULT="$RESULT
$ZIP_PATH"
fi

if [[ $DMG -eq 1 ]]; then
  if ! command -v create-dmg >/dev/null; then
    echo "==> 跳过 DMG：未安装 create-dmg（brew install create-dmg）" >&2
  else
    DMG_PATH="$OUT_DIR/Purge-汉化版-$VERSION.dmg"
    echo "==> 打包 DMG"
    STAGING="$(mktemp -d)/staging"
    mkdir -p "$STAGING"
    cp -R "$APP" "$STAGING/"
    rm -f "$DMG_PATH"
    create-dmg \
      --volname "Purge" \
      --volicon "$REPO_ROOT/Assets/dmg/VolumeIcon.icns" \
      --background "$REPO_ROOT/Assets/dmg/dmg_bg.png" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --text-size 16 \
      --icon "Purge.app" 175 192 \
      --app-drop-link 425 192 \
      "$DMG_PATH" "$STAGING"
    echo "    $DMG_PATH"
    RESULT="$RESULT
$DMG_PATH"
  fi
fi

echo
echo "==> 完成，产物："
echo "$RESULT"
echo
echo "首次打开若提示“无法验证开发者”，在 系统设置 > 隐私与安全性 中点击“仍要打开”，"
echo "或执行：xattr -dr com.apple.quarantine \"$APP\""
