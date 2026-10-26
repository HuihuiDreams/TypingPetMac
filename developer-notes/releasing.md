# 自动化发布流程 (Release Pipeline)

在当前 Mac 上，仅需一条命令即可依序执行：单元测试 → 编译源码 → Developer ID 签名 → Apple 官方公证 → 部署至更新服务器 → HTTPS 文件完整性验证。

```sh
./scripts/release.sh
```

如需同时发布 GitHub Release 并附带 ZIP 与 SHA-256 校验包，请使用：

```sh
./scripts/release.sh --github
```

如需连同更新 Homebrew Tap，请使用如下命令（`--homebrew` 会自动包含 `--github`）：

```sh
./scripts/release.sh --homebrew
```

该命令会更新 `ynifamily3/homebrew-tap` 仓库中的 `Casks/typing-pet.rb`，并优先校验公开 GitHub ZIP 与本地校验值是否完全一致。
用户安装命令为：`brew tap ynifamily3/tap` 然后 `brew install --cask ynifamily3/tap/typing-pet`。

## 准备新版本

1. 完成功能开发与手动 UI 确认。脚本不会自动操作 UI 或输入监控权限。
2. 在仓库根目录的 `version.json` 中，将 `version` 和 `build` **双双** 提高至大于当前已发布版本的数值，例如：

   ```json
   {
     "version": "0.19.0",
     "build": 31
   }
   ```

3. 在 `CHANGELOG.md` 顶部添加 `## 0.19.1 - YYYY-MM-DD` 章节与详细变更说明。该段落将作为自动更新弹窗说明与 GitHub Release 发版日志。安装说明中的版本链接也需同步更新。
4. 提交所有源码、版本与文档（Git commit）。使用 `--github` 时需先将该 commit 推送到 GitHub 远程仓库。脚本不会自动进行源码 commit 或 push。
5. 先运行只读预检，确认无误后再执行正式发布：

   ```sh
   ./scripts/release.sh --dry-run --homebrew
   ./scripts/release.sh --homebrew
   ```

默认情况下若存在未提交的更改将自动中止。仅在不发布 GitHub、仅本地部署时可通过 `--allow-dirty` 豁免。即使豁免，准备后若源码再有改动同样会拒绝重试。
`version.json` 同样作为日常本地开发构建的基准版本号。

## 依赖的前置凭据配置

- 钥匙串（Keychain）中必须包含有效的 `Developer ID Application` 证书与私钥。若存在多个，可通过环境变量 `CODE_SIGN_IDENTITY` 指定证书全名。
- Apple 公证凭据使用现有的 Keychain Profile `typingpet-notary`（可通过 `NOTARY_KEYCHAIN_PROFILE` 指定其他名称）。开发者姓名与 Team ID 为公开可查信息。
- 更新私钥使用 `~/.config/typingpet/update-keys/production.key` 与 `production.pub`（可通过 `TYPINGPET_UPDATE_KEY_DIR` 覆盖路径）。**发布过程中绝不重新生成新密钥。** 脚本会验证与当前已发布 ZIP 的签名一致性，若私钥不匹配立即终止。
- 静态更新服务器使用本地目录 `~/TypingPetUpdate`（可通过 `TYPINGPET_UPDATE_ROOT` 覆盖）。不修改 nginx/TLS 配置。本地 feed 必须与 `https://pet.miel.ing/update/production/latest.json` 状态一致方可继续。
- `--github` 选项需要已登录认证的 `gh` CLI 工具。严禁将密码或 Token 作为命令行参数传递。
- `--homebrew` 选项需要对对应的 tap 仓库具备推送写入权限。

关于证书的申请与配置，请参考 [Developer ID 准备指南](developer-id.md)。

## 执行阶段与产物说明

1. 检查版本、构建号、变更日志、源码工作区状态、证书、更新密钥对与当前 feed。`--dry-run` 只执行到此只读检查阶段。
2. 校验现有更新密钥对与当前发布的 ZIP 签名，并通过 `notarytool history` 检查公证 Profile。
3. 执行 `swift test`、`check_todo.sh` 与 `check_publish_update.sh`。任一测试失败将直接熔断，不会进入编译或公证环节。
4. 编译针对 Apple Silicon 的 Release 应用。生产包中剔除本地调试路径、剥离调试符号并执行 Developer ID 代码签名。
5. 提交 Apple 公证，公证状态必须为 `Accepted` 才能继续执行 staple 票据封装与 Gatekeeper 本地校验。默认超时为 30 分钟。
6. 使用 Ed25519 签名生成更新 zip 与 manifest。排查二进制中是否残留敏感路径（如 `/Users/<name>/`），防止信息泄露。
7. 使用 GitHub 选项时优先创建 Draft 草稿 Release。Tag 必须精准指向当前 Git Commit，绝不漂移旧 Tag。
8. 加锁更新服务器防止并发部署，先拷贝 zip 归档，最后原子替换 `latest.json`。禁止覆写历史版本的 zip。通过公网 HTTPS URL 下载并双向比对验证。
9. 服务器校验通过后，将 GitHub 草稿转为正式公开发布。
10. 使用 Homebrew 选项时重新拉取公开 GitHub ZIP 并校验哈希，发布锁定了版本与 SHA-256 的 Cask 文件。

发布产物保留在 `dist/releases/v<version>-<build>/` 目录下：
- `TypingPet.app`、公证完成的 ZIP、更新 feed 与带签名的 ZIP
- `TypingPetMac-v<version>-arm64.zip` 与 `.sha256` 校验和
- `release-notes.md`、`notary-result.json`、`release.log`
- 上一版本的 `previous-latest.json`、就绪证明 `ready.json`、完成记录 `complete.json`
- 发布成功的 Homebrew `typing-pet.rb`

`dist/` 目录与敏感私钥均已在 `.gitignore` 中排除。

## 暂停与断点续传

可选择仅执行到公证打包阶段，先行审查产物：

```sh
./scripts/release.sh --prepare-only
# 检查产物无误后，基于原产物直接部署：
./scripts/release.sh --resume --github
```

`--resume` 仅适用于存在 `ready.json` 且状态就绪的构建。它跳过重复测试、编译与公证，直接复用已生成的归档文件。若源码或文件哈希发生变化则拒绝执行。

若服务器部署后 URL 校验或 GitHub 发布偶发网络波动，更新 feed 可能已推送到服务器，此时切勿修改版本号或覆写文件，直接追加 `--resume` 重新执行即可。旧 manifest 会留存供排查，不会自动回滚。

若在公证环节遇到错误或超时，先查看 `release.log` 与 `notary-result.json`。可以通过 `xcrun notarytool info <ID> --keychain-profile typingpet-notary` 查询 Apple 端的进度。排查完毕后重新运行。

## 官网与下载链接联动

本版本在官网 `typing-pet.miel.ing` 提供了五种语言的展示页与更新说明。
发布新版本前，需在 `website/src/releases.json` 中添加该版本对应的中、英、日、韩语言标题与变更条目。
缺少翻译将在构建签名阶段被拦截。

在本机配置好官网部署环境后，在 `--github` 或 `--homebrew` 发布的版本公开后，
将同步更新 `typing-pet.miel.ing` 的五种语言页面与更新说明。
发布新版本前，需在 `website/src/releases.json` 中添加该版本对应的韩语、英语、日语、简体中文与繁体中文标题与变更条目。
缺少翻译将在构建签名阶段被拦截。网站记录从 v0.16.0 开始。
这些翻译也将同步用于应用更新弹窗中的多语言变更日志。即使不公开到 GitHub 或官网、仅部署至更新服务器时，也需备齐五种语言的变更记录。
官网统一使用 `https://pet.miel.ing/latest?from=github&type=dmg`（或 zip）的下载跳转模式。
若发布应用后仅官网部署失败，无需重新编译或发布应用，只需修复原因后在根目录下运行 `./scripts/deploy_website.sh` 即可。

## 为旧版本追加 DMG 安装包

从 v0.17.1 开始提供与 ZIP 内容完全一致的 DMG 镜像安装包。
DMG 构建独立于主发布流水线：

```sh
./scripts/build_dmg.sh /absolute/path/TypingPet.app /absolute/path/TypingPetMac-v0.17.1-arm64-installer.dmg
```

该脚本检查 app 的签名与公证状态，放入 `/Applications` 替身并生成 DMG。
包含精美爪印背景、拖拽示意箭头与 136pt 大图标排布。
使用独立的 Python `dmgbuild==1.6.7` 环境制作。生成的 DMG 使用同一 Developer ID 签名并提交 Apple 公证与 staple。
随后将生成的 DMG 与 `.sha256` 上传至 GitHub Release 与更新服务器对应目录，并执行 `./scripts/deploy_website.sh` 刷新官网即可。

## 自动化测试验证

```sh
python3 -m unittest discover -s scripts -p 'test_release.py'
./scripts/check_publish_update.sh
```

此验证使用临时环境与开发测试密钥，不会产生真实的网络发布行为。
