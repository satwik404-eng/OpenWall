# OpenWall

Free, open-source live wallpapers for macOS, and Windows. MIT licensed.
No account, subscription, analytics, paid catalog, or cloud library.

[Download the latest release](https://github.com/satwik404-eng/OpenWall/releases/latest)

## One click to apply

Click any wallpaper card to apply it immediately to the selected displays.
There is no second **Set wallpaper** step. **Add to playlist** is a separate action.

The Motion collection includes **89 original wallpapers made from code**. The original nine remain:
Northern lights, Afterglow, Deep current, Ember glow, Amethyst drift, Glacier light,
Solar tide, Midnight silk, and Rosewater. You can also import your own video files.

Version 1.3 adds **10 distinct motion styles × 8 palettes = 80 new wallpapers**:
Silk ribbons, Orbital rings, Luminous bloom, Contour flow, Prism drift, Neon rain,
Dune horizon, Constellation, Vortex tunnel, and Petal dance. Each comes in Jade,
Arctic, Violet, Coral, Gold, Midnight Silk, Light Blue, and Teal Green.
Both platforms consume the same vector catalog, so wave geometry, palettes,
and motion parameters match. Library cards and screen savers use the same artwork.

## Frame rate and video quality

In **Settings → Motion frame rate**, choose **60 fps**, **120 fps**, or **24 fps · Lower power**.
120 fps requires a compatible high-refresh display; actual cadence also depends on
system power and performance. This changes smoothness, not the animation's flow speed.
The OpenWall screen saver reads the same preference. Native live sign-in movie
exports keep their existing 24 fps format and are separate from desktop rendering.

A video's preview has its own **Video quality** selector. A 3840 × 2160 source
has **1080p, 1440p and 4K**; a 2560 × 1440 source has **1080p and 1440p**.
Below 1080p, **Original** plays the source at its maximum resolution. No option
upscales the source. Nonstandard sizes also retain an Original choice.

Lower resolutions prepare an actual silent playback copy the first time they
are chosen. The previous wallpaper keeps playing while preparation finishes.
Original videos stay intact, and video frame rate is preserved. A codec/encoding
failure reports the problem and returns the choice to original quality.
The VideoQuality cache holds at most 2 GiB of completed copies, with 512 MiB per
copy and one encoder at a time. Long clips that exceed that budget use Original.
Unused old copies can be evicted; active copies are protected. Removing an import
removes its copies, and unfinished work is cleaned on the next app launch.

## Playlist

Add wallpapers, arrange their order with the up/down controls, and give each one
its own duration: **1 day, 6 hours, 3 hours, 1 hour, 30 minutes, 5 minutes, or Forever**.
Start the playlist to cycle in order. Forever holds until you choose Next or another
wallpaper. Clicking a playlist member starts it immediately with its full duration;
clicking a wallpaper outside the playlist stops rotation on those displays.

Timers freeze while desktop playback is paused and resume with their time remaining.

On Mac, **Quit OpenWall** leaves a still frame of the current video or motion
wallpaper on each display. Reopening resumes live playback. Still frames come from
OpenWall’s own media; no screen-recording permission is used. At most two alternating
JPEG files are retained per display under StoppedFrames. On newer macOS versions,
the desktop choice is separated from the idle screen-saver choice in the native
wallpaper store, so a linked aerial cannot override the stopped image. A backup is
kept there; the live lock-screen feature remains experimental.
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

### Mac live lock screen (experimental)

Enable **Use live wallpaper on the lock screen** in Settings. On macOS 26+,
OpenWall converts your main display's current wallpaper to a silent HEVC movie
and adds it to the per-user native aerial cache. It configures the same native
linked wallpaper for the desktop and idle/lock views on every display. Selecting
another wallpaper updates this preparation automatically. Desktop playback pauses
while the session is locked.

A full-resolution thumbnail generated from that same wallpaper is used during
preparation, on battery when battery pause is enabled, on older macOS versions,
or if the live integration fails. Preparation can take time; the app reuses up to
three prepared videos across launches. OpenWall's prior native cache entry is
removed when another wallpaper replaces it. Original videos stay in your library.

This integration uses undocumented macOS data and can break after OS updates.
OpenWall backs up the original configuration under its local library's
LockScreen/Backups folder. Disable the toggle or choose **Restore previous system
wallpaper** to restore it while OpenWall still owns the current system wallpaper.
If you changed it in another app, OpenWall leaves that newer selection untouched.
Actual playback behind the locked sign-in prompt is not yet verified; see
[VALIDATION.md](VALIDATION.md). It does not change the FileVault startup login screen.

### Mac screen saver

In OpenWall Settings, choose **Install OpenWall screen saver**. Then select
**OpenWall** in System Settings → Wallpaper → Screen Saver → Other → Show All
(macOS 26+), or System Settings → Screen Saver on older versions.

The .saver reads the latest wallpaper assignments and videos from OpenWall's own
local library cache, so future wallpaper clicks are reflected the next time the
screen saver starts. Imported videos loop; the motion collection uses a lightweight
animated vector artwork as desktop playback. Battery pause shows a still image. The OS
controls idle timing, display sleep, password protection, and the sign-in prompt.
For password protection, choose Require password Immediately in Lock Screen settings.

When OpenWall.saver is installed, native wallpaper sync preserves it as the idle
screen saver rather than replacing it with the system aerial. The saver uses native
Core Graphics for the motion collection and AVFoundation for videos.

The optional .saver is separate from native live lock-screen sync. Changing the
wallpaper while this saver is already running takes effect next start.

## Install on Windows

Download OpenWall-Windows-x64.zip for Intel/AMD PCs, or
OpenWall-Windows-arm64.zip for ARM PCs. Extract the entire ZIP and double-click
**Start OpenWall.cmd** launcher, or open the inner OpenWall folder and run
**OpenWall.exe** (Type: Application). Keep all extracted files together. Requires **Windows 10 version
2004+ or Windows 11** and the [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/).
.NET is bundled; no separate .NET installation or administrator access is needed.

The Windows app includes the motion collection, local video import, direct click to
apply, per-display playlists, battery/full-screen/session-lock pause, and tray controls.
Imported videos receive cached JPEG previews, including videos already in your
library. Previews decode sequentially without playing audio and release the video
decoder after capture. One JPEG (at most 256 KiB) is retained per import and removed
with that import. Missing or damaged previews regenerate automatically, including
a bounded retry for browser decode failures. Unsupported codecs keep a fallback card.
A desktop playback failure does not hide the library or block thumbnail generation.

Pause in full screen ignores OpenWall, desktop/taskbar windows, hidden windows,
and normal maximized windows. It pauses for an external borderless client covering
its display. Geometry remains a heuristic; test your games/apps on your Windows build.

H.264 MP4 is the most portable video choice; codec availability depends on Windows.
Explorer embedding uses an undocumented WorkerW interface and may vary by Windows
build. The Windows release has verification limits documented in
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
