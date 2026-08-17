# Google Drive for Omarchy

A keyboard-friendly Omarchy bar widget for mounting, searching, and browsing
Google Drive with [rclone](https://rclone.org/drive/).

Google does not provide an official Drive sync client for Linux. This plugin
uses an rclone FUSE mount instead: files remain in Google Drive, are fetched on
demand, and use rclone's local VFS cache while open.

## Features

- Guided rclone installation and Google OAuth setup in a visible terminal
- Mount and unmount control from the Omarchy bar
- Storage usage and recent mounted files
- Full mounted-Drive search by file name or folder path
- File-type-specific icons for documents, sheets, slides, PDFs, media, code,
  archives, and more
- Opens files and folders in Nautilus
- Optional automatic mount when Omarchy Shell starts

## Install

```sh
omarchy plugin add https://github.com/wesleycole/omarchy-google-drive.git --enable
```

The widget appears in the right section of the bar. Click it and choose
**Install & connect Google Drive**. The setup opens a visible terminal, installs
`rclone` and `fuse3` through `omarchy pkg add` when needed, and starts Google
OAuth. The default rclone remote is named `gdrive` and mounts at
`~/Google Drive`.

## Requirements

- Omarchy with the Quattro shell plugin runtime
- A Google account
- `rclone` and `fuse3` (the guided setup can install both)
- Nautilus for opening and selecting mounted files

## Usage

Mouse controls:

| Input | Action |
|---|---|
| Left click | Open or close the panel |
| Right click | Refresh status and recent files |
| Middle click | Open Google Drive connection setup |

Panel keyboard controls:

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move through files |
| Enter / Space | Open the selected file or activate the selected control |
| `/` | Focus file search |
| `p` | Mount or unmount Google Drive |
| `r` | Refresh |
| `l` | Open connection setup |
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
| `remoteName` | `gdrive` | rclone remote name without the trailing colon |
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

Omarchy plugins run unsandboxed with your user permissions. This plugin does
not store Google credentials. OAuth tokens remain in rclone's standard user
configuration. Package installation is deliberately launched in a visible
terminal so `omarchy pkg add` can request sudo authentication normally.
Commands are executed as argument arrays rather than interpolated shell
strings.

rclone currently warns that its shared Google Drive OAuth client is being
retired during 2026. For long-term use, follow rclone's
[client ID guide](https://rclone.org/drive/#making-your-own-client-id) and add
your own Google OAuth client to the configured remote.

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
  "$PLUGIN_DIR/BarWidget.qml" \
  "$PLUGIN_DIR/Panel.qml" \
  "$PLUGIN_DIR/Service.qml" \
  "$PLUGIN_DIR/GoogleDriveIcon.qml"
```

The plugin follows the
[Omarchy plugin development guide](https://omarchyplugins.com/develop.html).
