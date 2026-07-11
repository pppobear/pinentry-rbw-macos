# pinentry-rbw-macos

[English README](./README.md)

`rbw` 用的最小 macOS `pinentry` 原型。

它做四件事：

- 第一次解锁时，优先用图形密码框采集 Bitwarden 主密码
- 手动输入时优先弹 macOS 图形密码框，失败时回退终端
- 把密码存进 macOS Keychain
- 后续先通过 `LocalAuthentication` 做系统认证，再读取 Keychain 中的密码

这版是 MVP，目标是先跑通：

- `rbw` 可调用的最小 `pinentry` 协议子集
- Touch ID 解锁
- 在系统支持时，让 macOS 自己决定是否允许 Apple Watch 参与认证

## 安装

优先建议通过 Homebrew 安装：

```bash
brew tap pppobear/tap
brew install pinentry-rbw-macos
```

如果你只是想快速试用，也可以直接从 GitHub Releases 下载预编译产物：

- <https://github.com/pppobear/pinentry-rbw-macos/releases>

最低支持 macOS 13。下载 release 压缩包及对应 checksum 后，请先在下载目录完成校验再解压：

```bash
shasum -a 256 -c pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip.sha256
```

## 配置 `rbw`

通过 Homebrew 安装后，直接把 `rbw` 指向安装好的二进制：

```bash
rbw config set pinentry "$(brew --prefix)/bin/pinentry-rbw-macos"
```

如果你使用多个 profile，建议始终保持 `RBW_PROFILE` 一致，这样每个 profile 都会映射到独立的 Keychain account。

只有 prompt 精确等于 `Master Password` 的请求才允许使用 Keychain 缓存。API 凭据、两步验证验证码以及未知
prompt 都必须手动输入，并且绝不写入缓存。

## 语言

程序自身的提示和命令输出支持英文与简体中文。可以通过 `--lc-messages LOCALE`、标准 Assuan
`OPTION lc-messages=LOCALE` 或 `PINENTRY_RBW_LOCALE` 选择语言：

```bash
PINENTRY_RBW_LOCALE=zh-Hans pinentry-rbw-macos --help
pinentry-rbw-macos --lc-messages zh_CN.UTF-8 --help
```

选择顺序依次是 pinentry 显式选项、`PINENTRY_RBW_LOCALE`、`LC_ALL`、`LC_MESSAGES`、`LANG`，最后才是
macOS 的首选语言列表。`zh`、`zh-Hans`、`zh-CN` 和 `zh-SG` 会使用简体中文；暂不支持的语言（包括繁体
中文 locale）会回退到英文。

Assuan 调用方通过 `SETTITLE`、`SETDESC`、`SETPROMPT`、`SETOK`、`SETCANCEL` 等命令传入的文案会原样
显示。特别是 `Master Password` 属于安全敏感的缓存选择条件，不是可翻译文案；把它翻译成“主密码”不会让
请求获得缓存资格。`LocalAuthentication` 中由 macOS 提供的系统文案仍由系统本地化；程序语言只控制回退
按钮标题，调用方提供的认证原因仍会原样显示。

## 管理命令

交互式预存主密码：

```bash
pinentry-rbw-macos --store
```

从标准输入预存主密码：

```bash
read -r -s "master_password?主密码："
printf '\n'
printf '%s' "$master_password" | pinentry-rbw-macos --store-stdin
unset master_password
```

不要把主密码直接写进 shell 命令、参数、环境变量或 shell history。

删除已存主密码：

```bash
pinentry-rbw-macos --clear
```

查看完整的本地化命令说明，或输出不随语言变化的版本号：

```bash
pinentry-rbw-macos --help
pinentry-rbw-macos --version
```

## 开发

本地源码构建：

```bash
cd pinentry-rbw-macos
swift build -c release
```

二进制路径：

```bash
./.build/release/pinentry-rbw-macos
```

如果你在本地源码目录里调试，也可以临时把 `rbw` 指向本地构建产物：

```bash
rbw config set pinentry "$(pwd)/.build/release/pinentry-rbw-macos"
```

## Release

推送符合语义化版本格式的 tag 会触发 GitHub Actions release workflow：

```bash
version=v1.2.3  # 仅作示例；请替换为下一发布版本
git tag "$version"
git push origin "$version"
```

workflow 会把已发布资产当作不可变内容：已有 tag 的 release 重新运行时必须失败，不能替换旧文件。仓库也已为
后续版本启用 GitHub immutable releases，并通过 tag ruleset 禁止删除或改写 `v*` 标签。

发布产物包括：

- `pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip`
- `pinentry-rbw-macos-vX.Y.Z-macos-x86_64.zip`
- 对应的 `sha256` 文件
- 对稳定版本，如果配置了 `HOMEBREW_TAP_GITHUB_TOKEN`，还会同步更新 `pppobear/homebrew-tap` 中的
  Homebrew formula；预发布版本不会更新稳定 tap

如果要自动更新 Homebrew tap，需要在仓库里配置名为 `HOMEBREW_TAP_GITHUB_TOKEN` 的 secret，
并确保它有权限 push 到 `pppobear/homebrew-tap`。
workflow 会在 clone tap 前验证该权限；如果资格检查报告凭据无效或缺少 push 权限，请轮换 token。

tap 更新后，用户本地还需要刷新 metadata 再升级：

```bash
brew update
brew upgrade pinentry-rbw-macos
```

## 环境变量

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`
- `PINENTRY_RBW_LOG`（已脱敏的协议元数据；默认关闭，但路径、错误与时间信息仍应按敏感信息处理）
- `PINENTRY_RBW_LOCALE`（`en` 或 `zh-Hans`；优先于标准 locale 环境变量）

## 卸载与清理

先清除 Keychain 条目，再重置 `rbw` 配置并卸载：

```bash
pinentry-rbw-macos --clear
rbw config unset pinentry
brew uninstall pinentry-rbw-macos
```

每个使用过的 `RBW_PROFILE` 都需要分别执行清理和配置重置。Homebrew 无法自动删除这些 profile 对应的
Keychain 条目。

## 安全模型

主密码会持久化到 macOS 登录 Keychain。当前实现是在读取普通 Keychain 条目前先执行
`LocalAuthentication`；认证尚未由 Keychain 条目自身强制。这能减少日常误访问，但无法防御已经以同一用户
身份运行、并能绕过或 patch 本程序的代码。

更强的目标方案是使用 Developer ID 签名、notarization，以及受 `.userPresence` 保护的 Keychain 条目。在
稳定的签名和升级路径建立前，这仍是威胁模型中的明确限制。安全问题报告方式见
[SECURITY.zh-CN.md](./SECURITY.zh-CN.md)。

## 已知限制

- GUI 密码框依赖桌面会话；SSH 或其他无图形环境会自动回退到终端输入
- 当前只实现了 `rbw` 所需的最小 `pinentry` 行为
- 程序自身文案目前只支持英文和简体中文，其他语言会回退到英文
- Apple Watch 是否会显示为认证选项，取决于 macOS 版本、硬件和系统设置；当前不会强制 companion-only 策略
