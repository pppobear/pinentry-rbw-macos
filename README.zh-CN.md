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

## 配置 `rbw`

通过 Homebrew 安装后，直接把 `rbw` 指向安装好的二进制：

```bash
rbw config set pinentry "$(brew --prefix)/bin/pinentry-rbw-macos"
```

如果你使用多个 profile，建议始终保持 `RBW_PROFILE` 一致，这样每个 profile 都会映射到独立的 Keychain account。

## 管理命令

交互式预存主密码：

```bash
pinentry-rbw-macos --store
```

从标准输入预存主密码：

```bash
printf '%s' 'your-master-password' | pinentry-rbw-macos --store-stdin
```

删除已存主密码：

```bash
pinentry-rbw-macos --clear
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

推送 `v*` tag 会触发 GitHub Actions release workflow：

```bash
git tag v0.1.0
git push origin v0.1.0
```

发布产物包括：

- `pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip`
- `pinentry-rbw-macos-vX.Y.Z-macos-x86_64.zip`
- 对应的 `sha256` 文件
- 如果配置了 `HOMEBREW_TAP_GITHUB_TOKEN`，还会同步更新 `pppobear/homebrew-tap` 中的 Homebrew formula

你也可以在 GitHub Actions 里手动运行 `Release` workflow。
手动运行时，填写类似 `v0.1.0` 这样的版本号。
如果要自动更新 Homebrew tap，需要在仓库里配置名为 `HOMEBREW_TAP_GITHUB_TOKEN` 的 secret，
并确保它有权限 push 到 `pppobear/homebrew-tap`。

tap 更新后，用户本地还需要刷新 metadata 再升级：

```bash
brew update
brew upgrade pinentry-rbw-macos
```

## 环境变量

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`

## 已知限制

- GUI 密码框依赖桌面会话；SSH 或其他无图形环境会自动回退到终端输入
- 当前只实现了 `rbw` 所需的最小 `pinentry` 行为
- Apple Watch 是否会显示为认证选项，取决于 macOS 版本、硬件和系统设置；当前不会强制 companion-only 策略
- 当前解锁流程是在应用层做保护：先通过 `LocalAuthentication` 完成认证，再读取普通 Keychain 条目。这和使用 `.userPresence` 强制保护的 Keychain 条目不是一回事。
- 这是当前项目约束下有意做出的实现选择：由于没有 Apple 开发者账号，项目无法建立一条稳定可分发的签名 / entitlement 链路来支持 `.userPresence` 保护的 Keychain 条目。
- 因此它更适合提升日常使用场景下的保护强度，而不是防御已经能以当前用户身份运行代码，并绕过或 patch 本程序读取路径的本地攻击者。
