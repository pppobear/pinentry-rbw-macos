# 安全策略

[English version](./SECURITY.md)

## 支持的版本

安全修复只提供给最新版本。如果旧版本上的行为可能已经改变，请先升级，再提交安全报告。

## 报告漏洞

当前仓库尚未启用 GitHub 私密漏洞报告。请先发送一封不含敏感信息的邮件到 `pppobear@gmail.com`，主题使用
`[SECURITY] pinentry-rbw-macos`。如果需要提供更敏感的证据，维护者会另行安排安全渠道。以后若启用
GitHub 私密漏洞报告，请优先使用该流程。

不要在公开 issue 或第一封邮件中包含真实的 Bitwarden 主密码、API 凭据、两步验证码、Keychain dump、
认证日志或其他秘密。

请说明受影响版本、macOS 版本与架构、`rbw` 版本、已脱敏的精确命令或 Assuan transcript，以及二进制来自
Homebrew 还是 GitHub Release。

## 当前信任边界

程序把主密码保存在 macOS 登录 Keychain 中，并在读取前执行 `LocalAuthentication`。当前 Keychain 条目
还没有使用 `.userPresence` 访问控制，因此这是应用层的认证门槛，无法防御已经以同一用户身份运行的任意代码。

调试日志默认关闭。排障时若启用日志，即使协议参数和返回的秘密已经脱敏，路径、错误元数据与时间信息仍可能
存在，因此也应按敏感信息处理。
