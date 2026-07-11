# Security policy

## Supported versions

Security fixes are provided for the latest release. Older releases should be upgraded before reporting behavior that
may already have changed.

## Reporting a vulnerability

Private vulnerability reporting is not currently enabled for this repository. Send an initial, redacted report to
`pppobear@gmail.com` with the subject `[SECURITY] pinentry-rbw-macos`; the maintainer can arrange a safer channel if
more sensitive evidence is needed. If GitHub private vulnerability reporting is enabled later, prefer that flow.

Do not include a real Bitwarden master password, API credential, two-factor code, Keychain dump, authentication log,
or other secret in a public issue or the initial email.

Include the affected version, macOS version and architecture, `rbw` version, the exact command or Assuan transcript
with secrets redacted, and whether the binary came from Homebrew or a GitHub release.

## Current trust boundary

The application stores the master password in the macOS login Keychain and performs `LocalAuthentication` before
reading it. The Keychain item is not currently protected by a `.userPresence` access-control policy, so this is an
application-layer gate rather than a defense against arbitrary code already running as the same user.

Debug logs are disabled by default. If enabled for diagnosis, treat them as sensitive because paths, error metadata,
and timing may be present even though protocol arguments and returned secret data are redacted.
