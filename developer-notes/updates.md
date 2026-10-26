# 自动更新机制 (Automatic Updates)

应用每天检查一次静态 JSON feed 更新源，且仅在用户主动同意后才执行安装。

| 维度 | 开发版 (Development) | 生产版 (Production) |
|---|---|---|
| Feed 路径 | 由 `UpdateFeedURL` 偏好控制，默认未设置 | `https://pet.miel.ing/update/production/latest.json` |
| Feed 协议 | HTTPS，或者针对 `localhost` / `127.0.0.1` 允许 HTTP | 仅限 HTTPS |
| 归档包校验 | 校验文件大小、SHA-256、Ed25519 签名 | 校验文件大小、SHA-256、Ed25519 签名 |
| 应用合法性检查 | 校验 Bundle ID、发布通道、构建号、有效代码签名 | 相同。运行的应用一旦拥有 Team ID，则校验 Developer ID 签名与 Apple 公证 |

Ad-hoc 生产构建没有 Team ID，因此它只信任 Ed25519 签名，可以平滑升级到第一个经过 Developer ID 签名的正式版本。
由于每个 ad-hoc 签名的特征各异，此类更新完成后 macOS 会要求重新授予输入监控权限。

更新请求不包含任何查询参数或设备标识符。服务器仅看到标准的 `URLSession` 请求头和来源 IP 地址。

## Feed 格式规范

```json
{
  "version": "0.13.0",
  "build": 19,
  "minimumSystemVersion": "13.0",
  "url": "https://pet.miel.ing/update/production/TypingPet-0.13.0-19-arm64.zip",
  "size": 7191671,
  "sha256": "…",
  "signature": "base64 编码的 zip 字节 Ed25519 签名",
  "notes": "- 更新内容说明",
  "localizedNotes": {
    "ko": "업데이트 내역\n\n• 변경 내용",
    "en": "Release notes\n\n• Changes",
    "ja": "更新内容\n\n• 変更点",
    "zh-Hans": "更新内容\n\n• 更改",
    "zh-Hant": "更新內容\n\n• 變更"
  }
}
```

`build` 对应 `CFBundleVersion`。仅当 feed 中的 build 大于当前运行应用的 build 时才提示更新。
zip 归档内部仅包含一个 `.app` bundle。

更新弹窗会根据应用当前语言设置（包括跟随系统）选择 `localizedNotes` 中的对应语言说明。若对应语言缺失或为空，则回退到英语，最后回退到传统的 `notes` 字段。旧版客户端会忽略新增的该字段并继续展示 `notes`。已安装旧版客户端的应用需先完成一次客户端更新后才能支持多语言发行说明显示。

## 安装流程

1. 下载 zip 归档至 `~/Library/Caches/<bundle id>/Updates/`。
2. 比对文件大小、SHA-256，并使用 Info.plist 中内置的公钥校验 Ed25519 签名。
3. 使用系统 `ditto` 工具解压，验证解压后应用的 bundle ID、channel 通道、build 版本号及代码签名。
4. 提示用户重启。若用户选择“稍后”，则在应用下次退出时静默安装。
5. 应用退出后，独立 helper 进程将当前旧 bundle 移至备份路径，把新 bundle 移动到原位并拉起。若移动失败则自动还原旧 bundle。
6. 下次启动时报告更新结果并清理临时缓存。

应用无法在 App Translocation 临时安全沙箱中自更新，也无法在用户无写权限的只读目录下自更新。

## 签名密钥管理

```sh
swift scripts/update_keys.swift generate production
```

密钥对默认保存在 `~/.config/typingpet/update-keys/`（可通过环境变量 `TYPINGPET_UPDATE_KEY_DIR` 覆盖）。
`build_app.sh` 会将 `<channel>.pub` 嵌入 Info.plist。生产版本如果缺失公钥将终止构建。
请妥善备份 `production.key`。正式发布的客户端仅信任对应的公钥；一旦私钥丢失，后续版本必须由用户手动重新下载安装。
严禁将 `.key` 私钥文件提交进 Git 仓库。

**已发布版本的生产密钥切勿重新生成覆盖。** 若需验证请运行：
`swift scripts/update_keys.swift check production`。该脚本会检查私钥与 `production.pub` 是否成对匹配。
此 Ed25519 私钥与 Apple Developer ID 证书无关联，切勿上传到公开网络。

## 正式发布

配置完成 Developer ID 后，推荐使用 [一键自动化发布流水线](releasing.md)：

```sh
# 更新 version.json 与 CHANGELOG.md，提交 git（若使用 --github 请推送到远程），然后：
./scripts/release.sh --dry-run --github
./scripts/release.sh --github
```

如需手动分步执行：

```sh
TYPINGPET_BUILD_CHANNEL=production TYPINGPET_VERSION=0.14.3 TYPINGPET_BUILD=23 ./scripts/build_app.sh
./scripts/notarize_release.sh
./scripts/deploy_update.sh production dist/TypingPet.app
```

`deploy_update.sh` 要求提供原始更新私钥、经过 Apple 公证的 Developer ID app 以及本地静态更新服务目录 `~/TypingPetUpdate`（可用 `TYPINGPET_UPDATE_ROOT` 或第三参数指定）。它会生成带签名的 zip 和 manifest，拒绝降级或覆写已发布版本，先拷贝 zip，最后原子替换 `latest.json`。之后会发起 HTTP 请求验证公网 URL 与本地文件的一致性。
若公网校验失败，重试前先检查服务器状态；本地 feed 可能已经完成更新。
已发布构建具备不可变性。下次发布必须自增 `CFBundleVersion`。
`latest.json` 需配置禁用 CDN 缓存。
更新日志来自 `CHANGELOG.md` 对应版本段落或 `UPDATE_NOTES`。
该兼容字段继续服务于旧版本客户端。`localizedNotes` 则从 `website/src/releases.json` 中匹配的版本自动生成（使用纯文本形式的标题与变更项）。
生产预检和正式发布在发布新 feed 前，均要求所有五种支持的语言都具备非空的说明内容（即使是仅在更新服务器发布的版本也是如此）。

注意：0.14.2 版本因旧私钥丢失轮换了生产密钥。0.14.1 及更早版本内嵌的是旧公钥，无法直接通过 feed 升级到 0.14.2，需要手动重新下载安装一次；此后的版本均可正常自动升级。

如需仅生成打包文件而不进行部署，可执行：`./scripts/publish_update.sh production dist/TypingPet.app`。

## 本地更新测试

先退出 TypingPet Dev，然后运行：

```sh
./scripts/check_update.sh
```

非 GUI 发布的验证脚本为：`./scripts/check_publish_update.sh`。

测试脚本在缺少开发密钥时会自动生成，构建 Dev 0.12.0 (18) 与 0.13.0 (19)，并在 `http://127.0.0.1:8787` 托管 feed 服务。
它会自动化测试并断言：错误签名、错误哈希、相同版本号、不安全外部链接均被正确拒绝拦截；
随后测试成功下载、安装并重新拉起新版本，最后清理 Dev 数据目录并还原 `UpdateFeedURL`。

如需手动测试交互界面：

```sh
TYPINGPET_VERSION=0.13.0 TYPINGPET_BUILD=19 ./scripts/build_app.sh dist-dev/new
./scripts/publish_update.sh development "dist-dev/new/TypingPet Dev.app"
python3 -m http.server 8787 --bind 127.0.0.1 --directory dist-dev/update-server
defaults write ing.miel.typingpet.dev.preferences UpdateFeedURL http://localhost:8787/development/latest.json
./scripts/run_dev.sh
```

然后点击托盘 DEV 菜单 > `检查更新…`。测试完毕后删除覆盖配置：`defaults delete ing.miel.typingpet.dev.preferences UpdateFeedURL`。
