# Changelog

## 1.3.0 — Known bug fixes and expanded motion collection

- Add 80 motion wallpapers: ten distinct styles with eight palettes each; retain the original nine (89 total).
- Share original wave geometry, colours, vector scenes and motion parameters across macOS and Windows.
- Use matching artwork in library previews, desktop playback and screen savers.
- Remove Windows Preview labeling; publish standard Windows x64 and ARM64 downloads.
- Generate and retain real JPEG thumbnails for new and existing Windows video imports, with bounded sequential decoding and cache cleanup.
- Fix Windows fullscreen pause falsely triggered by desktop/own/normal maximized windows; compare the visible client area instead of outer resize borders.
- Preserve the installed OpenWall screen saver when syncing native wallpaper; render saver motion with native Core Graphics.
- Leave the current Mac wallpaper as a still frame on Quit, with two bounded snapshot files per display.
- Add a clearly named Windows launcher and first-run/update instructions to the ZIP.

## 1.2.1

- Experimental native live lock-screen sync on macOS 26+, using your current wallpaper and per-user aerial cache.
- Matching high-resolution thumbnails for preparation, battery pause, older macOS, and processing failures.
- Pause desktop playback while the session is locked.
- Back up the original native wallpaper configuration and provide a restore action.
- Reuse up to three prepared videos across launches and remove replaced OpenWall native-cache entries.
- Include third-party attribution for the native wallpaper schema.

Native locked-session playback still needs visual verification. Windows remains the unchanged 1.2.0 preview.

## 1.2.0

- Click any wallpaper card to apply immediately, with no separate Set wallpaper step.
- Ordered playlists with per-wallpaper timers: 1 day, 6 hours, 3 hours, 1 hour, 30 minutes, 5 minutes, Forever.
- Pause-aware countdowns, reordering, next, stop, saved progress, and old Mac shuffle migration.
- Six new original motion palettes, expanding the collection to nine wallpapers.
- Bundled Mac screen saver that reads the current wallpaper from the local library.
- Native Windows preview for x64 and ARM64, with local WebView2 rendering, Explorer wallpaper hosting, playlists, tray controls, and power/full-screen/session-lock pause.
- Windows screen-saver modes and a still lock-screen image action.

Windows downloads and screen-saver support have separate verification limits; see VALIDATION.md.

## 1.1.0

First public release.

- Silent, looping local video wallpapers using AVFoundation.
- Three original animated presets: Northern lights, Afterglow, and Deep current.
- Per-display wallpaper selection and saved local libraries.
- Automatic pause for active full-screen/display-covering apps, enabled by default.
- Battery pause, display-sleep pause, manual pause/resume, and timed shuffle.
- Playback speed settings, menu bar controls, and optional login startup.
- No account, subscription, analytics, or network requests.

Prebuilt download: Apple Silicon, macOS 14+. The app is ad-hoc signed and is not
Apple-notarized. Intel builds, multiple physical displays, long-running battery
impact, and other limitations are documented in `VALIDATION.md`.

## 1.0.0

Initial local prototype, superseded by 1.1.0 before public release.
