# Bing Wallpaper
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-macOS-blue?style=for-the-badge&logo=apple&logoColor=white)

A lightweight macOS menu bar app that downloads the Bing daily wallpaper and sets it on all desktops.

## :bookmark: Overview

Bing Wallpaper runs silently in the macOS menu bar and keeps your desktop fresh with the Bing photo of the day. Key features:

- **Menu bar app** — no Dock icon; accessible via a status bar icon
- **Run on demand** or on a configurable daily schedule via a LaunchAgent
- **Watermark** — optionally stamps the image title and description in the lower-left corner
- **Multi-screen** — sets the wallpaper on every connected desktop/display
- **Settings window** — configure schedule time, market/language, resolution, wallpaper folder, and log retention
- **Log viewer** — open the latest run log directly from the menu

The app wraps a bash script (`bing-wallpaper.sh`) that fetches the Bing image API, downloads the wallpaper at the requested resolution, optionally applies a watermark using a bundled Swift helper, and applies the image via `osascript`/System Events.

## :wrench: Configuration

All settings are persisted to `~/Library/Application Support/BingWallpaper/settings.json` and configurable via the Settings window (⌘,).

### Settings

| Setting             | Description                                        | Default                        |
| ------------------- | -------------------------------------------------- | ------------------------------ |
| `scheduledHour`     | Hour to run the daily update (0–23)                | `6`                            |
| `scheduledMinute`   | Minute to run the daily update (0–59)              | `0`                            |
| `market`            | Bing market/language for wallpaper selection       | `en-US`                        |
| `resolution`        | Image resolution to download                       | `UHD`                          |
| `wallpaperDir`      | Folder where wallpaper images are saved            | `~/Pictures/BingWallpaper`     |
| `logRetentionDays`  | Number of days to keep log files                   | `7`                            |
| `enableWatermark`   | Stamp image title and description on the wallpaper | `true`                         |

### :dvd: Configuration Details

The bash script also accepts configuration via environment variables (set automatically by the app):

| Variable                      | Description                                  |
| ----------------------------- | -------------------------------------------- |
| `BINGWALLPAPER_LOG_DIR`       | Directory for log files                      |
| `BINGWALLPAPER_WALLPAPER_DIR` | Directory to save downloaded wallpapers      |
| `BINGWALLPAPER_MARKET`        | Bing market code (e.g. `en-US`, `ja-JP`)     |
| `BINGWALLPAPER_RESOLUTION`    | Resolution string (e.g. `UHD`, `1920x1080`)  |
| `BINGWALLPAPER_WATERMARK`     | `1` to enable watermark, `0` to disable      |
| `BINGWALLPAPER_LOG_RETENTION` | Number of days before log files are purged   |

Supported markets: `en-US`, `en-GB`, `en-AU`, `de-DE`, `fr-FR`, `ja-JP`, `zh-CN`, `pt-BR`

Supported resolutions: `UHD`, `1920x1080`, `1366x768`, `1280x720`

## :rocket: Usage

### Prerequisites

- macOS 12 or later
- Xcode Command Line Tools (for `swiftc`)
- `curl` and `python3` (both included with macOS)
- Automation permission granted to the app (System Settings → Privacy & Security → Automation)

### Installation

```bash
# Clone the repo and build
git clone <repo-url>
cd bing-wallpaper
./build.sh
```

### Running the Application

```bash
# After building, move to Applications
mv build/BingWallpaper.app /Applications/

# Launch
open /Applications/BingWallpaper.app
```

On first launch the app installs a LaunchAgent (`com.nnet.bing-wallpaper`) that runs the wallpaper update daily at the configured time. Add the app to **System Settings → General → Login Items** to have it start automatically at login.

## :outbox_tray: Output

1. **Wallpaper** — saved as `~/Pictures/BingWallpaper/bing-YYYY-MM-DD.jpg`; only today's image is kept (previous files are deleted automatically)
2. **Logs** — timestamped files written to `~/Library/Logs/BingWallpaper/BingWallpaper_<timestamp>.log`; files older than `logRetentionDays` are purged on each run
3. **Status indicator** — the menu bar icon changes to a spinning arrow while a download is in progress; the menu header shows the last run time with a ✓/✗ result indicator

## :sos: Troubleshooting

- **Wallpaper doesn't change after setting**: The app restarts `WallpaperAgent` after applying the wallpaper to bypass the same-path cache. If this fails, log out and back in.
- **"Never run" shown in menu**: The LaunchAgent may not be loaded. Toggle it via **Enable Daily Schedule** in the menu, or run manually with **Run Now**.
- **Automation permission denied**: Go to System Settings → Privacy & Security → Automation and ensure Bing Wallpaper has permission to control System Events.
- **Build fails**: Ensure Xcode Command Line Tools are installed: `xcode-select --install`

## :scroll: Notes

- The app runs as a `LSUIElement` (no Dock icon). Use the menu bar icon to access all controls.
- Only the current day's wallpaper is stored; the folder will never grow beyond one image.
- The watermark is rendered by `Resources/add-watermark.swift`, compiled at runtime via `/usr/bin/swift`.
- The LaunchAgent plist is written to `~/Library/LaunchAgents/com.nnet.bing-wallpaper.plist` and updated automatically when the schedule is changed in Settings.
