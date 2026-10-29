# 更新日志

## [Unreleased]

### Added

- 新增领域模型词汇表（`GLOSSARY.md`）与架构决策记录 `ADR-002`（自研安全自动更新子系统）、`ADR-003`（统一动作包与预设映射模型）、`ADR-004`（双窗口伴生架构与非激活焦点安全不变量）。

### Changed

- 同步上游原作者更新（v0.19.2、v0.19.3）：通过重写 `NSSplitView.drawDivider`（`SettingsSplitView`）移除设置窗口侧边栏与主内容之间的竖直分割线；同步版本号至 0.19.3（Build 35）及官网发布历史相对时间格式化支持；补充代码中文注释并解决合并冲突与日志错位。
- 更新系统架构设计文档（`docs/architecture.md`）与威胁模型分析文档（`docs/TypingPetMac-threat-model.md`）至 `0.19.3`（Build 35）基准，完整覆盖自研安全自动更新子系统（ADR-002）、统一动作包模型（ADR-003）、双窗口伴生与非激活焦点安全（ADR-004）及发布管线二进制路径与密钥扫描守卫（`scripts/release.py`）。
- 在 `AGENTS.md` 中明确每次变更后的强制同步清单：同步更新 `CHANGELOG.md`（`## [Unreleased]`）、核查并同步单元测试（`Tests/TypingPetTests/*`）与独立检查脚本（`scripts/check_*.sh`），以及按需同步全局架构与安全文档。

### Fixed

- 修复 `scripts/check_todo.sh` 独立编译待办检查工具时缺失 `Sources/TypingPet/PetPreferences.swift` 源文件依赖的问题。

## [0.19.3] - 2026-10-27

### Changed

- 移除设置面板侧边栏与主内容之间的竖直分隔线（使用自定义 `SettingsSplitView` 消除侧边栏边界）。

## [0.19.2] - 2026-10-26

### Changed

- 移除设置侧边栏与内容之间的竖直分隔线并修复分割视图委托一致性。

## [0.19.1] - 2026-10-26

### Fixed

- 移除设置面板中自动更新开关下方的多余分割线。

## [0.19.0] - 2026-10-26

### Added

- 设置窗口常驻侧边栏与前进/后退导航支持，标题在滚动时常驻窗口工具栏。
- 更新说明支持五种语言（韩语、英语、日语、简体中文、繁体中文），并在发布前进行完整性校验。

### Changed

- 设置界面全面采用原生开关与分组行布局，对齐选择控件与操作按钮，统一“复制”与图集菜单按钮高度，修复新建图集弹窗小箭头居中对齐。
- 设置控件、预设选择项、活跃图集指示器及键盘高亮全面遵循 macOS 系统强调色。
- 内置图集与预设名称动态跟随当前应用语言展示，不覆写已保存数据；移除冗余的图片导入与修饰键多选提示文案。

## [0.18.2] - 2026-10-26

### Security

- 强化待办与图片存储安全边界：校验预设、休息及打字反应中的存储文件名与目录安全，拦截符号链接与非普通文件。
- 待办数据落盘使用专用权限与原子替换，强化读写文件 10 MiB 大小限制，严格限制长文本输入边界。
- 窗口失焦、锁屏或休眠时主动释放待办输入焦点，并将启动调试参数限制在 DEBUG 模式下。

## [0.18.1] - 2026-10-25

### Added

- 支持将预设图片直接拖拽至键盘按键完成绑定（悬停目标显示光晕反馈）；支持将图片文件直接拖入画廊完成导入。
- 侧边栏支持展示预设图集封面艺术图，支持双击激活图集，并提供包含使用、重命名及删除的上下文右键菜单。
- 内置图集新增默认键盘映射，并在键盘布局中将 Touch ID/电源键展示为禁用状态。
- 设置面板底部新增作者主页链接与预填充系统诊断信息的反馈邮件草稿按钮。

## [0.18.0-zh] - 2026-10-25

### Added

- 新增 `Sources/TypingPet/Resources/TypingPet.entitlements` 运行时强化权限描述文件，显式禁用 JIT、未签名可执行内存并保持库验证（Library Validation，在具备 Team ID 证书签名时生效）。
- 在 `scripts/build_app.sh` 中强制校验并传入 `--entitlements` 签名入参，并在打包完成时自动计算并输出 `dist/TypingPet-macOS.zip` 的 SHA-256 校验哈希。
- 在 `Tests/TypingPetTests/FolderImageSelectionTests.swift` 与 `Tests/TypingPetTests/KeyReactionTests.swift` 中新增 `ignoresSymlinkedImagesDuringFolderImport` 与 `rejectsSymlinkedRuleImage` 符号链接过滤与拒绝导入回归测试。
- 在 `KeyReactionTests` 中新增按键规则字典查找与物理文件恢复测试 `ruleLookupUpdatesOnRuleModificationAndPhysicalFileRestoration`，覆盖运行中删除后恢复、启动时文件缺失后恢复。
- 在 `ThumbnailCacheTests` 中新增切换激活图集时自动释放旧图集反应帧缓存测试 `activateSetInvalidatesPreviousSetReactionCache`。

### Changed

- 优化高频热路径偏好读取：在 `PetController` 内存中常驻缓存 `scale`、`restingOpacity`、`hoverOpacity`、`avoidsPointerWhenLocked` 与 `shakeLevel`，消除鼠标移动及击键事件中对 `UserDefaults` 的反复读取。
- 优化按键响应热路径：`KeyReactionStore` 建立 O(1) 字典缓存 `ruleURLsByStroke`，无规则击键直接返回 `nil`，消除每击键磁盘 `stat` 开销；`PetController` 预热缓存 `reactionPicker` 与 `reactionURLsByPath`，消除每击键临时数组与 `URL` 对象的内存分配；`showImage` 增加同路径短路，避免重复赋值。
- 按需启停鼠标悬停监控：仅在悬停与常驻透明度不同或锁定避让开启时注册全局/局部鼠标监控器，其余状态注销监控，降低 CPU/GPU 唤醒。
- 指针躲避算法预计算与短路防抖：`PetPointerAvoidance` 预计算旋转方向常量避免重复三角函数计算；避让定时器运行期间短路重复的 `targetOrigin` 冗余重算。
- 设置面板缩放滑块流畅度优化：调整缩放时直接应用无动画平滑重设，消除连续拖拽滑块时的 AppKit 阻塞式窗口动画卡顿。
- 图集切换内存卫生加固：`PetImageLibrary.activateSet` 切换不同图集时主动释放上一图集的反应图像内存缓存，防止大图集残留占用内存。
- 偏好键与默认值集中管理：在 `PetPreferences.swift` 中统一集中定义全部 30 个 `AppPreferencesKey` 常量与 `AppPreferencesDefault` 默认值，全面消除待办气泡、专注计时器、语言模式、设置外观与更新检查中的字符串字面量，由 `PetPreferencesContractTests` 全量契约守卫。
- 测试框架现代化升级：将全部 8 个遗留 `XCTest` 测试套件迁移至 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`、`#require`），消除对命令行工具中缺失的 `XCTest.framework` 依赖，使 17 个测试套件（137 个测试）在 macOS CLT 环境下全数通过。

### Fixed

- 修复 `PetImageLibrary.repairActiveSelection` 误将基于动作包（Pet Packs）动态管理的独立图集重置回内置图集的问题，增加 `!activeSet.idleFileName.isEmpty` 守卫保护。
- 修复 `TypingPetSettingsModel` 丢失 `currentPositionLock` 闭包导致设置面板与主窗口锁定状态同步断裂的问题。
- 修复 `PetPackTests` 仍引用不存在的旧版 `pet-left.png`/`pet-idle.png` 文件名及预设 5 个表情数量导致测试失败的问题。
- 屏幕配置变化时先停止惯性滑动和指针避让，再将宠物窗口限制到当前可视区，防止运动定时器继续使用旧屏幕边界覆盖归位结果。
- 按键规则索引保留安全的图像路径，文件暂时缺失时仅返回未命中；文件恢复后无需重启或修改规则即可重新响应。

### Security

- 修复 `PetImageLibrary.presetImageURL` 回退分支与 `storageDirectory(for:)` 缺失 `StoredFileName.isSafe` 校验的问题，防止被篡改的图集配置越出存储目录读写文件。
- 加固待办与文本输入边界：`TodoTitlePolicy` 在切分换行与空白前先做 $O(1)$ 长度截断，并在自定义倒计时、新建图集及重命名预设输入框统一接入长度与换行限制，防止超大剪贴板粘贴造成主线程卡顿。
- 加固 `TodoFileStorage` 与 `TodoState.validate()`：落盘 `todo-state.json` 时显式设置 `0600` 权限，加载时拦截符号链接与超大文件，并校验待办标题不含换行符且不超过长度上限。
- 加固 `TodoBubbleWindowController` 非激活悬浮面板焦点释放：在窗口失去 Key 状态、全局外部鼠标点击、系统休眠或锁屏时主动释放 `firstResponder`，防止用户在其他应用或解锁时的输入误落入待办输入框。
- 将 `AppDelegate` 中的 `--show-settings` 启动参数收敛至 `#if DEBUG` 编译块内。
- 强化图库与规则导入安全：`PetImageLibrary.addSet`、`copyImage` 与 `KeyReactionStore.setRule` 统一采用 Fail-Closed 校验（要求 `isSymbolicLink == false && isRegularFile == true`），过滤并拦截符号链接及非普通文件，防御跨目录软链接穿透风险。
- 完善分发安全指引：在 `README.md` 与 `README.txt` 中增加基于 `shasum -a 256` 的文件完整性校验指引，提供源码本地构建指引，并将“绝对安全”文案优化为诚实、可技术验证的零网络离线运行与纯按键码响应承诺。
- 建立威胁模型分析文档（`docs/TypingPetMac-threat-model.md`），系统梳理 macOS `ListenEvent` 权限、无网络离线边界与分发安全加固策略。

## [0.12.2] - 2026-10-16

### Added

- 在 `Info.plist` 中添加 `NSInputMonitoringUsageDescription` 权限用途描述文案，明确提示输入监控用于实时响应按键切换互动表情。
- 扩充 `PetPreferencesContractTests`，新增 `preferencesKeysAndDefaultsAreConsistent` 契约测试，断言全部 13 个 `AppPreferencesKey` 常量唯一非空，且 `AppPreferencesDefault` 缩放范围、抖动等级及透明度默认值与边界符合约束。
- 在 `KeyReactionTests` 中新增修饰键前缀顺序（`⌃⌥⇧⌘`）与 `F1`/`F2`/`F4` 功能键名称格式化测试。
- 在 `PetWindowGeometryTests` 中新增指针躲避死角边界回归测试 `pointerAvoidanceReturnsNilWhenPinnedInCornerCannotMoveFurther`。

### Fixed

- 修复指针躲避在屏幕角落被逼停且鼠标在 90pt 范围内静止时，`targetOrigin` 仍返回当前原点导致 60 FPS 无限空转的问题。
- 修复 `GlobalKeyMonitor.isRunning` 仅判断指针非空导致 Mach Port 失效后报告假阳性无法自动恢复的问题；并在 `AppDelegate` 监听系统唤醒通知实现自动重连。
- 修复 `InputMonitoringGuide` 引导窗每 0.6s 轮询强行重置坐标、覆盖用户手动拖动位置的问题，改为仅在系统设置窗口首次出现或发生位移时平滑跟随；Timer 改为弱引用并在 `deinit` 安全释放。
- 修复 `SettingsWindow` 缺少 `window.isReleasedWhenClosed = false` 导致关闭后重开可能失效的隐患。
- 修复按键录制弹窗在空白处点击后失去键盘焦点且难以找回的问题；补充 `F1` (122)、`F2` (120)、`F4` (118) 功能键名称映射。
- 修复 `FolderImageSelectionTests` 中直接使用 `"customIdleImageFile"` 与 `"customReactionImageFiles"` 字符串字面量的问题，改为统一引用 `AppPreferencesKey` 集中定义。
- 修复 `scripts/notarize_release.sh` 在执行代码签名校验前缺少 `.app` 目录存在性判断的问题。
- 统一 `scripts/notarize_release.sh` 归档输出文件名与打包格式：默认生成 `dist/TypingPet-macOS.zip` 并同步打包 `README.txt`，与 `build_app.sh` 保持一致。
- 修复自定义图集磁盘文件丢失时没有自愈回退到默认图集的问题；修复单图文件夹导入时物理重复复制同一份图片的问题；修复 `catch` 回滚删除失败掩盖原始格式错误的问题。

### Changed

- 版本号提升至 `0.12.2` (Build 19)。
- 清理 `AppDelegate.swift` 中旧版状态栏菜单残留的 14 个未使用的私有动作与辅助方法，文件从 410 行精简至 298 行。
- 优化 `SettingsWindow.swift` 表单布局与视图层级，代码行数从 649 行压缩至 627 行，严格满足 ADR-001 规定的 650 行上限。
- 优化 `InputMonitoringGuide` 与 `AppDelegate` 轮询定时器的 `tolerance` 容差，降低系统后台能耗。
- 更新系统架构设计文档（`docs/architecture.md`），明确 `AppKit + SwiftUI` 与 `NSHostingController` 承载结构，并在根目录索引中补齐 `README.txt` 与 `LICENSE`。

## [0.12.1] - 2026-10-13

### Added

- 新增 15 个回归用例，覆盖图集迁移与替换、部分复制失败清理、删除重试、按键规则失败处理及设置状态同步。
- 打包脚本 (`scripts/build_app.sh`) 末尾增加自动打包分发压缩包步骤，生成包含 `TypingPet.app` 与 `README.txt` 的 `dist/TypingPet-macOS.zip`。

### Fixed

- 修复旧版图集替换待机或反应图像后，另一组图像因存储目录变化而失效的问题。
- 替换图集图像时清理旧文件并使旧缓存失效；删除旧版图集时清理应用内部的孤立文件，保留用户源图像。
- 图集导入、图像替换或按键规则复制失败时清理新副本，避免留下未登记的文件或意外切换当前图集。
- 图集及按键规则删除失败时报告错误并保留记录；覆盖按键规则时，旧文件清理失败会保留原规则并清理新副本。
- 设置窗口刷新时读取宠物控制器的实际位置锁定状态，保持菜单栏与设置开关一致。

### Changed

- 宠物显示复用图像缓存，反应图像列表仅在初始化或重新加载图集时解析，减少击键路径中的重复图像加载和文件检查。
- 同步架构文档中的存储、缓存与测试说明，并修正两份 README 中待机图文件名的匹配规则。

## 0.12.0 - 2026-10-10

- 全面支持简体中文界面：汉化菜单栏、设置窗口、权限引导及系统提示文案。
- 将代码库核心注释与文档翻译为中文。
- 更新内置默认桌宠素材为《人渣反派自救系统》七九 CP（岳清源 × 沈清秋，basic / left / right），素材由画师“-烤得很香的狗蛋-”（LOFTER ID: guduxiaolangnaibu）绘制；图库导入规则支持将 `basic` 识别为待机图。
- 完善中文使用说明、分发指南与版权协议（README.md、README.txt 与 ASSET_LICENSE.md），补充对原项目作者（Jongkeun Choi / @ynifamily3）及默认素材画师的致谢与来源标注。
- 性能与能耗优化：在透明度更新中增加差值守卫，阻断无差异高频 CoreAnimation 事务提交；将权限引导窗口轮询放宽至 0.6 秒以节省电量。
- 磁盘卫生与文件管理：删除图集时物理同步删除磁盘目录；删除或覆盖按键反应规则时清理旧孤立图像文件。
- 内存与响应速度优化：为图集与待机图引入基于 `NSCache` 的内存缓存机制，并在图像变动时自动失效。
- 隐私与健壮性防护：修复 Release 二进制中的本地路径泄漏（`#filePath` 仅在 DEBUG 模式下作为开发回退），消除不安全的强制解包。
- 架构解耦与重构：集中收敛 UserDefaults 配置键 (`PetPreferences`)，彻底消除 `PetImageLibrary` 与 `KeyReactionStore` 的本地重复键；在 `GlobalKeyMonitor` 销毁与注销时显式失效 MachPort；为按键弹跳动画添加安全越界守卫；将 1397 行的巨石 `main.swift` 拆解为 `PetViews`, `GlobalKeyMonitor`, `PetController`, `AppDelegate` 与 11 行极简启动入口，并新增 ADR-001 决策记录。
- 现代测试迁移：将单元测试全面迁移至原生 Swift Testing 框架，新增磁盘物理清理、缓存失效生命周期以及首选项存储契约 (`PetPreferencesContractTests`) 测试套件。

## 0.19.3 - 2026-10-27

- Remove the visible vertical divider between the Settings sidebar and main content.

## 0.19.2 - 2026-10-26

- Remove the visible divider line between the Settings sidebar and its content.

## 0.19.1 - 2026-10-26

- Remove the extra divider below the automatic update switch in Settings.

## 0.19.0 - 2026-10-26

- Keep the Settings sidebar visible and add Back/Forward navigation with a title that stays in place while scrolling.
- Use native switches and grouped settings rows. Align selection controls and action buttons, match Duplicate and set-menu button heights, and fix the New Set popover arrow.
- Follow the macOS accent color for controls, preset selections, active-set indicators, and keyboard highlights.
- Display the built-in set and preset names in the selected app language without rewriting saved data or translating custom names. Remove redundant image-import and modifier-selection hints.
- Support update release notes in Korean, English, Japanese, Simplified Chinese, and Traditional Chinese, with English and legacy-feed fallbacks. Validate all translations before publishing.

## 0.18.2 - 2026-10-26

- Validate stored image filenames and set folders across preset, resting, and typing-reaction lookups; reject symbolic links and non-regular files when importing images.
- Save Todo records with owner-only permissions before atomically replacing the original. Permission or write failures preserve the previous records, and reads and writes enforce a 10 MiB file limit.
- Bound long text input before processing and reject invalid stored Todo titles.
- Release Todo input focus when clicking another app, locking the screen, or sleeping, and limit the settings launch shortcut to debug builds.

Thanks to @HuihuiDreams for contributing the input and storage hardening in #5.

## 0.18.1 - 2026-10-25

- Drag preset images onto keyboard keys to assign them, with a glow on the active drop target; drop image files into the gallery to import them.
- Improve set management with preset artwork in the sidebar, double-click activation, and a context menu for using, renaming, and deleting sets. Deleting the active set switches to the set above it.
- Add default keyboard mappings for the built-in set and show the Touch ID/power button as a disabled key.
- Add creator links and a support email draft with basic system details to the Settings footer, alongside the app version and DEV/production badge.
- Refine preset cards, hover feedback, and the update-check settings copy.

## 0.18.0 - 2026-10-25

- Redesign Settings with a native, resizable sidebar and a single page for each set's image presets and keyboard mappings.
- Create empty named sets, duplicate existing sets with independent image copies, and save edits automatically. Keep built-in image presets fixed; duplicate the set to customize them.
- Assign multiple presets to individual keys and modifier combinations, with random or sequential playback and separate typing and resting selections.
- Keep preset selection popovers open while editing and anchor their tails to the selected key. Add modifier checkboxes and Space/Enter shortcuts.
- Center the keyboard with square character keys, hover feedback, and an inverted-T arrow cluster; preserve its proportions in narrow windows with horizontal scrolling.
- Show Input Monitoring authorization and connection status in General settings.

## 0.17.1 - 2026-10-24

- Clarify app and website copy in Korean, English, Japanese, Simplified Chinese, and Traditional Chinese.
- Use consistent names for Todo views and reaction images, clarify opacity settings, and split long setup descriptions.
- Distinguish the Pause action from the Paused status and use consistent timer-ending labels.

## 0.17.0 - 2026-10-24

- Add Japanese, Simplified Chinese, and Traditional Chinese throughout the app, alongside Korean and English.
- Detect Japanese and Chinese system languages, honoring explicit Chinese scripts and regional defaults, and allow a saved language override in Settings.
- Localize the website, installation guides, FAQs, release notes, accessibility labels, and search and social metadata in all five languages.
- Keep the current website page and anchor when switching languages, and remember the choice for future visits.

## 0.16.0 - 2026-10-24

- Keep Settings at a compact 490-point default width, with room to grow for larger accessibility text and manual resizing.
- Add System, Korean, and English language choices in Settings. Follow the first system language by default, using English for languages other than Korean.
- Maintain Korean and English interface strings in separate localization files, including Settings, menus, Todo bubbles, Input Monitoring guidance, and update messages.
- Apply the saved System, Light, or Dark appearance to both Settings and Todo bubbles, including the collapsed entry button.

## 0.15.0 - 2026-10-24

- Let users try pet key reactions inside the welcome window before requesting Input Monitoring permission.
- Guide users through enabling the permission switch, with optional drag-and-drop help when the app is missing from the list.
- Confirm a real global key event before completing setup, and resume verification after a required app relaunch.
- Add a gear button immediately to the left of the pet's resize handle on hover to open Settings.
- Publish the signed and notarized Apple Silicon app through the ynifamily3/tap Homebrew cask alongside GitHub and automatic updates.
- Add guarded release automation for testing, signing, notarization, update-server deployment, and Homebrew publication.

## 0.14.3 - 2026-10-24

- Add System, Light, and Dark appearance choices for the Settings window, with an immediate preview and a saved preference.
- Keep the pet and Todo bubble appearance independent of the Settings window choice.

## 0.14.2 - 2026-10-24

- Publish the production update feed and verify release archives with the app's Ed25519 key, Developer ID signature, and Apple notarization.
- Replace the lost update signing key. Builds through 0.14.1 cannot update automatically to 0.14.2; install this release manually once. Later releases can use automatic update checks.
- Add a single-command, guarded update deployment that publishes the archive before atomically replacing the feed.

## 0.14.1 - 2026-10-24

- Release the existing 0.14.0 features with an Apple-issued Developer ID Application signature and Apple notarization.
- Keep the production update public key from 0.14.0 so existing installations continue to trust future updates signed with the original private key.
- Existing ad-hoc installations may need Input Monitoring permission granted again when switching to this Developer ID-signed build.

## 0.14.0 - 2026-10-23

- Add a compact view for a Todo bubble that stays open: up to three open Todos, one line each with checkboxes, and `+N 个更多` to open the full view.
- Switch views from the bubble header, the hover button, the context menu, or Settings > `待办事项` > `列表视图`. The choice persists across relaunches.
- Right-click a compact row to pause, resume, or stop its timer, or start it with its saved setting, count-up, or 20 minutes.
- Keep the compact view when a timer starts from it. Endings and absences show their own bubble until answered, then the compact view returns.

## 0.13.0 - 2026-10-23

- Check for updates once a day and from the menu bar or the General settings tab.
- Install an update after you accept it, then restart. A later quit installs an accepted update.
- Verify each update with SHA-256, an Ed25519 signature, the bundle identity, and the Developer ID Team ID.
- Restore the previous app when the swap fails, and report the result on the next launch.
- Ad-hoc builds update with the Ed25519 signature alone. Grant Input Monitoring again after each update until builds are Developer ID signed.

## 0.12.0 - 2026-10-21

- Add a Todo speech bubble beside the pet with a per-Todo countdown or count-up focus timer and measured session time.
- Edit Todo titles in place, zoom the bubble from 80% to 200%, and show it always or only on hover.
- Pause a running timer after a configurable idle period, on screen lock, or on sleep, then ask how to treat the time away.
- Bounce the bubble like a Dock icon when a countdown ends or a missed notice is waiting.
- Build local development copies as a separate TypingPet Dev app with its own settings, images, and Todo records.

## 0.11.2 - 2026-09-27

- 将权限引导窗口中的 Finder 快捷方式替换为重新打开“输入监控”设置的醒目按钮。
- 在菜单栏、设置窗口和浮动引导窗口之间统一共用相同的“输入监控”跳转链接。

## 0.11.1 - 2026-09-27

- 让“输入监控”引导窗口保持在常规应用窗口上方（置顶显示）。
- 无需申请辅助功能（Accessibility）权限即可自动跟随已打开的“系统设置”窗口。
- 优先吸附排列在“系统设置”窗口旁边，并在空间受限时保持在可视屏幕区域内。

## 0.11.0 - 2026-09-27

- 添加用于授予“输入监控”权限的浮动引导窗口。
- 支持将真实的 `TypingPet.app` 图标直接拖拽到系统权限列表中。
- 自动检测权限变更，并在授予访问权限后自动关闭引导窗口。
- 当应用位于 Applications 文件夹外部时发出警告，并提供在 Finder 中定位及手动选择的后备方案。

## 0.10.0 - 2026-09-27

- 精简菜单栏菜单，仅保留核心的宠物显示、位置、权限、开机自启和退出操作。
- 菜单展开时以绿色或红色直观显示按键输入监控是否可用。

## 0.9.1 - 2026-09-25

- 在宠物的缩放把手上显示原生对角线框架缩放光标。
- 添加“拖拽以调整大小”的提示信息与辅助功能说明，提升控件易用性。

## 0.9.0 - 2026-09-25

- 所有设置标签页统一采用 4 点网格标准间距规范。
- 使用扁平分块与对齐行替换原有的嵌套分组表单。
- 统一图库卡片、操作按钮组、空白状态以及窗口边距样式。

## 0.8.1 - 2026-09-25

- 在空间充裕时，让指针避让更偏向灵动的对角线逃跑路径。
- 围绕直线逃逸向量旋转采样，并保留屏幕边缘自适应的后备行为。

## 0.8.0 - 2026-09-25

- 为点击穿透位置锁定模式添加可选的指针避让功能。
- 在保持处于当前显示器范围内的同时，以阻尼弹簧运动平滑远离光标。
- 当最近的屏幕边缘阻挡移动时，自动选取备选逃逸方向。

## 0.7.0 - 2026-09-25

- 使用可配置的常驻与悬停不透明度设置替代基于距离的渐变透明。
- 默认设置为常驻 100% 不透明度与悬停 30% 不透明度。
- 光标进入与离开悬停状态时不透明度立即生效，无需过渡延迟。

## 0.6.0 - 2026-09-25

- 根据指针接近程度平滑淡化宠物图像，悬停时降至 30% 不透明度。
- 宠物图像淡化时，保持隐藏与缩放控件完全清晰可见。

## 0.5.1 - 2026-09-25

- 将图像层锚点居中，使悬停与按下的弹簧缩放效果围绕宠物中心点缩放。

## 0.5.0 - 2026-09-25

- 添加基于速度的拖拽惯性，具备平滑摩擦力衰减与屏幕边缘边界碰撞反弹。
- 添加富有弹性的悬停放大及按下拖动时的微缩反馈。

## 0.4.0 - 2026-09-25

- 悬停时显示用于隐藏和缩放宠物的控制控件。
- 支持右上角等比缩放，并与设置窗口中的尺寸数值保持同步。
- 关闭控件仅隐藏宠物本体，菜单栏应用与按键监听继续在后台运行。
- 添加用于重新显示已隐藏宠物的菜单项。

## 0.3.0 - 2026-09-25

- 添加包含通用、图库和按键反应标签页的独立设置窗口。
- 支持多套可复用的图库图像集，并从早期的单图像集格式平滑迁移。
- 支持精确匹配特定按键及修饰键组合的专用反应图像。
- 添加四档按键弹跳幅度等级。
- 添加原创的 CC0 协议键盘猫咪占位图像集与应用图标。
- 添加支持 Developer ID 签名的编译构建与公证脚本。
