# Implementation Plan: TypingPetMac Game UI/UX 体验系统性改进

## Overview

基于 `/game-ui-ux` 体系的设计规范（响应式布局、事件驱动 HUD、微状态机、Game-Feel 动效与键盘/全设备友好），将 **TypingPetMac** 从基础的“悬浮图片弹跳”提升为高品质、具有生命感、交互细腻且深度融入 macOS 工作流的**桌面打字陪伴宠物**。

本计划将 P0 到 P3 需求收敛为 **3 个互相解耦、可独立验证的实施阶段（Phase 1 至 Phase 3）**，严格遵守项目的架构设计约束（零第三方依赖、严格能耗差值守卫、非激活焦点安全不变量与集中偏好收敛）。

针对方案的可实现性与验收严谨性，本版明确强化了**全屏与 DND 权限边界**、**`.petpack` 容器规范与解压防爆防护**、**输入解耦与按键唤醒路径**，以及 **WPM/Combo 的精确数学模型与能耗验收指标**。

---

## Architecture Decisions & Constraints

1. **零第三方依赖 (Zero External Dependencies)**：所有物理动效、粒子反馈与文件归档全部采用 Apple 原生框架（`QuartzCore`、`AppKit`、`SwiftUI`、原生 ZIP 解析与 `FileHandle`），严禁引入外部包。
2. **能耗与调度守卫 (Energy & Timer Guarding)**：
   - 击键速度计算与 Combo 连击跟踪必须采用按需事件驱动的滑动窗口，严禁引入常驻轮询定时器（`repeats: true`）；
   - 任何 CoreAnimation 变换与透明度跃迁保留差值阈值保护（`> 0.001`），杜绝无效 `CATransaction` 提交；
   - 空闲能耗验收以**无活跃后台定时器、无多余主线程 Wake-up** 为准。
3. **输入监控权限与按键路径隔离 (Input Monitoring & Key Event Pipeline)**：
   - 全局按键与唤醒依赖 macOS 系统“输入监控”权限（`CGEventTap` `.listenOnly` 会话）；
   - `handleKeystroke` 严格分离“按键事件接收与状态唤醒”和“具体动作图片分发”，未绑定动作图片的按键同样能准确唤醒待机宠物。
4. **伴生窗口非激活焦点安全 (ADR-004)**：
   - `PetPanel` 保持 `canBecomeKey = false` 铁律；
   - 气泡从 `.compact` 胶囊态展开为 `.expanded` 全面板时，依然遵循按需激活与激进失焦释放逻辑。
5. **集中偏好管理 (PetPreferences Contract)**：所有新功能开关（如 WPM 连击弹跳、胶囊态显示、边缘探头、全屏 DND）必须收敛进 `AppPreferencesKey` 和 `AppPreferencesDefault`，并在 `PetPreferencesContractTests` 中全量覆盖。

---

## Dependency Graph

```
Phase 1: Foundation (P0 核心打击感与微状态机)
    ├── Task 1: 打字速度感应与动态连击弹跳 (WPM / Combo Tracker)
    ├── Task 2: 待机多帧呼吸与发呆瞌睡微状态机 (Idle Micro-States)
    └── Task 3: 拖拽挤压与撞击拉伸物理形变 (Squash & Stretch)
         │
         ▼
Phase 2: Core HUD (P1 伴生 HUD 分级与动效流)
    ├── Task 4: 专注计时常驻微型 Mini 胶囊态 (Compact HUD Capsule)
    ├── Task 5: 气泡弹跳与矢量尾巴果冻展开动效 (Spring Expansion)
    └── Task 6: 专注结束/任务达成庆祝动效与体态联动 (Celebration Feedback)
         │
         ▼
Phase 3: Ecosystem & System (P2/P3 编辑器沙盒、动作包共享与系统融合)
    ├── Task 7: 动作包编辑实时打字沙盒预览 (Interactive Typing Sandbox)
    ├── Task 8: 动作包一键打包导出与导入 (.petpack Single-File Archive)
    └── Task 9: 屏幕边缘探头停靠态与全屏智能免打扰 (Edge Peeking & Targeted DND)
```

---

## Phase 1: 核心打击感与微状态机 (P0)

> **目标**：赋予桌宠即时打字正反馈与生命呼吸感，消除静态贴图与僵硬平移的塑料感。

### Task 1: 打字速度感应与动态连击弹跳 (Adaptive Combo & WPM Bounce)

**Description:**
在按键分发路径中引入轻量击键滑动窗口追踪器（`TypingComboTracker`），无常驻定时器，基于按键事件驱动。根据即时打字速度与连击数动态调整 `bounce()` 的位移与缩放反馈。

**数学模型与验收口径明确：**
1. **按键重复 (Key Repeat / Held Keys) 过滤**：
   - 依赖 `CGEvent` 的 `keyboardEventAutorepeat` 字段（在 `KeyStroke` 中增加 `isAutorepeat: Bool = false`）；
   - 长按键盘触发的系统重复击键仅作为持续动作刷新，**不计入 Combo 连击累加**，**不计入 WPM 统计**，防止按住单键虚增连击。
2. **WPM 算法口径**：
   - 采用 3.0 秒滑动窗口，容量为 30 的环形时间戳队列（无动态内存分配）；
   - 按国际打字标准，5 次有效初次击键折算为 1 个单词（$1\text{ Word} = 5\text{ Keystrokes}$）；
   - 若窗口内初次击键数 $N \ge 2$ 且时间跨度 $\Delta t > 0.3\text{s}$，则 $\text{WPM} = \frac{N / 5}{\Delta t / 60} = \frac{12 \times N}{\Delta t}$；超过 1.5 秒无击键则即时 WPM 归 0。
3. **Combo 归零与平滑衰减的界限**：
   - **逻辑状态（超时归零）**：击键间隔 $\Delta t \le 1.2\text{s}$ 计为连续击键，`combo += 1`；超过 1.2 秒无击键判定为连击中断，逻辑计数归 0。
   - **视觉动效（弹性平滑衰减）**：连击期间宠物享受动态微缩放（最高 1.05x）；连击中断时，通过 `PetConstants.idleDelay`（0.3s）配合 CoreAnimation `CAMediaTimingFunction(name: .easeOut)` 在 0.2 秒内将形变矩阵平滑插值回缩至 1.0x 基准尺寸，视觉无突兀跳变。
4. **能耗验收指标**：
   - `TypingComboTracker` 内部**零常驻重复定时器 (`repeats: true`)**；
   - 连击超时仅由击键时投递的可取消单次延迟任务（One-Shot WorkItem）或下次击键时间差判定驱动，空闲静止期间所有定时器均处于失效或已销毁状态。

**Acceptance criteria:**
- [ ] 连续高频初次击键（有效 WPM > 50 或 Combo > 15）时，弹跳高度与体态尺寸呈现轻微动态增益（振幅提升 20%~40%，缩放 1.03x~1.05x）。
- [ ] 键盘长按产生的重复事件（Autorepeat）不增加 Combo 计数与 WPM。
- [ ] 停止打字超过 1.2s 后，Combo 计数重置，体态通过 CoreAnimation 平滑衰减回缩至 1.0x。
- [ ] 偏好设置中收敛 `AppPreferencesKey.comboBounceEnabled`，支持用户一键开启/停用。
- [ ] 单元测试验证空闲状态下无残留活跃 Timer 或无尽循环任务。

**Verification:**
- [ ] 单元测试通过：`swift test --filter PetComboTrackerTests`
- [ ] 偏好契约测试通过：`swift test --filter PetPreferencesContractTests`
- [ ] 手动验证：长按按键与快速敲击不同按键，验证 Combo 增长口径与视觉衰减回缩。

**Dependencies:** None
**Files likely touched:**
- `Sources/TypingPet/PetController.swift`
- `Sources/TypingPet/GlobalKeyMonitor.swift`
- `Sources/TypingPet/KeyReactions.swift`
- `Sources/TypingPet/PetPreferences.swift`
- `Tests/TypingPetTests/PetPreferencesContractTests.swift`

**Estimated scope:** Medium (4 files)

---

### Task 2: 待机多帧呼吸与发呆瞌睡微状态机 (Idle Micro-States)

**Description:**
构建多级待机状态机（`PetIdleStateMachine`）：活跃打字（Active）→ 浅层待机呼吸（Resting）→ 发呆打瞌睡（Sleeping，无输入 5 分钟后）。
**重构 `PetController.handleKeystroke` 的调用顺序**，确保任何输入都能即时唤醒宠物，无论该按键是否配置了专用动作图片。

**状态机架构与按键处理路径重构：**
1. **输入监控依赖说明**：全局击键感知依赖 macOS“输入监控”权限（`ListenEvent`）。未授权时全局按键不送达，宠物稳定保留在 Resting 待机；已授权时无论聚焦何种应用均能捕获。
2. **`handleKeystroke` 时序拆分**：
   ```swift
   func handleKeystroke(_ stroke: KeyStroke? = nil) {
       // Step 1: 无论是否有动作图片，优先唤醒状态机与记录连击
       idleStateMachine.receiveInput() // 若在 Sleeping，立即切回 Active，重置 5 分钟瞌睡计时
       comboTracker.recordKeystroke(stroke) // 记录击键用于 WPM / Combo 计算
       
       // Step 2: 动作图片分发
       let set = library.activeSet
       let pack = packStore.rawConfiguration(for: set)
       guard let id = playback.reaction(for: stroke, in: pack),
             let chosenURL = packStore.imageURL(id: id, in: pack, set: set) else {
           // 未绑定动作图片的按键：宠物已苏醒，维持当前常态待机帧并轻微抖动，不拦截唤醒
           if idleStateMachine.wasSleepingBeforeInput { showIdleImage() }
           return
       }
       
       // Step 3: 播放匹配图片与弹跳
       showImage(at: chosenURL)
       bounce()
       scheduleIdleReset()
   }
   ```
3. **呼吸与瞌睡帧表现**：
   - 多帧待机动作包：按 2~3 秒周期低频循环待机帧（呼吸/眨眼）；
   - 单帧动作包：通过轻微 `transform.translation.y`（1~2 逻辑像素）执行柔和缓动循环；
   - 瞌睡态：5 分钟无输入后显示发呆表情或微浮动气泡，任意击键瞬间取消瞌睡，即刻转入清醒工作态。

**Acceptance criteria:**
- [ ] 敲击未配置独立反应图片的按键（如未映射的符号键或无图片规则键），依然能从瞌睡状态即刻唤醒宠物。
- [ ] 待机呼吸循环频率严格维持在 0.33Hz ~ 0.5Hz（2~3 秒一次），且在宠物窗口隐藏（`hidePet()`）或系统休眠时彻底暂停定时器。
- [ ] 瞌睡唤醒后无图层撕裂或帧残留。

**Verification:**
- [ ] 单元测试通过：`swift test --filter PetIdleStateMachineTests`
- [ ] 状态时序断言：编写用例模拟未绑定按键输入，断言状态机从 `.sleeping` 成功跃迁至 `.active`。

**Dependencies:** Task 1
**Files likely touched:**
- `Sources/TypingPet/PetController.swift`
- `Sources/TypingPet/PetPacks.swift`
- `Sources/TypingPet/PetPreferences.swift`

**Estimated scope:** Medium (3 files)

---

### Task 3: 拖拽挤压与撞击拉伸物理形变 (Squash & Stretch Physics)

**Description:**
利用已有 `PetDragSample` 速度向量与阻尼滑行几何，在鼠标拖拽与惯性滑行撞墙时为宠物图层引入经典的动画物理法则（Squash & Stretch）：拖拽提起时沿速度方向微幅拉伸（Stretch），撞击屏幕可视边界（`clampedOrigin`）时触发弹性挤压（Squash）。

**Acceptance criteria:**
- [ ] 鼠标按住宠物拖动时，按当前移动速率施加适度拉伸形变（不超过 10%）。
- [ ] 惯性释放并撞击屏幕边缘反弹时，触发一次 `CAKeyframeAnimation` 挤压形变，回弹曲线自然平滑。
- [ ] 严格遵守 `PetPanel` 的非激活和低消耗约束，形变矩阵在动作结束时彻底恢复为 `identity`。

**Verification:**
- [ ] 编译与基础测试：`swift test --filter PetWindowGeometryTests`
- [ ] 手动验证：拖拽甩动宠物并使其撞向屏幕边框，观察回弹与拉伸形变。

**Dependencies:** None
**Files likely touched:**
- `Sources/TypingPet/PetViews.swift`
- `Sources/TypingPet/PetController.swift`
- `Sources/TypingPet/PetWindowGeometry.swift`

**Estimated scope:** Small-Medium (3 files)

---

### Checkpoint: Phase 1 交付检查点
- [ ] `swift test` 全量单元测试通过。
- [ ] `./scripts/check_todo.sh` 独立检查工具编译无阻断。
- [ ] 静态空闲状态下通过回归测试确认无任何未清理的无尽重复定时器。

---

## Phase 2: 伴生 HUD 分级与动效流 (P1)

> **目标**：重构伴生待办与番茄钟（`TodoBubble`）的交互层级，解决大面板遮挡屏幕视线痛点，打造果冻弹簧般精致的伴生 HUD。

### Task 4: 专注计时常驻微型 Mini 胶囊态 (Compact Mini HUD Capsule)

**Description:**
在 `TodoBubbleView` 中实现紧凑型胶囊模式（`.compact`）。专注计时器运行期间，气泡默认收起为宠物身旁的微型半透明圆角药丸胶囊（例如：`⏱ 23:45`），仅占极小桌面空间；悬停或单击可平滑展开为完整待办看板。

**Acceptance criteria:**
- [x] 在 `FocusTimerState` 处于运行态时，用户可配置自动收缩为胶囊态（Capsule HUD）。
- [x] 胶囊条自适应停靠在宠物头顶或侧翼，尺寸不超过 120x28 逻辑像素。
- [x] 悬停或点击胶囊顺畅展开为完整待办列表，移出或失焦后自动收起。

**Verification:**
- [x] 单元测试通过：`swift test --filter TodoBubbleTests`
- [x] 手动验证：启动倒计时专注，观察大面板平滑折叠为小胶囊，悬停能正常唤起并操作待办项。

**Dependencies:** None (与 Phase 1 解耦)
**Files likely touched:**
- `Sources/TypingPet/TodoBubbleView.swift`
- `Sources/TypingPet/TodoBubbleWindowController.swift`
- `Sources/TypingPet/TodoBubbleGeometry.swift`
- `Sources/TypingPet/PetPreferences.swift`

**Estimated scope:** Medium (4 files)

---

### Task 5: 气泡弹跳与矢量尾巴果冻展开动效 (Spring Expansion & Tail Growth)

**Description:**
优化气泡窗口从收起到展开的视觉过渡，用 SwiftUI `spring(response: 0.35, dampingFraction: 0.72)` 替代突兀的显隐。尾巴尖端向量先向宠物锚定，气泡本体如同水滴般微弹膨胀展开；收回时向锚点微缩淡出。

**Acceptance criteria:**
- [x] 气泡展开与折叠具有可感知的弹性物理果冻效果，避免窗口硬切闪烁。
- [x] 气泡在屏幕四角自适应翻转方向时（`flipX / flipY`），尾巴与弹簧动画保持平滑连续。
- [x] 保持 ADR-004 焦点释放不变量，弹簧动画播放期间不阻塞系统点击穿透。

**Verification:**
- [x] 单元测试通过：`swift test --filter TodoBubbleTests`
- [x] 视觉走查：在屏幕各个边缘与角落触发气泡展开，验证尾巴锚定与缩放中心一致性。

**Dependencies:** Task 4
**Files likely touched:**
- `Sources/TypingPet/TodoBubbleView.swift`
- `Sources/TypingPet/TodoBubbleGeometry.swift`

**Estimated scope:** Small-Medium (2 files)

---

### Task 6: 专注结束/任务达成庆祝动效与体态联动 (Celebration Feedback)

**Description:**
当番茄钟倒计时结束、或今日全部待办项被勾选完成时，触发一次轻量纯原生的小型庆祝动效（Confetti/Sparkle），同时与 `PetController` 联动，使宠物主动播放开心/举杯庆祝的反应动作，强化正向心流。

**Acceptance criteria:**
- [x] 计时完成触发音画一致的轻量庆祝反馈，持续约 1.2 秒后自动消散，不污染图层层级。
- [x] 宠物同步切换到庆祝情绪帧（若当前动作包未配置则播放开心跳跃序列）。
- [x] 严格遵循系统的“减弱动态效果 (Reduce Motion)”辅助功能设置。

**Verification:**
- [x] 单元测试通过：`swift test --filter TodoBubbleTests`
- [ ] 手动验证：完成一个 1 分钟快速倒计时，观察气泡微动效与宠物联动。

**Dependencies:** Task 4, Task 5
**Files likely touched:**
- `Sources/TypingPet/TodoBubbleView.swift`
- `Sources/TypingPet/PetController.swift`
- `Sources/TypingPet/TodoState.swift`

**Estimated scope:** Medium (3 files)

---

### Checkpoint: Phase 2 交付检查点
- [ ] 待办与专注功能所有回归测试通过：`swift test --filter Todo*`
- [ ] 连续开启/关闭/最小化番茄钟，确认无内存泄漏（Instruments Leaks 零报告）。

---

## Phase 3: 编辑器沙盒、动作包共享与系统级融合 (P2 & P3)

> **目标**：打通用户创作、调试与共享闭环，并使桌宠在多屏、全屏与边缘停靠中达到 macOS 原生级融入感。

### Task 7: 动作包编辑实时打字沙盒预览 (Interactive Typing Sandbox)

**Description:**
在偏好设置工作台（`NativeSetWorkspace.swift`）内集成一个交互式打字沙盒预览框。用户在设置界面内输入任何字母或修饰键，内置的预览画布即时以当前配置的图集和按键映射进行出拳弹跳与特殊帧展示，所见即所得。

**Acceptance criteria:**
- [ ] 设置工作台提供清晰的“打字试玩沙盒”输入区域，捕获击键事件仅用于本地预览渲染。
- [ ] 支持实时呈现用户刚刚调整的待机帧、左右手交替以及特定按键映射效果。
- [ ] 离开或切换设置面板时，沙盒状态与定时器安全销毁，不拦截系统全局击键。

**Verification:**
- [ ] 单元测试通过：`swift test --filter PackEditorModelTests`
- [ ] 手动验证：在设置窗口中为字母 `F` 绑定新图片，沙盒敲击 `F` 即时验证生效。

**Dependencies:** None
**Files likely touched:**
- `Sources/TypingPet/NativeSetWorkspace.swift`
- `Sources/TypingPet/PackEditorModel.swift`
- `Sources/TypingPet/SettingsWorkspace.swift`

**Estimated scope:** Medium (3 files)

---

### Task 8: 动作包一键打包导出与导入 (`.petpack` 规范与安全防线)

**Description:**
设计并实现标准的单文件动作包格式（`.petpack`）。采用标准 ZIP 容器封装结构化目录，并建立严格的文件数、体积、解压膨胀比（Zip Bomb 防御）及路径穿越校验。

**`.petpack` 格式规范与安全边界：**
1. **归档容器标准**：
   - 基于标准 ZIP 容器封装（Magic Header: `PK\x03\x04` / `0x04034b50`），扩展名限定为 `.petpack`。
2. **包内组织结构与 Manifest 格式**：
   ```
   my_pack.petpack (ZIP 根目录)
   ├── pack.json            # 动作包元数据与映射清单
   └── images/              # 图片素材目录
       ├── basic.png        # 待机帧
       ├── left.png         # 左手出击帧
       ├── right.png        # 右手出击帧
       └── reactions/       # 可选的特殊单键反应帧
   ```
   `pack.json` 规范定义：
   ```json
   {
     "schemaVersion": 1,
     "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
     "name": "Custom Cat",
     "author": "Alice",
     "version": "1.0.0",
     "idle": { "frameNames": ["basic.png"], "interval": 2.5 },
     "typing": { "left": "left.png", "right": "right.png" },
     "keyReactions": { "49": "reactions/space.png" }
   }
   ```
3. **版本兼容规范**：
   - 当前基准为 `schemaVersion = 1`；
   - 若导入文件 `schemaVersion > 1`，弹出本地化清晰报错并引导用户升级应用，不强行解析未知结构。
4. **安全边界与解压防爆防护 (Security & DoS Limits)**：
   - **归档包体积上限**：单个 `.petpack` 文件不得超过 **25 MiB**；
   - **解压总文件数上限**：整包解压文件数严格限制 $\le 200$ 个；
   - **解压后总大小上限**：解压出的文件总字节数不得超过 **50 MiB**；
   - **单文件大小上限**：任意单一图片文件不得超过 **10 MiB**；
   - **解压膨胀比拦截 (Zip Bomb Mitigation)**：解压膨胀比超过 **10:1** 判定为异常炸弹，立即中断解压并丢弃临时文件；
   - **格式与路径过滤**：仅允许 `.json` 及图片扩展名（`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`）；过滤抛弃 `.DS_Store`、`__MACOSX`、符号链接、硬链接以及包含 `..`、绝对路径 `/` 或 Windows 风格 `\` 的非法路径；
   - **落盘目标隔离**：物理目标严格限定在沙箱安全的 `~/Library/Application Support/TypingPet/Sets/<UUID>/` 专用目录内。

**Acceptance criteria:**
- [ ] 导出：一键将选中的自定义图集打包并命名为 `<SetName>.petpack`。
- [ ] 导入：支持文件拖拽与系统打开面板，解压前执行 Magic Header 与文件大小预检；解压中严格执行文件数与膨胀比熔断。
- [ ] 任何恶意构造的符号链接、路径穿越包或压缩炸弹均被优雅拦截，并在 UI 呈现安全提示，不损坏现有图集目录。

**Verification:**
- [ ] 单元测试覆盖合规导入、非法扩展名拦截、超大文件熔断与符号链接拒绝：`swift test --filter PetPackArchiveTests`
- [ ] 手动验证：导出预设图集，清空后重新拖入，画廊与按键绑定准确恢复。

**Dependencies:** None
**Files likely touched:**
- `Sources/TypingPet/PetImageLibrary.swift`
- `Sources/TypingPet/PetPacks.swift`
- `Sources/TypingPet/SettingsWorkspace.swift`
- `Tests/TypingPetTests/DiskCleanupTests.swift`

**Estimated scope:** Medium-Large (4 files)

---

### Task 9: 屏幕边缘探头停靠态与全屏智能免打扰 (Edge Peeking & Targeted DND)

**Description:**
实现高质感的系统级空间适应能力，**收窄并明确全屏与免打扰的权限边界与检测方案**：
1. **零权限原生 Space 隔离 (Native Space Full-Screen Suppression)**：利用 macOS 窗口系统底层的 Space 行为，无需任何探测代码或权限即可完美解决全屏遮挡；
2. **定向应用免打扰 (Targeted App DND via NSWorkspace)**：基于事件通知对特定应用实现自动静音与避让；
3. **边缘探头吸附 (Edge Peeking)**：贴近屏幕左右边界时，自动缩进只露半个脑袋暗中观察。

**全屏检测与 DND 具体落地方案：**
1. **原生 Full-Screen Space 隔离（解决全屏应用遮挡，0 权限，0 轮询）**：
   - 当前 `PetPanel` 配置为 `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`，使得它强行悬浮在全屏应用所在的独立 Space 之上；
   - **改进方案**：在 `PetPreferences` 中新增开关 `showInFullScreenSpaces`（默认值：`false`，免打扰优先）；
   - 当该选项为 `false` 时，从 `panel.collectionBehavior` 中**移除 `.fullScreenAuxiliary`**，仅保留 `.canJoinAllSpaces`。
   - **系统行为保证**：macOS Window Server 在用户全屏切换到 Xcode、视频、Keynote 等独立全屏 Space 时，会**在底层自动隐藏宠物面板**，切换回桌面 Space 时自动恢复显示！完全由操作系统保证，**零轮询、零私有 API、零额外权限（无需辅助功能或录屏权限），100% 稳定可靠**。
2. **指定应用激活免打扰 (Targeted Application DND)**：
   - 监听系统标准通知 `NSWorkspace.didActivateApplicationNotification`（事件驱动，0 轮询）；
   - 当 `frontmostApplication?.bundleIdentifier` 命中用户配置的免打扰名单（如 Keynote `com.apple.iWork.Keynote`、QuickTime `com.apple.QuickTimePlayerX`，或游戏）时，宠物平滑将透明度降低至 0.05 或自动隐退。
3. **边缘探头停靠 (Edge Peeking)**：
   - 当拖拽宠物并释放于屏幕左/右边缘 24 像素阈值内时，触发吸附判定，窗口自动平移缩进，仅露出一半头部（50% 视口）；
   - 打字时执行平滑位移动画探身出拳，打字停止 0.5s 后回缩至停靠态。

**Acceptance criteria:**
- [ ] 关闭“全屏空间中显示”后，将任意窗口全屏化（进入新 Space），桌宠在该全屏 Space 中原生自动隐藏，切回普通桌面立即恢复。
- [ ] 命中免打扰应用名单激活时，桌宠透明度平滑衰减，切出后自动复原。
- [ ] 靠边释放时触发探头吸附，出拳位移自然，且依然保持 `canBecomeKey = false` 点击穿透约束。

**Verification:**
- [ ] 单元测试通过：`swift test --filter PetWindowGeometryTests`
- [ ] 手动验证：进入全屏播放或幻灯片放映，验证全屏 Space 隔离与边缘吸附。

**Dependencies:** Task 3
**Files likely touched:**
- `Sources/TypingPet/PetWindowGeometry.swift`
- `Sources/TypingPet/PetController.swift`
- `Sources/TypingPet/PetPreferences.swift`
- `Sources/TypingPet/SettingsWorkspace.swift`

**Estimated scope:** Medium (4 files)

---

### Checkpoint: Phase 3 交付检查点
- [ ] 全量单元测试 `swift test` 保持 100% 通过。
- [ ] 执行打包验证：`./scripts/build_app.sh dist`，验证打包签名与无符号泄漏。
- [ ] 运行 `./scripts/check_publish_update.sh` 与 release 测试，确认无破损。
- [ ] 更新 `CHANGELOG.md` 与相关文档。

---

## Risks and Mitigations

| 风险点 | 影响等级 | 缓解与应对策略 |
| :--- | :--- | :--- |
| **打字高频事件下 WPM 计算引发主线程卡顿** | 高 | 限制滑动窗口容量（仅保留最近 30 次击键时间戳，环形缓冲区），避免频繁数组内存重新分配；Key Repeat 事件直接在最前端过滤。 |
| **待机多帧循环导致电量消耗与唤醒增多** | 中 | 待机循环频率严格限制在 2~3 秒一次；全屏隐藏或屏幕锁屏时必须完全暂停定时器；拒绝常驻循环 Timer。 |
| **`.petpack` 压缩炸弹 (Zip Bomb) 攻击与路径穿越** | 高 | 解压前检查包体 $\le 25\text{MB}$，解压中实时累计解压大小（$\le 50\text{MB}$）和膨胀比（$\le 10:1$），熔断超限立即删除残片；强制路径组件白名单。 |
| **未授权输入监控时按键唤醒失效** | 中 | 在状态机中将“权限未授予”视为自然休眠状态，UI 端保持明确的 Input Monitoring 引导浮窗，不进行崩溃或无尽重试。 |
| **全屏 Space 切换产生闪烁** | 低 | 依赖 macOS 原生 `.fullScreenAuxiliary` 集合行为控制，交由 Window Server 原生管理淡入淡出，无额外闪烁风险。 |

---

## Plan Status Summary

- [x] **Phase 1: 核心打击感与微状态机 (P0)** (已完成并提交 `bd65003`)
  - [x] Task 1: 打字速度感应与动态连击弹跳
  - [x] Task 2: 待机多帧呼吸与发呆瞌睡微状态机
  - [x] Task 3: 拖拽挤压与撞击拉伸物理形变
- [ ] **Phase 2: 伴生 HUD 分级与动效流 (P1)**
  - [ ] Task 4: 专注计时常驻微型 Mini 胶囊态
  - [ ] Task 5: 气泡弹跳与矢量尾巴果冻展开动效
  - [ ] Task 6: 专注结束/任务达成庆祝动效与体态联动
- [ ] **Phase 3: 编辑器沙盒、动作包共享与系统融合 (P2 & P3)**
  - [ ] Task 7: 动作包编辑实时打字沙盒预览
  - [ ] Task 8: 动作包一键打包导出与导入 (`.petpack`)
  - [ ] Task 9: 屏幕边缘探头停靠态与全屏智能免打扰
