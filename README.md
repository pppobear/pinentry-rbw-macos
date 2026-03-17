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

## 构建

```bash
cd /Users/enoch/projects/pinentry-rbw-macos
swift build -c release
```

二进制路径：

```bash
/Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos
```

## 接到 rbw

```bash
rbw config set pinentry /Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos
```

如果你使用多 profile，建议保留 `RBW_PROFILE`，这样不同 profile 会落到不同的 Keychain account。

## 管理命令

手动预存主密码：

```bash
/Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos --store
```

从标准输入预存主密码：

```bash
printf '%s' 'your-master-password' | /Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos --store-stdin
```

删除已存主密码：

```bash
/Users/enoch/projects/pinentry-rbw-macos/.build/release/pinentry-rbw-macos --clear
```

## 环境变量

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`

## 已知限制

- GUI 密码框依赖当前会话可访问桌面；SSH 等无图形会话会自动回退终端
- 当前只实现了 `rbw` 够用的最小 `pinentry` 子集
- Apple Watch 是否会在你的机器上作为系统认证选项出现，取决于 macOS、硬件和系统设置；这版没有单独强制 companion-only 策略
