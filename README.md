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

The minimum supported system is macOS 13. After downloading a release archive and its matching checksum file,
verify it from the download directory before extracting it:

```bash
shasum -a 256 -c pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip.sha256
```

## Configure `rbw`

After installing with Homebrew, point `rbw` at the installed binary:

```bash
rbw config set pinentry "$(brew --prefix)/bin/pinentry-rbw-macos"
```

If you use multiple profiles, keep `RBW_PROFILE` set consistently so each profile maps to a separate Keychain account.

Only requests whose prompt is exactly `Master Password` are eligible for the Keychain cache. API credentials,
two-factor authentication codes, and unknown prompts must always be entered manually and are never stored.

## Management Commands

Seed the master password interactively:

```bash
pinentry-rbw-macos --store
```

Seed the master password from standard input:

```bash
read -r -s "master_password?Master password: "
printf '\n'
printf '%s' "$master_password" | pinentry-rbw-macos --store-stdin
unset master_password
```

Do not put the master password directly in a shell command, argument, environment variable, or shell history.

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

Pushing a semantic-version tag triggers the GitHub Actions release workflow:

```bash
version=v1.2.3  # example only; replace with the next release version
git tag "$version"
git push origin "$version"
```

The workflow treats published assets as immutable: rerunning a release for an existing tag fails instead of replacing
files. Repository administrators should also enable GitHub immutable releases and a protected tag ruleset for
platform-level enforcement.

Release artifacts include:

- `pinentry-rbw-macos-vX.Y.Z-macos-arm64.zip`
- `pinentry-rbw-macos-vX.Y.Z-macos-x86_64.zip`
- matching `sha256` files
- an updated Homebrew formula in `pppobear/homebrew-tap` for stable releases when
  `HOMEBREW_TAP_GITHUB_TOKEN` is configured; prereleases intentionally skip the stable tap

To update the Homebrew tap automatically, add a repository secret named `HOMEBREW_TAP_GITHUB_TOKEN`
with permission to push to `pppobear/homebrew-tap`.

After the tap has been updated, users need to refresh local metadata before upgrading:

```bash
brew update
brew upgrade pinentry-rbw-macos
```

## Environment Variables

- `RBW_PROFILE`
- `PINENTRY_RBW_SERVICE`
- `PINENTRY_RBW_ACCOUNT`
- `PINENTRY_RBW_LOG` (redacted protocol metadata; disabled by default, but paths, errors, and timing remain sensitive)

## Uninstall and cleanup

Clear the Keychain item before removing the executable, then reset `rbw` and uninstall:

```bash
pinentry-rbw-macos --clear
rbw config unset pinentry
brew uninstall pinentry-rbw-macos
```

Repeat the clear and config commands with each `RBW_PROFILE` you used. Homebrew cannot remove those profile-specific
Keychain items automatically.

## Security model

The master password is persisted in the macOS login Keychain. The current implementation performs
`LocalAuthentication` before reading a normal Keychain item; authentication is not yet enforced by the Keychain item
itself. This improves protection against casual access, but it does not defend against code already running as the
same user that can bypass or patch this program.

The intended stronger design is a Developer ID signed and notarized binary using a `.userPresence`-protected
Keychain item. Until a stable signing and upgrade path exists, this limitation remains part of the threat model.
See [SECURITY.md](./SECURITY.md) for reporting guidance.

## Known Limitations

- The GUI password prompt requires a desktop session; SSH and other headless sessions fall back to terminal input
- Only the minimum `pinentry` behavior needed by `rbw` is implemented right now
- Whether Apple Watch appears as an authentication option depends on macOS version, hardware, and system settings; this project does not force a companion-only policy
