# heic-converter

A signed, notarized macOS installer that watches `~/Downloads` and auto-converts
`.heic` / `.HEIC` files to PNG, JPG, or both. Runs as a `launchd` `WatchPaths`
agent (not an Automator Folder Action — those can silently miss AirDropped files
that get written via a temp name and renamed).

Conversion uses `sips`, the image tool built into macOS, so there are no
dependencies to install and nothing leaves the machine.

## Install

Download `HEIC-Converter-<version>.pkg` from the releases and double-click it.
No Terminal required: the installer sets everything up, adds a **HEIC
Converter** app to your Applications folder, and opens it so you can choose
settings.

The one step that can't be automated is granting **Full Disk Access** — Apple
deliberately gives installers no way to request it. System Settings → Privacy &
Security → Full Disk Access → **+** → Cmd-Shift-G → `/bin/zsh` → switch it on.

The grant goes to `/bin/zsh` rather than to this tool because that's the
interpreter macOS sees running the watcher; it's the finest granularity this
mechanism offers. Watching a folder *outside* Downloads, Desktop, and Documents
needs no permission at all, since only those are TCC-protected.

## Settings

Defaults are **both** formats, **90%** JPEG quality, watching **`~/Downloads`**.

Open **HEIC Converter** from your Applications folder to change them (or run
`heic-converter setup` from a shell — same window):

```
┌─ heic-converter ─────────────────────────┐
│                                          │
│   Convert to PNG                  (  ●)  │
│   Convert to JPG                  (  ●)  │
│      Quality  [ 90 ] %                   │
│   ────────────────────────────────────   │
│   Watch folder                           │
│   ~/Downloads                 [ Browse… ]│
│                                          │
│                              [   Done  ] │
└──────────────────────────────────────────┘
```

PNG and JPG are independent switches: either, both, or neither. Turning both off
stores `FORMAT="none"` and pauses conversion — the agent stays installed and
watching, it just stops producing output, and the window says so. The quality
field greys out when JPG is off, since it means nothing for PNG. Changes apply
as you make them; **Done** just closes the window.

The window is built with AppKit via JavaScript for Automation, so it needs no
compiled binary and no extra signing. On a machine where it can't start,
`setup` falls back to sequential prompts automatically; `setup --dialogs`
forces that mode, which is what you want over SSH.

Or set everything individually:

```bash
heic-converter format both              # png | jpg | both | none
heic-converter quality 90               # 0-100
heic-converter watch-folder ~/Pictures  # rebuilds the agent
```

Format and quality take effect on the next converted file — `heic-watch.sh`
re-reads its config on every run, so there is no reinstall and no logout. The
watch folder is different: launchd bakes it into the agent's `WatchPaths`, so
changing it regenerates and reloads the agent. `watch-folder` and `setup` do
that for you; if you hand-edit `WATCH_DIR` in `config.conf`, run
`heic-converter install-agent` afterwards. `heic-converter doctor` reports it
if the two ever disagree.

## Other commands

```bash
heic-converter status           # agent, config, watch folder
heic-converter doctor           # diagnose "it isn't converting"
heic-converter run              # convert everything in the folder now
heic-converter logs             # follow the conversion log
heic-converter uninstall        # remove everything
```

## Layout

```
heic-converter/
├── Install.command            double-click entry point for a source checkout (dev)
├── VERSION                    single source of truth for the release version
├── Makefile                   check / pkg / notarize / release
├── scripts/
│   ├── heic-converter          the installed CLI
│   ├── heic-watch.sh           conversion logic, run by the launchd agent
│   ├── install.sh              dev-mode install, straight from a checkout
│   └── uninstall.sh            removes agent, files, and config
├── packaging/
│   ├── app-launcher.applescript  source for HEIC Converter.app
│   ├── distribution.xml        productbuild definition
│   ├── preinstall              stops the running agent before upgrade
│   ├── postinstall             wires up the per-user agent after install
│   ├── setup-agent.sh          the per-user setup itself (shared with the CLI)
│   ├── settings-ui.js          the settings window (AppKit via JXA)
│   └── resources/              installer welcome + conclusion screens
├── build/
│   ├── build-pkg.sh            pkgbuild + productbuild + productsign
│   └── notarize.sh             notarytool + stapler + verification
├── config/config.conf.example  reference copy of the generated config
└── docs/SIGNING.md             certificates, credentials, troubleshooting
```

## How the install is put together

A `.pkg` runs as **root**, but the watcher has to run as **you** — it reads your
`~/Downloads` and writes converted images next to the originals. So the install
has two halves:

- The **payload** is system-wide and inert: the watcher and CLI under
  `/usr/local`, plus `HEIC Converter.app` in `/Applications`.
- The **`postinstall`** script figures out who actually double-clicked the
  installer, then writes that user's config and LaunchAgent and loads it.

`packaging/setup-agent.sh` does that second half, and is the same code
`heic-converter install-agent` runs, so there is one implementation rather than
two that can drift.

Installing also retires the pre-1.0 `com.$USER.heicconverter` agent if the
machine has one, so an upgrade from the old `.command` installer doesn't leave
two watchers running over the same folder. Your existing format setting is kept.

## Building a release

```bash
make check      # syntax-check every script, validate the XML — runs anywhere
make pkg        # build + sign
make notarize   # submit to Apple, staple the ticket, verify
```

`make release` runs all three. Certificates and credentials are covered in
[docs/SIGNING.md](docs/SIGNING.md) — the short version is that a `.pkg` needs a
**Developer ID Installer** certificate, which is *not* the same as the Developer
ID Application certificate used for signing binaries.

## Why a `.pkg`

This started as a signed `.zip` of loose `.command` scripts. That works, but
loose scripts **cannot be stapled**: Gatekeeper has to check with Apple online
the first time they run, which needs a network and fails awkwardly without one.

`stapler` only supports `.pkg`, `.app`, `.dmg`, and disk images. Packaging as a
`.pkg` means the notarization ticket is embedded in the file itself, so it
installs with no warning and no network round-trip — including on a Mac that has
never encountered it. It also gets a real install receipt, a proper uninstall
story, and an Installer UI that can explain the Full Disk Access step at the
point the user needs it.

## Dev loop, without signing

```bash
./scripts/install.sh --format both     # points the agent at this checkout
./Install.command                      # same, then opens the settings window
```

The agent runs `heic-watch.sh` from the checkout, so edits take effect on the
next dropped file. Both use the same launchd label as the `.pkg`, so you can't
accidentally end up with two watchers.

```bash
tail -f ~/Library/Logs/heic-converter.log
```

## Uninstall

```bash
heic-converter uninstall
```

Removes the agent, config, and installed files, and forgets the package
receipt. Already-converted images are left alone, as is the Full Disk Access
grant for `/bin/zsh` — remove that in System Settings if you want it gone.

## Known constraints

- `WatchPaths` fires on *any* change in Downloads, not just new HEICs. That's a
  cheap no-op — the script skips files that already have a matching output.
- Full Disk Access is granted to `/bin/zsh`, not to this tool specifically,
  which means it applies to every zsh script you run. A signed `.app` bundle
  could scope the grant to itself, which would be a better permission story if
  this ever grows past a personal tool.
- `sips`'s accepted values for JPEG `formatOptions` have varied across macOS
  versions — some want `low`/`normal`/`high`/`best`, others `0-100`. If JPG
  conversion starts failing after an OS update, check
  `~/Library/Logs/heic-converter.log` first.
- The `.pkg` can't host the settings UI. Installer's Customize pane only does
  fixed checkboxes declared in `distribution.xml` — there is no folder-browse
  widget, and a real one would need a compiled Installer plugin. An `osascript`
  prompt in a `postinstall` isn't an option either, since a dismissed dialog
  would fail the install. So the dialogs live in `heic-converter setup`, which
  the installer's final screen points at and `Install.command` calls directly.
