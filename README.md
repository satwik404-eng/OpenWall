# OpenWall

Free, open-source live wallpapers for macOS, with a Windows preview. MIT licensed.
No account, subscription, analytics, paid catalog, or cloud library.

[Download the latest release](https://github.com/satwik404-eng/OpenWall/releases/latest)

## One click to apply

Click any wallpaper card to apply it immediately to the selected displays.
There is no second **Set wallpaper** step. **Add to playlist** is a separate action.

The Motion collection includes nine original animations made from code:
Northern lights, Afterglow, Deep current, Ember glow, Amethyst drift, Glacier light,
Solar tide, Midnight silk, and Rosewater. You can also import your own video files.

## Playlist

Add wallpapers, arrange their order with the up/down controls, and give each one
its own duration: **1 day, 6 hours, 3 hours, 1 hour, 30 minutes, 5 minutes, or Forever**.
Start the playlist to cycle in order. Forever holds until you choose Next or another
wallpaper. Clicking a playlist member starts it immediately with its full duration;
clicking a wallpaper outside the playlist stops rotation on those displays.

Timers freeze while desktop playback is paused and resume with their time remaining.
Normal quit saves that remaining time. Stopping the playlist leaves the current
wallpaper visible; Stop removes the desktop wallpapers. Existing shuffle settings
on Mac migrate to an ordered playlist.

## Install on Mac

Download OpenWall-macOS-arm64.dmg, open it, and drag OpenWall to Applications.
The prebuilt app requires **Apple Silicon and macOS 14+**. It is ad-hoc signed,
not Apple-notarized; macOS may require approval in Privacy & Security.

Imported MP4/MOV and other supported videos loop silently using AVFoundation.
Full-screen/display-covering apps pause playback automatically. Battery and display
sleep pause are also available, with per-display assignment, menu-bar controls,
playback speed, and optional login startup.

### Mac screen saver

In OpenWall Settings, choose **Install OpenWall screen saver**. Then select
**OpenWall** in System Settings → Wallpaper → Screen Saver → Other → Show All
(macOS 26+), or System Settings → Screen Saver on older versions.

The .saver reads the latest wallpaper assignments and videos from OpenWall's own
local library cache, so future wallpaper clicks are reflected the next time the
screen saver starts. Imported videos loop; the motion collection uses a lightweight
animated gradient in the same palette. Battery pause shows a still image. The OS
controls idle timing, display sleep, password protection, and the sign-in prompt.
For password protection, choose Require password Immediately in Lock Screen settings.

This is an OS screen saver. It does not replace Apple's aerial downloads or rewrite
Apple's lock-screen cache, and it does not change the FileVault startup login screen.
Changing the wallpaper while the saver is already running takes effect next start.

## Install on Windows (preview)

Download OpenWall-Windows-x64-preview.zip for Intel/AMD PCs, or
OpenWall-Windows-arm64-preview.zip for ARM PCs. Extract the entire ZIP and run
OpenWall.exe. Keep all extracted files together. Requires **Windows 10 version
2004+ or Windows 11** and the [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/).
.NET is bundled; no separate .NET installation or administrator access is needed.

The Windows app includes the motion collection, local video import, direct click to
apply, per-display playlists, battery/full-screen/session-lock pause, and tray controls.
H.264 MP4 is the most portable video choice; codec availability depends on Windows.
Explorer embedding uses an undocumented WorkerW interface and may vary by Windows
build. The Windows release is explicitly a **preview**, with verification limits in
[VALIDATION.md](VALIDATION.md).

### Windows screen saver and lock-screen image

In Settings, choose **Enable OpenWall screen saver**. This registers the included
OpenWall.scr for your current account, enables it, enables password protection,
and opens Windows screen-saver settings. Keep the extracted folder in place.
The saver reads the current per-display assignments. Windows controls its idle
activation and the sign-in screen shown on resume. /s, /p, and /c modes are
included for full-screen, Control Panel preview, and configuration.

**Use current wallpaper as lock-screen image** captures a still frame from the
active wallpaper and sets it through Windows' LockScreen API. Device policy can
prevent this. Windows' lock-screen cache does not provide arbitrary animated video
playback on the sign-in screen. A video screen saver and a sign-in background are
separate OS features.

## Build from source

Mac (Xcode Command Line Tools, no package dependencies):

    ./build.command /tmp/OpenWall.app
    ./test.command

The script builds the native app and its bundled OpenWall.saver. It targets the
build machine's architecture. Intel source builds have not been runtime tested.

Windows (.NET 10 SDK; cross-compilation is supported):

    ./Windows/build.ps1 -Runtime win-x64
    # or -Runtime win-arm64
    dotnet run --project Windows.Tests/OpenWall.Tests.csproj

The Windows UI and renderer are local HTML/CSS/JavaScript in WebView2, hosted by
WinForms. Requests to external HTTP hosts, popups, and browser permission requests
are blocked. WebView2 Runtime may follow Microsoft's own update/network behavior.
See THIRD-PARTY-NOTICES.txt in the Windows download for bundled runtime/SDK notices.

## Local data

- Mac: ~/Library/Application Support/org.openwall.desktop/
- Windows: %LOCALAPPDATA%\OpenWall\

Imported videos are copied into the local library. Removing an import deletes the
OpenWall copy and thumbnail, preserving the original. Public downloads contain only
OpenWall code and original art; personal media and paid wallpaper assets are excluded.

Independent software, not affiliated with Wallper. No trial, account, payment, or
license restrictions from another app are bypassed.
