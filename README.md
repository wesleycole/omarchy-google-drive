# Google Drive for Omarchy

A keyboard-friendly Omarchy bar widget for mounting, searching, and browsing an
existing [rclone](https://rclone.org/drive/) Google Drive remote.

Google does not provide an official Drive sync client for Linux. This plugin
uses an rclone FUSE mount instead: files remain in Google Drive, are fetched on
demand, and use rclone's local VFS cache while open.

The plugin is deliberately a thin interface over rclone. It does not install
packages, request elevated privileges, or create or modify rclone remotes.

## Features

- Mount and unmount control from the Omarchy bar
- Storage usage and recent mounted files
- Full mounted-Drive search by file name or folder path
- File-type-specific icons for documents, sheets, slides, PDFs, media, code,
  archives, and more
- Opens files and folders in Nautilus
- Optional automatic mount when Omarchy Shell starts

## Prerequisites

Before installing the plugin:

1. Install `rclone` and `fuse3` using your normal system package tooling.
2. Run `rclone config` in a terminal.
3. Create a **Google Drive** remote named `gdrive` and complete browser
   authentication.
4. Verify the remote:

```sh
rclone listremotes
rclone about gdrive:
```

`rclone listremotes` should include `gdrive:` and `rclone about` should display
storage information. If you choose a different remote name, set the plugin's
`remoteName` option after installation.

### Google OAuth client ID

rclone's shared Google Drive OAuth client is being retired during 2026. Each
user should create a personal **Desktop app** OAuth client by following
[rclone's client ID guide](https://rclone.org/drive/#making-your-own-client-id),
then enter that client ID and secret during `rclone config`.

Do not reuse or distribute another user's client credentials. The plugin does
not ship a shared client ID and never reads the client ID, client secret, or
OAuth token directly; rclone owns that configuration.

For a personal external Google OAuth app, publish the consent app to Production
to avoid Testing-mode grants expiring after seven days. Personal use generally
does not require Google verification, though Google displays an unverified-app
warning during authorization.

If `gdrive:` already uses rclone's shared client, migrate it in place:

1. Unmount Google Drive from the plugin.
2. Run `rclone config` and choose **Edit existing remote** → `gdrive`.
3. Enter your personal client ID and secret, keep the desired Drive scope, and
   replace the existing token when prompted.
4. Complete browser authorization and verify with `rclone about gdrive:`.
5. Mount Google Drive again from the plugin.

## Install

```sh
omarchy plugin add https://github.com/wesleycole/omarchy-google-drive.git --enable
```

The widget appears in the right section of the bar. With `gdrive:` configured,
it mounts at `~/Google Drive` automatically by default. If rclone or the remote
is missing, the panel shows what is required and links back to these
prerequisites without changing the system.

## Requirements

- Omarchy with the Quattro shell plugin runtime
- An existing authenticated rclone Google Drive remote
- `rclone` and `fuse3`
- Nautilus for opening and selecting mounted files

## Usage

Mouse controls:

| Input | Action |
|---|---|
| Left click | Open or close the panel |
| Right click | Refresh status and recent files |
| Middle click | Open prerequisite instructions |

Panel keyboard controls:

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move through files |
| Enter / Space | Open the selected file or activate the selected control |
| `/` | Focus file search |
| `p` | Mount or unmount Google Drive |
| `r` | Refresh |
| `l` | Open prerequisite instructions |
| `o` | Open Google Drive |
| Escape | Clear search or close the panel |

Search begins after two characters. Results include matching file names and
folder paths; selecting one opens it in Nautilus.

## Configure

Settings are stored inline with the widget entry in
`~/.config/omarchy/shell.json` and can be changed with `omarchy bar set`:

```sh
omarchy bar set io.github.wesleycole.google-drive remoteName gdrive
omarchy bar set io.github.wesleycole.google-drive mountPath "$HOME/Google Drive"
omarchy bar set io.github.wesleycole.google-drive autoMount false --json
omarchy bar set io.github.wesleycole.google-drive refreshIntervalSec 60 --json
```

| Setting | Default | Description |
|---|---:|---|
| `remoteName` | `gdrive` | Existing rclone remote name without the trailing colon |
| `mountPath` | `~/Google Drive` | Local FUSE mount folder |
| `autoMount` | `true` | Mount when Omarchy Shell starts |
| `refreshIntervalSec` | `60` | Status refresh interval |

## Diagnostics

```sh
omarchy-shell io.github.wesleycole.google-drive status
python3 ~/.config/omarchy/plugins/io.github.wesleycole.google-drive/gdrive.py \
  status --remote gdrive --mount "$HOME/Google Drive"
```

Plugin logs:

```sh
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

## Security and privileges

Omarchy plugins run unsandboxed with your user permissions. This plugin never
installs packages, requests elevated privileges, or creates or edits rclone
configuration. OAuth tokens remain in rclone's standard user configuration and
are not read directly by the plugin. Commands are executed as argument arrays
rather than interpolated shell strings.

## Remove

Unmount Google Drive with the panel toggle, then remove the plugin:

```sh
omarchy plugin remove io.github.wesleycole.google-drive --yes
```

Removing the plugin does not delete the `gdrive` rclone remote, cached files,
or installed packages.

## Development

```sh
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.wesleycole.google-drive"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" \
  "$PLUGIN_DIR/Panel.qml" \
  "$PLUGIN_DIR/Service.qml" \
  "$PLUGIN_DIR/GoogleDriveIcon.qml"
```

The plugin follows the
[Omarchy plugin development guide](https://omarchyplugins.com/develop.html).
