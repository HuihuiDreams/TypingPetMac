# 本地开发 (Local Development)

本地构建默认使用开发环境配置（Development profile）。开发版与正式安装的生产版应用可同时共存运行。

| 配置项 | 开发版 (Development) | 生产版 (Production) |
|---|---|---|
| 应用名称 | TypingPet Dev | Typing Pet |
| Bundle 包名 | TypingPet Dev.app | TypingPet.app |
| 可执行文件名 | TypingPetDev | TypingPet |
| Bundle Identifier | ing.miel.typingpet.dev | ing.miel.typingpet |
| 偏好设置域 | ing.miel.typingpet.dev.preferences | ing.miel.typingpet |
| Application Support 目录 | TypingPetDev | TypingPet |
| 菜单栏图标 | 烧瓶图标与 DEV 字样 | 爪印图标 |

开发版将待办事项、图片套组、按键反应图片、偏好设置和保存的窗口坐标完全隔离。
它从独立的空数据目录启动，不迁移或拷贝正式版数据。
输入监控权限同样归属于独立的开发版应用。
权限引导界面明确显示 `TypingPet Dev.app`。

## 构建与运行

在仓库根目录下执行：

```sh
./scripts/run_dev.sh
```

该脚本会在 `dist-dev/TypingPet Dev.app` 生成 Debug 应用包，进行本地临时代码签名并启动待办列表。
如果需要测试全局按键响应，请在系统设置中为 **TypingPet Dev** 授予输入监控权限。
开发版在启动时不会强制弹出阻断式的系统权限弹窗。
当您需要测试全局按键反应时，可在 DEV 菜单 > 输入监控设置 中开启。
您可以先在应用内体验待办事项 UI。
本机已安装的生产版无需退出。

### 输入监控引导测试

如需在 Debug 构建中测试全新的权限引导流程，请先退出 Dev，然后执行：

```sh
open "dist-dev/TypingPet Dev.app" --args --show-input-guide
```

欢迎卡片仅在预览区域获得键盘焦点时接收按键事件。
它会直接播放当前宠物的动作图片，无需申请输入监控权限，也不会记录输入的文本内容。
按 Tab 和 Shift-Tab 可以跳出预览区域，确保设置按钮支持全键盘访问。
仅当用户点击 **在其他应用中也响应** 时，才会真正请求系统权限。
引导窗口贴合 macOS 系统设置界面，指导用户优先开启列表中的开关，并在 **不在列表中？** 折叠项下展示可拖拽的应用图标。

系统授予权限且底层 event tap 成功连接后，引导窗口进入等待真实全局击键的阶段。
只有收到真实的全局键盘事件才能完成引导闭环；本地输入框内的按键无法完成该步骤。
如果 macOS 要求“退出并重新打开应用”，请按系统提示操作。连接排错指引提供重试按钮并说明如何退出重开。
应用本体与单元测试不会越权自发授予权限。
如果 macOS 在授权过程中自动终止了应用，正式版在重新启动后会自动恢复验证步骤。
点击引导窗口的 **稍后** 或关闭按钮，可取消自动恢复。

如需在不触发真实系统权限请求的情况下进行纯视觉 UI 审查，Debug 构建支持通过参数预览各个阶段：
`--input-guide-preview preview`、`permission`、`verifying`、`connectionFailed` 或 `complete`：

```sh
open "dist-dev/TypingPet Dev.app" --args --input-guide-preview permission
```

这些屏幕使用模拟的权限与连接状态，不验证真实的全局输入。

生产版在输入监控不可用时仅展示一次欢迎指引。点击 **稍后** 可正常使用无全局反应的基础功能，之后可通过菜单栏的输入监控项或设置随时恢复引导。
开发版在启动时继续避免自动弹窗阻断。

菜单栏托盘带有明显的 `DEV` 标签。设置窗口标题和待办标头同样标明开发模式。
可通过托盘菜单的 `退出 TypingPet Dev` 退出。源码变更后重新运行脚本即可。
原生 Swift/AppKit 代码需重新编译并重启生效，脚本不提供热重载。
若 Dev 实例已在运行，请先退出再重新构建，以保证二进制文件与资源的一致性。
运行时文件锁机制会拦截第二个 Dev 进程启动，防止数据并发读写损坏。

您也可以直接通过命令行运行调试可执行文件：

```sh
swift run TypingPet --show-todos
```

直接运行未打包的二进制始终使用开发版的数据与配置。
如需测试 macOS 输入监控权限，请务必使用 `run_dev.sh` 打包的应用 bundle。

## 数据目录

```text
~/Library/Application Support/TypingPetDev/todo-state.json
~/Library/Application Support/TypingPetDev/Images/
~/Library/Application Support/TypingPetDev/KeyReactions/
```

设置 > 待办事项 中展示当前活跃的数据文件路径。
切勿使用早期与正式版共享 bundle identifier 的测试安装包。

## 正式版 Release 构建

仅在您明确需要构建生产正式包时，执行以下命令：

```sh
TYPINGPET_BUILD_CHANNEL=production ./scripts/build_app.sh
```

正式版构建保留原有的应用名与标准存储路径。
未打包或未识别的可执行文件无法启用正式模式。

## 自动更新验证

`./scripts/check_update.sh` 可通过两个 Dev 构建与本地本地服务器测试完整的自动更新链路。
详见 [自动更新说明](updates.md)。

## 界面本地化

五种界面语言存放在 `Sources/TypingPet/Localization/` 目录下：`zh-Hans.lproj`、`zh-Hant.lproj`、`en.lproj`、`ja.lproj` 与 `ko.lproj`，每个目录包含一个 `Localizable.strings` 文件。在代码中调用 `L(...)` 传入英文 key 字符串；动态参数通过占位符 `%1$@` 传入。所有语言文件中的 key 和参数占位符必须完全对称一致。用户自定义的待办标题和图片动作包名称不做多语言翻译。

设置 > 通用 > 语言 默认跟随系统。首选系统语言根据前缀匹配：`zh` 匹配简体中文/繁体中文（根据 script 和地区区分），`ja` 匹配日语，`ko` 匹配韩语，`en` 匹配英语；其他未知语言回退至简体中文（或英文）。用户手动选择语言后即时生效持久化，无需重启应用即可刷新全部界面。语言逻辑由 [AppLanguageMode](../Sources/TypingPet/Localization.swift) 管理。构建脚本会将所有 `.lproj` 资源目录拷贝进签名 bundle 中。设置窗口采用侧边栏分组架构，默认尺寸 1100 × 820 磅（最小 900 × 700 磅），预留充足空间展示键盘与预设编辑器。系统字号调大时会自动等比缩放窗口。保存的外观主题会同步应用到设置窗口和待办气泡面板。
