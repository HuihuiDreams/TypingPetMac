# TypingPetMac 全量缺陷与代码质量修复实施计划

## 概述 (Overview)

基于代码库全面审查报告，本项目在核心玩法与几何计算上表现优异，但在**高频事件能耗**、**磁盘数据管理**、**构建脚本版本同步**、**开发环境路径泄漏**以及**单文件结构臃肿 (main.swift 1397行)** 方面存在改进空间。

本计划将所有修复任务划分为 4 个具备依赖顺序和可验证条件的阶段，确保每一步修改均可编译、可测试，并渐进式提升代码健康度。

---

## 架构与设计决策 (Architecture Decisions)

1. **增量交付与最小变更 (Karpathy Guidelines)**:
   - 先行解决有直接运行时影响的性能、能耗与磁盘泄露问题；
   - 随后处理构建脚本与安全泄漏；
   - 最后在已有测试守护下执行 `main.swift` 文件级拆分重构。
2. **模块内可见性**:
   - `main.swift` 中的原有组件拆分至独立文件后，由 `private` 提升为模块内默认的 `internal`，使 `@testable import TypingPet` 可以直接针对组件进行单元测试。
3. **安全优先**:
   - 避免直接裸露 `#filePath`，仅在 `#if DEBUG` 下提供本地开发回退；
   - 消除生产代码中不必要的强制解包 `!`。

---

## 依赖关系图 (Dependency Graph)

```
阶段一：性能与能耗修复 (Task 1, 2)
    │
    ▼
阶段二：正确性、磁盘清理与构建脚本 (Task 3, 4, 5)
    │
    ▼ [验证检查点 1]
阶段三：UI 响应与缩略图缓存 (Task 6)
    │
    ▼
阶段四：架构解耦与 main.swift 拆分 (Task 7, 8)
    │
    ▼ [最终验证检查点 2]
```

---

## 详细任务清单 (Task List)

### 阶段一：性能与能耗即时修复 (Performance & Energy)

#### Task 1: 消除全局鼠标事件中的无差别 CoreAnimation 事务提交
- **目标**: 避免在用户移动光标的每个像素点都强制提交无变化的 `CATransaction`。
- **改动范围**: [Sources/TypingPet/main.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/main.swift#L708-L719)
- **验收标准**:
  - [x] 在 `updatePetOpacity()` 中加入差值守卫：当 `abs(CGFloat(imageLayer.opacity) - targetOpacity) <= 0.001` 时直接返回，不再启动 `CATransaction`。
- **验证方式**:
  - [x] 编译通过：`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build`
  - [x] 现有测试全部通过。
- **估计规模**: XS (1 个文件，~5 行)

#### Task 2: 节流权限引导窗口的高频 WindowServer 窗口轮询
- **目标**: 将 120ms 的全系统窗口遍历放宽至省电周期，减少电量与 CPU IPC 开销。
- **改动范围**: [Sources/TypingPet/InputMonitoringGuide.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/InputMonitoringGuide.swift#L257-L268)
- **验收标准**:
  - [x] 将 `startWindowTrackingTimer` 中的 `timeInterval` 从 `0.12` 调整为 `0.6` 秒。
  - [x] 窗口吸附计算平滑性不受明显影响。
- **验证方式**:
  - [x] 编译通过。
  - [x] [PetWindowGeometryTests](file:///Users/huihui/Documents/TypingPetMac/Tests/TypingPetTests/PetWindowGeometryTests.swift) 几何测试不受影响。
- **估计规模**: XS (1 个文件，~2 行)

---

### 阶段二：正确性、磁盘卫生与脚本修复 (Correctness & Build Scripts)

#### Task 3: 实现图集与按键反应规则物理文件的同步清理
- **目标**: 彻底解决删除图集与规则时在 `Application Support` 留下孤立残留文件的问题。
- **改动范围**:
  - [Sources/TypingPet/PetImageLibrary.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/PetImageLibrary.swift#L163-L171) (`deleteSet`)
  - [Sources/TypingPet/KeyReactions.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/KeyReactions.swift#L94-L116) (`setRule` 覆盖旧图与 `removeRule`)
- **验收标准**:
  - [x] `deleteSet(id:)` 成功后，同步物理删除 `Sets/<storageFolder>` 目录。
  - [x] `removeRule(id:)` 和 `setRule` 覆盖同键位规则时，删除对应的 `<rule.imageFileName>` 孤立文件。
  - [x] 编写对应的单元测试验证物理文件在删除后确实已不存在。
- **验证方式**:
  - [x] 运行测试确认新增的物理删除测试通过。
- **估计规模**: S (2 个源文件 + 1 个测试文件)

#### Task 4: 修复打包脚本版本号与公证脚本临时目录清理
- **目标**: 确保分发包与文档版本严格一致，公证过程保持环境干净。
- **改动范围**:
  - [scripts/build_app.sh](file:///Users/huihui/Documents/TypingPetMac/scripts/build_app.sh#L48)
  - [scripts/notarize_release.sh](file:///Users/huihui/Documents/TypingPetMac/scripts/notarize_release.sh#L15)
- **验收标准**:
  - [x] `build_app.sh` 中的 `CFBundleShortVersionString` 从 `0.11.2` 修正为与 CHANGELOG 一致的 `0.12.0`。
  - [x] `notarize_release.sh` 中增加 `trap 'rm -rf "$work_dir"' EXIT`。
- **验证方式**:
  - [x] 检查生成的 `Info.plist` 内容。
- **估计规模**: XS (2 个脚本文件)

#### Task 5: 消除 Release 模式下的 `#filePath` 路径泄漏与不必要强制解包
- **目标**: 避免开发者本地文件路径固化在发布二进制中；增强代码健壮性。
- **改动范围**:
  - [Sources/TypingPet/PetImageLibrary.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/PetImageLibrary.swift#L87, #L148, #L222, #L232)
  - [Sources/TypingPet/KeyReactions.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/KeyReactions.swift#L71)
- **验收标准**:
  - [x] `#filePath` 仅在 `#if DEBUG` 下作为本地运行时回退，Release 模式下不嵌入绝对路径。
  - [x] 将 `fileManager.urls(...).first!` 和 `requestedName!` 替换为安全拆包模式。
- **验证方式**:
  - [x] 编译通过，所有既有测试通过。
- **估计规模**: S (2 个源文件)

---

### 检查点 1 (Checkpoint: Phases 1 & 2)
- [x] 编译无警告无报错：`swift build`
- [x] 现有测试全部通过
- [x] 磁盘清理逻辑经测试验证有效

---

### 阶段三：UI 缩略图缓存 (UI Responsiveness)

#### Task 6: 为图集与规则列表引入基于内存的缩略图缓存
- **目标**: 避免在设置窗口网格中每次重绘都主线程从磁盘解码大图。
- **改动范围**:
  - [Sources/TypingPet/PetImageLibrary.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/PetImageLibrary.swift)
  - [Sources/TypingPet/SettingsWindow.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/SettingsWindow.swift#L81-L87)
- **验收标准**:
  - [x] 在 `PetImageLibrary` 中维护 `NSCache<NSURL, NSImage>` 用于缓存解析后的待机/缩略图。
  - [x] 当图像被替换或更新时，自动清理或失效对应缓存条目。
- **验证方式**:
  - [x] 切换图集卡片时流畅，无重复磁盘 I/O。
- **估计规模**: S (2 个源文件)

---

### 阶段四：架构解耦与 `main.swift` 拆分 (Architecture & Simplicity)

#### Task 7: 统一收敛配置偏好键 (`AppPreferencesKey`)
- **目标**: 将分散在各处的 `"petScale"`, `"restingOpacity"`, `"alwaysOnTop"` 等字面量统一为强类型常量。
- **改动范围**:
  - [Sources/TypingPet/PetPreferences.swift](file:///Users/huihui/Documents/TypingPetMac/Sources/TypingPet/PetPreferences.swift) (新建)
- **验收标准**:
  - [x] 集中定义 UserDefaults 读写键与默认值。
- **估计规模**: S (新建 1 个文件，重构读取点)

#### Task 8: 模块化拆分 `main.swift` (1397 行) 为独立组件
- **目标**: 按照单一职责原则分解巨石文件，便于长期维护与测试。
- **改动范围**:
  - `Sources/TypingPet/PetViews.swift`: 抽离 `PetPanel`, `PetResizeHandleView`, `PetContentView`
  - `Sources/TypingPet/GlobalKeyMonitor.swift`: 抽离系统键盘监控逻辑
  - `Sources/TypingPet/PetController.swift`: 抽离宠物窗口控制器与运动学驱动
  - `Sources/TypingPet/AppDelegate.swift`: 抽离应用代理与状态栏菜单
  - `Sources/TypingPet/main.swift`: 精简保留为仅含应用启动引导的代码 (~30 行)
- **验收标准**:
  - [x] 所有类各司其职，无冗余代码与回滚。
  - [x] 应用主二进制大小与行为完全一致。
  - [x] `swift build` 与打包脚本均可无缝构建产物。
- **估计规模**: M (拆分为 4 个新文件，精简 1 个文件)

---

### 检查点 2 (Final Checkpoint)
- [x] `swift build` 构建成功且干净
- [x] 运行 `./scripts/build_app.sh` 成功产出 `TypingPet.app`
- [x] 检查 `Info.plist` 版本号为 `0.12.0`
- [x] 单元测试套件全部通过
- [x] Git diff 清晰，无附带不相关代码变动

---

## 潜在风险与应对预案 (Risks & Mitigations)

| 风险点 | 影响评估 | 应对预案 |
| :--- | :---: | :--- |
| **拆分 `main.swift` 可能导致类可见性冲突** | 中 | 保持在同一 `TypingPet` 目标下，将内部类级别由 `private` 调整为 `internal`（Swift 默认访问控制），不改变对外暴露接口。 |
| **磁盘删除操作可能误删用户原始文件** | 高 | 明确界定删除范围仅限于 `Application Support/TypingPet/Images/Sets/<UUID>` 和 `KeyReactions/` 内部拷贝文件，绝不触碰用户源文件夹。 |
| **缩略图缓存占用过多内存** | 低 | 使用系统受控的 `NSCache`，在系统内存吃紧时由系统自动淘汰释放。 |
