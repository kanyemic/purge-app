# Purge 简体中文版

这是开源 macOS 清理工具 [Purge](https://github.com/jithin-sabu/purge-app) 的简体中文构建，基于上游 `d726956`（v1.8.2）。

汉化只改界面文案，扫描规则、安全白名单、删除逻辑、文件匹配和持久化数据格式全部与上游保持一致。原生 Markdown 结构、代码标识与配置项未做改动，因此上游的更新可以继续合并进来。

## 快速开始

本机已有完整 Xcode 时，一条命令完成编译、签名和打包：

```bash
./scripts/build-localized.sh          # 只生成 Purge.app
./scripts/build-localized.sh --zip    # 额外生成 ZIP
./scripts/build-localized.sh --dmg    # 额外生成 DMG（需先 brew install create-dmg）
```

产物落在 `build-localized/`。脚本使用 ad-hoc 签名，不需要 Apple 开发者账号，也不做公证（notarization）。

首次打开若提示「无法验证开发者」，在 **系统设置 → 隐私与安全性** 中点击「仍要打开」，或执行：

```bash
xattr -dr com.apple.quarantine build-localized/export/Purge.app
```

未安装完整 Xcode 时脚本会在最开始就提示安装步骤，不会浪费一次完整编译。

## 汉化范围

| 位置 | 内容 |
| --- | --- |
| `purge/Resources/explanations.json` | 282 条清理规则的名称与详细说明 |
| `purge/Views/**` | 侧边栏、总览、应用缓存、开发工具、大文件、应用卸载、设置、关于及首次使用向导 |
| `purge/Menu/**` | 菜单栏面板与扫描完成通知 |
| `purge/Intents/**` | Siri / 快捷指令的标题、说明、对话与搜索关键词 |
| `purge/Models/**`、`purge/Services/**`、`purge/Utilities/**` | 安全等级、清理失败原因、扫描进度、体积对比、时间描述等界面文案 |
| `purge/ContentView.swift`、`purge/purgeApp.swift` | 确认弹窗、错误提示、菜单命令 |

### 术语对照

统一采用以下译法，跨页面保持一致：

| 英文 | 中文 |
| --- | --- |
| Safe to Clean | 可以安全清理 |
| Check First | 请先检查 |
| Safe to delete | 可以安全删除 |
| Nothing is lost | 内容不会丢失 |
| Trash | 废纸篓 |
| Full Disk Access | 完全磁盘访问权限 |
| Reveal in Finder | 在访达中显示 |
| App Caches | 应用缓存 |
| Dev Tools | 开发工具 |
| Large Files | 大文件 |
| App Uninstaller | 应用卸载 |
| Overview | 总览 |

品牌名、命令行与工具名保持英文原样（npm、npx、Docker、Xcode、Git、JetBrains、Safari、Chrome 等），以免用户照着界面输入命令时出错。

## 与上游的两处行为差异

### 自动更新已停用

上游通过 Sparkle 每天从 GitHub 拉取 Appcast，发现新版本就提示安装。中文版如果保留这个行为，会被上游英文发行版覆盖，因此这里关闭了整条更新链路：

- `purge/Info.plist`：`SUEnableAutomaticChecks` 改为 `false`，`SUFeedURL` 置空，`SUScheduledCheckInterval` 改为 `0`。
- `purge/Services/PurgeUpdater.swift`：不再启动 `SPUStandardUpdaterController`，并清除可能已存在的 `SUEnableAutomaticChecks` 偏好。

保留 `PurgeUpdater` 的公开接口（`checkForUpdates()`、`setAutomaticallyChecksForUpdates(_:)`、`automaticallyChecksForUpdates`、`canCheckForUpdates`）是为了不影响现有调用方；这些入口现在都不会真正发起网络请求。

**这意味着中文版不会自动获得上游修复。** 需要上游新版本时，用 `git fetch` 合并后再重新构建。

### App Shortcut 短语仅支持中文

`purge/Intents/PurgeAppShortcuts.swift` 里的 Siri 触发短语已整体替换为中文。中文系统下可以直接说「清理 Purge 的安全项目」这类短语；英文系统下原英文短语不再命中。需要双语支持时，在同一个 `AppShortcutsProvider` 中补回英文短语即可，两者可以并存。

## 验证

改动完成后执行的检查：

```bash
# 语法解析（只需 Command Line Tools；不等于编译通过）
swiftc -frontend -parse <改动的 .swift 文件>

# 设计 token 门禁，与 CI 相同
node scripts/lint-design-tokens.mjs

# Info.plist 合法性
plutil -lint purge/Info.plist
```

`explanations.json` 另做了不变量校验：条目数 282、`key` 顺序与上游一致、除 `display_name` 与 `explanation` 外所有字段（`tag`、`bundle_ids`、`aliases`、`scope`、`kind`、`staleness_aware`）逐字节未变。

### 已知会失败的测试

`PurgeTests/` 中有若干断言直接比对英文原文，汉化后这些断言不再成立：

| 测试文件 | 断言的英文 |
| --- | --- |
| `IntentRouterTests.swift` | `"No junk to clean right now."`、`"safe to clean"`、`"Found "`、`"Moved … of junk to the Trash."` |
| `AppUninstallScannerTests.swift` | `"Not opened"`、`"Opened "` |
| `LockedPlacesFindingsTests.swift` | `"Nothing big was hiding"`、`"still checking"` |
| `CustomCleaningIntervalTests.swift` | `"Custom"`、`"3 months"` |
| `TimeTaglineTests.swift`、`CleanFailureReasonTests.swift` | `"done in 5 seconds"` |
| `FinderRevealTests.swift` | `"Show in Finder"`、`"Copy Path"` |
| `SupportNudgeTests.swift` | `"items cleaned up, on the house."` |

这些断言检查的是展示文案而非行为，因此只影响 `xcodebuild test`，不影响应用运行。上游 CI 的 `build` 任务只执行 `lint` 与 `xcodebuild build`，不跑测试，所以云端构建不会因此失败。

要让测试重新变绿，把这些断言的字面量同步改为对应中文即可。

## GitHub Actions

本仓库保留了上游的 `.github/workflows/build.yml`，并新增 `.github/workflows/build-localized.yml`：

- 只手动触发（`workflow_dispatch`）或推送到 `localized` 分支时运行，不会因为普通 push 就消耗额度。
- 编译、校验更新确实已停用、打包出 ZIP 作为 artifact 上传。
- 不创建 Release、不推送 Appcast、不改动 Homebrew tap，也不需要任何仓库密钥。

只想本地使用的话，不需要这个工作流，直接跑 `scripts/build-localized.sh` 更省事。

## 上游文档

功能说明、安装方式、安全设计与开发指引请见上游 [README.md](README.md)（英文）。界面元素在中文版中的对应名称可参考上文的术语对照表。

## 授权

沿用上游的 [MIT License](LICENSE)，原作者为 Jithin Sabu。汉化部分同样以 MIT 协议发布。
