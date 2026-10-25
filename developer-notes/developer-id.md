# Developer ID 正式发布准备指南 (Developer ID Setup)

为确保 TypingPet 在用户电脑上运行时不触发 macOS Gatekeeper 未签名安全拦截，且在自动更新后能够稳定保持“输入监控”权限，需要拥有 Apple Developer Program 开发者账号以及 `Developer ID Application` 证书。
本文档指导账号所有者（Account Holder）完成相关配置。

## 1. 注册前准备

- 开启双重认证的 Apple ID。建议使用独立的个人 Apple 账号。
- Apple 账号的姓名必须是**法定真实姓名**，使用别名或昵称会导致审核受阻。
- 真实的账单地址和联系电话。不接受邮政信箱（P.O. Box）。
- 支付信用卡。年费为 99 美元。
- 个人开发者申请较为便捷，组织开发者则需要 D-U-N-S 编码和法人验证。本项目个人开发者即可满足需求。

## 2. 注册加入开发者计划

1. 访问 <https://developer.apple.com/programs/enroll/> 点击 **Start your enrollment**，也可在 Mac 或 iPhone 上的 **Apple Developer** 应用中操作。
2. 登录 Apple ID，选择 **Individual / Sole Proprietor**。
3. 填写真实姓名、地址、电话，并同意 Apple Developer Program License Agreement。
4. 支付年费，等待审核邮件（通常 1–2 个工作日）。
5. 审核通过后，在 <https://developer.apple.com/account> 的 **Membership details** 中获取 10 位 **Team ID**。

## 3. 创建 Developer ID Application 证书

证书仅限 Account Holder 创建，每个账号最多可创建 5 张。

### 使用 Xcode 快速创建（推荐）

1. 打开 Xcode > Settings > Accounts，添加您的 Apple 账号。
2. 选中团队，点击右下角 **Manage Certificates…**。
3. 点击左下角 `+` > 选择 **Developer ID Application** 即可自动生成并导入钥匙串。

### 通过 Apple Developer 官网创建

1. 打开 钥匙串访问 > 证书助理 > **从证书颁发机构请求证书…**，输入邮箱和常用名，选择**保存到磁盘**，生成 `.certSigningRequest` (CSR) 文件。
2. 访问 <https://developer.apple.com/account/resources>，点击 Certificates > `+`，选择 Software 下的 **Developer ID** > **Developer ID Application**。
3. 上传 CSR 文件，生成并下载 `.cer` 证书文件，双击安装到钥匙串。

### 验证与备份

在终端中运行：

```sh
security find-identity -v -p codesigning
```

输出中出现 `Developer ID Application: 您的姓名 (TEAMID)` 即说明安装成功。
请在“钥匙串访问”中将该证书与私钥一起导出为 `.p12` 格式，妥善加密备份。
若私钥丢失，已发布的旧版本无法用新证书直接平滑升级；但若 Team ID 保持一致，权限迁移相对顺畅。

## 4. 配置 Apple 公证凭据

1. 登录 <https://account.apple.com> 的“登录与安全” > **App 专用密码**，生成名为 `typingpet-notary` 的专用密码。
2. 在终端中运行一次以持久化存储到 Keychain 中：

```sh
xcrun notarytool store-credentials typingpet-notary --apple-id "您的Apple账号邮箱" --team-id "您的TEAMID"
```

该凭据加密存储于本地 Keychain 中，不会泄露进仓库。

## 5. 校验 Team ID 与生成更新密钥

`scripts/build_app.sh` 脚本会自动从 `Developer ID Application: 姓名 (TEAMID)` 中提取 Team ID，写入 Info.plist 的 `TypingPetTeamIdentifier` 键中（亦可通过 `TYPINGPET_TEAM_ID` 手动指定）。
生产版客户端仅允许安装带有相同 Team ID 且经过官方公证的升级包。

在发布首个正式生产版本前，需生成一次用于更新包校验的 Ed25519 密钥对：

```sh
swift scripts/update_keys.swift generate production
```

请将生成的 `~/.config/typingpet/update-keys/production.key` 与证书 `.p12` 一同妥善加密备份。若该私钥丢失，已安装的客户端将无法接收后续的自动升级。
若已有已发行的正式包，切勿生成新密钥覆盖，必须找回原始私钥并通过 `swift scripts/update_keys.swift check production` 校验与公钥的一致性。

## 6. 首次正式发布

配置完成后，即可使用 [自动化发布流程](releasing.md) 的 `./scripts/release.sh` 执行全自动构建、公证与部署。
分步手动执行命令如下：

```sh
TYPINGPET_BUILD_CHANNEL=production ./scripts/build_app.sh
./scripts/notarize_release.sh
./scripts/deploy_update.sh production dist/TypingPet.app
```

详情请参阅 [自动更新说明](updates.md)。

0.12.0 及更早版本由于缺少升级检测逻辑，需用户手动下载一次全新安装包。
此后采用相同 Team ID 签名的更新包，在用户平滑升级时均可完整保持“输入监控”权限，无需反复授权。
