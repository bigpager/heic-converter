# heic-converter

A double-click macOS installer that watches `~/Downloads` and auto-converts `.heic` /
`.HEIC` files to PNG, JPG, or both. Runs as a `launchd` `WatchPaths` agent (not an
Automator Folder Action — those can silently miss AirDropped files that get written via
a temp name and renamed).

## Layout

```
heic-converter/
├── Install.command          double-click entry point (native format-picker dialog)
├── scripts/
│   ├── install.sh            core installer (also runnable from CLI: --format png|jpg|both)
│   ├── heic-watch.sh          the actual conversion logic, run by the launchd agent
│   └── uninstall.sh           removes agent, script, and config
├── config/
│   └── config.conf.example    reference copy of the config install.sh generates
├── build/
│   └── sign-and-notarize.sh   codesign + notarytool submission (run locally, uses your keychain)
└── README.md
```

## How the format toggle works

`install.sh` (called either directly or via the `Install.command` dialog) writes the
chosen format to:

```
~/Library/Application Support/heic-converter/config.conf
```

`heic-watch.sh` (the script the launchd agent actually runs) sources this file fresh on
every invocation. That means **switching PNG ⇄ JPG ⇄ Both later doesn't require
reinstalling** — just edit `config.conf` and the next file dropped in Downloads uses the
new setting. Re-running the installer (CLI or double-click) is just a convenience for
resetting it via prompt instead of a text editor.

## Quick start (dev loop, no signing)

```bash
cd heic-converter
chmod +x Install.command scripts/*.sh
./scripts/install.sh --format both      # non-interactive, for iterating fast
# or: ./Install.command                  # full GUI experience with the dialog
```

Then grant Full Disk Access to `/bin/zsh` (System Settings → Privacy & Security → Full
Disk Access) — this is the one step that can never be automated, by design on Apple's
part, regardless of signing/notarization status.

Test:
```bash
tail -f ~/Library/Logs/heic-converter.log
```
Drop a `.heic` in Downloads and watch for `OK (png): ...` / `OK (jpg): ...` lines.

## Signing & notarization

You mentioned you have a paid Apple Developer account — `build/sign-and-notarize.sh` is
set up to use it, but **has not been run**, since it needs credentials that only exist on
your actual machine (Keychain Access certs, `notarytool` stored credentials). One-time
setup is documented at the top of that script. Once set up:

```bash
./build/sign-and-notarize.sh "Developer ID Application: Your Name (TEAMID)"
```

This signs `Install.command` and everything in `scripts/`, then submits the bundle to
Apple's notary service. One caveat worth knowing going in: **loose scripts (`.command`
files) can't be "stapled"** the way `.app` bundles or `.pkg` installers can — stapling
embeds the notarization ticket directly in the file so Gatekeeper can verify it offline.
A signed-but-unstapled script still avoids the scary "unidentified developer, no way to
open it" dialog, but it does a quick online check with Apple on first launch instead
(fast, automatic, no user action needed) — a meaningfully smoother experience than
today's unsigned version, just not literally zero-friction.

**Going further:** if you want a fully stapled, works-fully-offline artifact, the next
step would be wrapping this as a `.pkg` installer (via `pkgbuild`) or a proper `.app`
bundle instead of a bare `.command` file — both support stapling. Worth discussing with
Claude Code if the friction from the online check ever actually matters in practice; for
a personal/small-distribution tool it usually doesn't.

## Distributing to someone else

```bash
cd build && ./sign-and-notarize.sh "Developer ID Application: ..."
# produces dist/HEIC-Converter-Installer.zip, signed + notarized
```

Send them that zip. They: unzip → double-click `Install.command` → pick a format from
the dialog → grant Full Disk Access when prompted → done.

## Uninstall

```bash
./scripts/uninstall.sh
```

Removes the launchd agent, the installed script, and the config directory. Leaves any
images already converted untouched, and leaves the Full Disk Access grant in place
(remove that manually in System Settings if you want it gone too).

## Known constraints worth keeping in mind while iterating

- `WatchPaths` fires on *any* filesystem change in Downloads, not just new HEICs — cheap
  no-op for the script (it skips files with an existing matching output), but worth
  knowing if you ever want to optimize.
- Full Disk Access is granted to `/bin/zsh` itself, not to this specific script — that's
  the coarsest-grained option available via this mechanism. A signed `.app` bundle could
  instead request access scoped to itself, which is arguably a nicer permission story
  long-term if this grows beyond a personal tool.
- `sips`'s accepted values for JPEG `formatOptions` (quality) have varied across macOS
  versions — some want `low`/`normal`/`high`/`best`, others `0-100`. If JPG conversion
  ever starts failing after an OS update, check `~/Library/Logs/heic-converter.log` and
  `/tmp/heicconverter.err.log` first.
