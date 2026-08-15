# Signing and notarizing the installer

One-time setup, then two commands per release.

## What you need, and what you don't

A `.pkg` is signed with a **Developer ID Installer** certificate. That is a
*different certificate* from the **Developer ID Application** one, which signs
executables.

This project's payload is entirely shell scripts. There is no Mach-O code in it,
so there is nothing for a Developer ID Application certificate to sign, and it
plays no part in the build. If you set one up for the earlier `.zip`-based
flow, it is simply unused now.

You need, once:

1. A Developer ID Installer certificate in your keychain.
2. Notarization credentials stored under a keychain profile.

Both require a paid Apple Developer Program membership.

## 1. Developer ID Installer certificate

Easiest path, via Xcode:

- **Xcode → Settings → Accounts**
- select your team → **Manage Certificates…**
- **+** → **Developer ID Installer**

Or through the portal, if you'd rather not install Xcode:

- Keychain Access → **Certificate Assistant → Request a Certificate From a
  Certificate Authority**, save the CSR to disk
- <https://developer.apple.com/account/resources/certificates> → **+** →
  **Developer ID Installer** → upload the CSR
- download the resulting `.cer` and double-click to add it to your keychain

Creating Developer ID certificates requires the **Account Holder** role. If the
option is greyed out, that's why.

Confirm it landed:

```bash
security find-identity -v | grep "Developer ID Installer"
```

`build-pkg.sh` runs this itself and picks the certificate up automatically, so
you only need `--identity` if you hold more than one.

## 2. Notarization credentials

Create an app-specific password at <https://appleid.apple.com> (Sign-In and
Security → App-Specific Passwords) — your normal Apple ID password will not
work — then store it once:

```bash
xcrun notarytool store-credentials "heic-converter-notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

The profile name `heic-converter-notary` is what `notarize.sh` expects; pass
`--profile` if you name it something else. Your Team ID is the parenthesised
code in the certificate name, and is listed at
<https://developer.apple.com/account> under Membership.

## Building a release

```bash
make check      # syntax-check scripts, validate XML
make pkg        # build + sign  -> dist/HEIC-Converter-<version>.pkg
make notarize   # submit, staple, verify
```

or `make release` to run all three. Bump `VERSION` first; the file is the single
source of truth for the version in the package identifier, the filename, and
`heic-converter version`.

For a local test build with no certificate at all:

```bash
make unsigned
```

That package installs on your own machine if you right-click → Open, but
Gatekeeper will reject it anywhere else and it cannot be notarized.

## Why stapling is the point

Notarization and stapling are two separate things:

- **Notarizing** uploads the package to Apple, which scans it and records a
  ticket on its servers.
- **Stapling** attaches that ticket *to the package file itself*.

Without stapling, Gatekeeper has to ask Apple's servers about the package the
first time it runs. That is usually fast, but it needs a working network, and
it fails awkwardly offline.

The previous `.zip` of loose `.command` scripts could be notarized but **not**
stapled — `stapler` only works on `.pkg`, `.app`, `.dmg`, and disk images. That
limitation is exactly why this is a `.pkg` now: `make notarize` staples, so the
installer verifies entirely offline, on a Mac that has never seen it before.

## Verifying before you send it

```bash
pkgutil --check-signature dist/HEIC-Converter-1.0.0.pkg   # signed, and by whom
xcrun stapler validate    dist/HEIC-Converter-1.0.0.pkg   # ticket attached
spctl --assess --type install -vv dist/HEIC-Converter-1.0.0.pkg
```

`notarize.sh` runs all three. Note the `--type install` on `spctl`: the default
policy is for applications and reports a confusing failure on an installer
package.

The honest end-to-end test is a Mac that has never seen the package —
ideally with the network off, which is the case stapling exists to handle.

## Troubleshooting

**`no 'Developer ID Installer' certificate found`** — you likely have the
*Application* certificate only. They are not interchangeable; see step 1.

**Notarization status `Invalid`** — `notarize.sh` fetches the detailed log
automatically. Manually:

```bash
xcrun notarytool log <submission-id> --keychain-profile "heic-converter-notary"
```

**`Team is not yet configured for notarization`** — a Program membership that
hasn't finished provisioning, or unsigned agreements. Check for outstanding
contracts in App Store Connect.

**`The signature of the binary is invalid`** — usually a package signed with the
Application certificate instead of the Installer one.

**Package installs, but nothing converts** — that's not a signing problem.
Gatekeeper and TCC are separate systems: a perfectly signed installer still
can't grant itself permission to read your Downloads folder. Run
`heic-converter doctor`.
