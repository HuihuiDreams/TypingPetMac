# 更新日志

## [Unreleased]

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

### Fixed

- 屏幕配置变化时先停止惯性滑动和指针避让，再将宠物窗口限制到当前可视区，防止运动定时器继续使用旧屏幕边界覆盖归位结果。
- 按键规则索引保留安全的图像路径，文件暂时缺失时仅返回未命中；文件恢复后无需重启或修改规则即可重新响应。

### Security

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
