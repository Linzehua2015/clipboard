# ClipHistory

Lightweight native clipboard history for macOS.

ClipHistory runs in the macOS menu bar, records text clipboard history locally, and lets you open a history window with `Cmd+Shift+V`. After selecting an item, press `Enter` or double-click to copy it back to the clipboard and paste it into the current app.

## Features

- Native macOS app written in Swift
- Global shortcut: `Cmd+Shift+V`
- Text-only clipboard history
- Up to 1000 history items
- Automatically removes entries older than 7 days
- Menu bar icon with manual quit action
- Single-instance protection
- Can be packaged as a standalone `.app`
- No server, no port, no cloud sync

## Requirements

- macOS 12+
- Apple Silicon Mac recommended
- Accessibility permission for automatic paste

## Quick Start

### Build

```bash
./build.sh
```

This generates:

```bash
./cliphistory
```

### Run

```bash
./cliphistory
```

After launch:

- a clipboard icon appears in the macOS menu bar
- press `Cmd+Shift+V` to open clipboard history
- use arrow keys to move selection
- press `Enter` or double-click to use the selected item

## Permissions

On first run, allow ClipHistory in:

- `System Settings -> Privacy & Security -> Accessibility`

Without this permission, history still works, but automatic paste may fail.

## Install As App

Build a distributable app bundle:

```bash
./package.sh
```

This generates:

```bash
./ClipHistory.app
```

Then launch it by double-clicking `ClipHistory.app`.

## Auto Start On Login

Install the LaunchAgent:

```bash
./install_launchagent.sh
```

This will register ClipHistory to start automatically after login.

To stop auto-start:

```bash
launchctl unload "$HOME/Library/LaunchAgents/com.user.cliphistory.native.plist"
```

To start it again:

```bash
launchctl load "$HOME/Library/LaunchAgents/com.user.cliphistory.native.plist"
```

## Package For Sharing

Create a zip archive:

```bash
zip -r ClipHistory.zip ClipHistory.app
```

You can then share either:

- `ClipHistory.app`
- `ClipHistory.zip`

Recipients only need to unzip and double-click the app.

## Data Storage

Clipboard history is stored locally at:

```bash
~/.local/share/cliphistory/history.json
```

Runtime files:

```bash
~/.local/share/cliphistory/.lock
~/.local/share/cliphistory/native.log
~/.local/share/cliphistory/native.err
```

## Menu Bar

When the app is running, a clipboard icon appears in the top-right macOS menu bar.

Available action:

- `Quit ClipHistory`

## Project Structure

- `ClipHistory.swift`: main app source
- `build.sh`: builds the native binary
- `package.sh`: creates `ClipHistory.app`
- `install_launchagent.sh`: installs auto-start on login
- `gen_icon.swift`: generates the app icon

## Development

Rebuild after changing source:

```bash
./build.sh
```

Repackage after changing source or icon:

```bash
./package.sh
```

## Known Limitations

- Only text clipboard content is stored
- Automatic paste depends on Accessibility permission
- Clipboard history is local only

## License

Add a license before publishing publicly, for example:

- MIT
- Apache-2.0

## Contributing

Issues and pull requests are welcome.