# 官网 Base UI 无障碍可访问性审查 (Website Accessibility Review)

对照 `@base-ui/react` 1.9.0 官方文档与最佳实践规范，对官网组件进行了全面无障碍改造。
覆盖范围包括五种语言的首页及更新日志页面中的语言切换菜单、安装方式切换 Tab、FAQ 折叠面板、邮件订阅表单及访问统计开关。

## 改进项与实现对照

| 审查对象 | 原有实现与存在问题 | 改进落地方案 |
| --- | --- | --- |
| 页面语言切换 | 原为 `details` 标签包裹普通链接。缺少方向键键盘导航、字符快速跳转定位、Esc 快捷键收起与焦点复位 | 重构为 `Menu.Trigger → Portal → Positioner → Popup → LinkItem`。保留当前语言高亮显示，完整保留页面路由、查询参数与锚点，维持语言偏好持久化 |
| 显示模式切换 | 原为 `details` 与原生单选按钮。包含大量手动监听指针与全局事件的代码 | 重构为 `Menu.RadioGroup / RadioItem / RadioItemIndicator`。清晰区分方向键聚焦与回车选择，关闭弹窗与焦点管理委托给组件库，维持系统外观模式监听 |
| 邮件订阅语言 | 原为独立原生 `select` 控件，与整体风格不协调 | 重构为 `Select.Label / Trigger / Value / Portal / Positioner / Popup / List / Item`。提供规范的标签关联、字符搜索定位、键盘无障碍操作与表单联动 |
| 订阅表单与授权 | 原生浏览器弹窗与默认 checkbox，错误信息脱节 | 重构为 `Form / Field / Input / Checkbox`。校验失败自动聚焦错误字段，关联 `aria-describedby` 错误描述，提交前前置检查必选条款，成功后重置表单并聚焦反馈结果 |
| 隐私说明 / Homebrew 指南 | 孤立分散的 `details/summary` | 统一抽象为 `Collapsible.Trigger / Panel` 组件，规范展开收起与 ARIA 状态联动 |
| 访问统计开关 | 使用 `aria-pressed` 按钮，文案频繁切换导致读屏体验差 | 采用固定语义标签的 `Switch` 开关控件，保留 DNT/GPC 防追踪保护逻辑 |
| 锚点直达与体验输入 | 直达目标元素无法显式接收焦点 | 主内容区添加 `tabIndex=-1`，打字体验区采用标准 `Input` |

普通页面导航与下载链接继续保留标准的 `<a>` 标签。
弹出浮层通过 Portal 渲染，添加了屏幕边缘防溢出边距。键盘聚焦态使用 `data-highlighted` 属性，并在浅色/深色主题下提供清晰的高对比度焦点指示环。

## 规范参考依据

- [Menu: 页面跳转与单选](https://base-ui.com/react/components/menu)：语言切换使用 `LinkItem`，设置项使用 `RadioGroup`。
- [Select: 结构与标签](https://base-ui.com/react/components/select)：`Select.Label` 与触发器严格关联，区分显示文本与表单值。
- [Forms: 校验与错误处理](https://base-ui.com/react/handbook/forms)：提交前校验必填字段与协议勾选，精准关联无障碍错误信息。
- [Collapsible](https://base-ui.com/react/components/collapsible), [Switch](https://base-ui.com/react/components/switch)：遵循各自的标准角色语义。
- [Tabs](https://base-ui.com/react/components/tabs)：保持手动激活模式，方向键移动焦点，Enter/Space 切换选项卡。

## 验证与测试

在真实浏览器中对键盘按键交互及无障碍无障碍树（Accessibility Tree）/ DOM 进行了验证：
- 语言选择器：Tab 键聚焦，Enter 或方向键展开，支持 Home/End 及字符快速搜索，Esc 键收起，焦点精准还原。
- 在 `/zh-Hans/changelog/?from=keyboard#newsletter` 中使用键盘切换语言，能正确保留参数无缝跳转至对应语言路径。
- 深浅色切换：支持方向键移动并按回车确认，页面刷新后偏好持久化生效。
- 订阅表单校验：空提交时自动聚焦至邮箱字段并关联 `aria-invalid` 属性。
- 移动端 375px 小屏适配：无横向滚动溢出，弹出层自适应视口。
- 静态页面构建编译：TypeScript 类型检查通过，10 个静态页面构建验证通过。
