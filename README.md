# pinentry-rbw-macos

[简体中文说明](./README.zh-CN.md)

A minimal macOS `pinentry` implementation for `rbw`.

It currently focuses on four things:

- Collect the Bitwarden master password with a GUI prompt on first unlock
- Prefer a macOS GUI password prompt for manual entry, with terminal fallback
- Store the password in macOS Keychain
- Use `LocalAuthentication` before reading the stored password from Keychain

This is still an MVP. The current goal is to prove out:

- The minimum `pinentry` protocol surface needed by `rbw`
- Touch ID unlock
- Letting the macOS authentication UI decide whether Apple Watch can participate when supported by the system

## Installation

Homebrew is the recommended installation path:

```bash
brew tap pppobear/tap
brew install pinentry-rbw-macos
```

If you just want to try it without Homebrew, prebuilt binaries are also available from GitHub Releases:

- <https://github.com/pppobear/pinentry-rbw-macos/releases>

## Configure `rbw`

After installing with Homebrew, point `rbw` at the installed binary:

```bash
rbw config set pinentry "$(brew --prefix)/bin/pinentry-rbw-macos"
```

If you use multiple profiles, keep `RBW_PROFILE` set consistently so each profile maps to a separate Keychain account.

## Management Commands

Seed the master password interactively:

```bash
pinentry-rbw-macos --store
```

Seed the master password from standard input:

```bash
printf '%s' 'your-master-password' | pinentry-rbw-macos --store-stdin
```

Remove the stored password:

```bash
pinentry-rbw-macos --clear
```

## Development

Build from source locally:

```bash
cd pinentry-rbw-macos
swift build -c release
```

Binary path:

```bash
./.build/release/pinentry-rbw-macos
```

If you are testing from a local source checkout, you can temporarily point `rbw` at the locally built binary:

```bash
rbw config set pinentry "$(pwd)/.build/release/pinentry-rbw-macos"
```

## Release

Pushing a `v*` tag triggers the GitHub Actions release workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Release artifacts include:

- `pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip`
- `pinentry-rbw-macos-vX.Y.Z-macos-x86_64.zip`
- matching `sha256` files

You can also run the `Release` workflow manually from GitHub Actions.
When running it manually, provide a version such as `v0.1.0`.

## Environment Variables

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`

## Known Limitations

- The GUI password prompt requires a desktop session; SSH and other headless sessions fall back to terminal input
- Only the minimum `pinentry` behavior needed by `rbw` is implemented right now
- Whether Apple Watch appears as an authentication option depends on macOS version, hardware, and system settings; this project does not force a companion-only policy
