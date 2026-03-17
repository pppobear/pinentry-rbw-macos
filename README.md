# pinentry-rbw-macos

`rbw` 用的最小 macOS `pinentry` 原型。

它做三件事：

- 第一次解锁时，优先用图形密码框采集 Bitwarden 主密码
- 手动输入时优先弹 macOS 图形密码框，失败时回退终端
- 把密码存进 macOS Keychain
- 后续先通过 `LocalAuthentication` 做系统认证，再读取 Keychain 中的密码

这版是 MVP，目标是先跑通：

- `rbw` 可调用的 `pinentry` 协议最小子集
- Touch ID 解锁
- 在支持的系统配置下，尽量让系统认证界面自行决定是否允许 Apple Watch 参与认证

## 安装

优先建议通过 Homebrew 安装：

```bash
brew tap pppobear/tap
brew install pinentry-rbw-macos
```

如果你只想先试用，也可以直接从 GitHub Releases 下载预编译产物：

- <https://github.com/pppobear/pinentry-rbw-macos/releases>

## 接到 rbw

Homebrew 安装后，直接把 `rbw` 指向 Homebrew 的二进制：

```bash
rbw config set pinentry "$(brew --prefix)/bin/pinentry-rbw-macos"
```

如果你使用多 profile，建议保留 `RBW_PROFILE`，这样不同 profile 会落到不同的 Keychain account。

## 管理命令

手动预存主密码：

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

```bash
cd pinentry-rbw-macos
swift build -c release
```

二进制路径：

```bash
./.build/release/pinentry-rbw-macos
```

如果你在本地源码目录里调试，也可以临时把 `rbw` 指向构建产物：

```bash
rbw config set pinentry "$(pwd)/.build/release/pinentry-rbw-macos"
```

## Release

推送 `v*` tag 会自动触发 GitHub Actions：

```bash
git tag v0.1.0
git push origin v0.1.0
```

发布产物会包含：

- `pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip`
- 对应的 `sha256` 校验文件

手动触发也可以直接在 GitHub Actions 里运行 `Release` workflow。
手动触发时填写版本号，例如 `v0.1.0`。

## 环境变量

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`

## 已知限制

- GUI 密码框依赖当前会话可访问桌面；SSH 等无图形会话会自动回退终端
- 当前只实现了 `rbw` 够用的最小 `pinentry` 子集
- Apple Watch 是否会在你的机器上作为系统认证选项出现，取决于 macOS、硬件和系统设置；这版没有单独强制 companion-only 策略
