# Validation — 24 October 2026

## Version 1.3.1 — Clearer live motion

Rendered-frame checks sample four phases per style, two seconds apart at 1×,
using the dark Midnight Silk palette at 480 × 270. Every style visibly changes:
Dunes changes at least 6,645 pixels, Bloom 46,529 and Constellation 6,030.
All 89 artworks render distinctly. Geometry position and velocity, plus opacity,
are continuous at loop boundaries. All 11,490 Mac/Windows geometry coordinates
match within 1e-12; moving gradient centers, radii and opacity also match.
Animation remains capped at 24 fps. Motion export caches carry catalog revision
3 so older generated movies regenerate. Constellation’s earlier installed fix
was visually confirmed by the user. The broader movement update is installed
as Mac build 7; Dune horizon Teal Green is selected and the native integration
suite passes. The app and installed screen saver signatures verify.
Windows runtime verification remains subject to the 1.3.0 limits below.

## Version 1.3.0

Both Windows self-contained architectures and the native Mac app/screen saver build.
The existing Mac integration suite passes, including actual AVPlayer, playlists,
HEVC preparation and fullscreen/manual/battery pause checks. Native SwiftUI renders
all 89 artworks to distinct images; all ten new styles have exactly eight palettes,
all shapes animate and loop seamlessly. Pure JavaScript/Swift geometry comparison
checks 11,490 coordinates across all eleven scenes with maximum error below 1e-12.
The shared catalog and generated JavaScript are reproducibly checked.

Windows regression checks cover ordinary/maximized/own/shell/hidden/cloaked windows,
full-screen coverage, negative-coordinate monitors, persistent thumbnail cache,
malformed/oversized writes, cleanup, and all previous playlist behaviours.
A Chromium interface harness extracts real H.264 JPEG thumbnails sequentially,
and leaves a fallback for invalid media. This harness substitutes the native bridge;
it does not prove WebView2/Explorer compatibility on every physical Windows PC.

Windows 11 ARM VM testing reached the library but controller startup failed. A
subsequent corrected build was blocked before startup by the VM’s Windows
Application Control policy (0x800711C7); its protections were left enabled.
Therefore full 1.3.0 WebView2/Explorer runtime verification remains incomplete.

Physical Intel/AMD Windows playback, games, multi-display pause behaviour and secure
screen-saver execution still need testing on those machines. The installed Mac bundle/saver signatures pass. The native desktop store and
NSWorkspace both report the stopped-frame JPEG after Quit, with no app process
remaining. The selected OpenWall screen-saver bundle loads in an isolated native
host and plays the current video (rate 1.5, time advancing, no AVPlayer error);
layout, frame callback and stop succeed. The user also confirmed it is working.
Actual password-prompt/secure idle transitions remain separate, unverified tests.
Earlier experimental Mac sign-in animation limits remain below.


## Version 1.2.1 — Mac lock-screen preparation

Built and installed in Applications on Apple Silicon, macOS 27.2. The bundled
screen saver was updated too. All integration checks passed, including the
existing real AVPlayer, full-screen pause, and playlist suite. New checks decode
real HEVC output, verify it contains no audio, generate distinct 1920 × 1080
preset thumbnails and video thumbnails, preserve Apple manifest entries, and
preserve Space identities and unknown wallpaper-store metadata.

The installed app prepared an imported wallpaper, registered a distinct native
asset and matching poster, and wrote the linked Aerial provider configuration.
The setting persisted across an app restart. An obsolete running test copy was
stopped to prevent it overwriting newer settings. The original native index and
manifest are backed up under the user's OpenWall library.

Actual animation behind the locked sign-in prompt, restoration across macOS
upgrades, physical battery/sleep changes, multiple displays, and long-term power
use remain unverified. Native integration is explicitly experimental and uses
private macOS data. HEVC availability and OS cache behavior vary by Mac.

## Version 1.2

Mac app and bundled screen saver build successfully on Apple Silicon, targeting macOS 14+. The 1.2.0 app was installed in Applications before the 1.2.1 update. All Mac integration checks pass with one connected display, including all seven timer durations, exact expiry, ordered wraparound, Forever, a real Foundation timer firing, immediate application, active-entry removal, reorder, pause-aware countdowns, persisted remaining time, and legacy shuffle migration. Nine unique motion wallpapers are included.

The installed native UI was inspected with all nine motion cards, direct Apply actions, playlist controls, and screen-saver controls. OpenWall.saver installed successfully and was selected in System Settings on macOS 27.2. A separate native check verified start/stop layer rendering and that the installed bundle principal class loads. Actual locked-session transitions, password prompt timing, video playback inside the OS screen-saver host, multi-display screen savers, and long-term power use remain unverified.

Both Windows x64 and ARM64 self-contained builds compile with .NET 10. The platform-independent C# playlist checks pass: all durations, nine unique presets, duplicate prevention, immediate apply, exact expiry to Forever, freeze/resume, wraparound, reorder, removal of an active entry, target isolation, persistence, and invalid duration rejection. Windows runtime testing is recorded separately below. Build success does not establish runtime compatibility with Explorer, WebView2, the secure screen-saver desktop, or the LockScreen API.



## Version 1.1 full-screen pause

Added default-on full-screen/display-coverage pause with backward-compatible
library decoding, low-frequency fallback checks, and no repeated player/renderer
updates when pause state and speed have not changed.

New regression checks cover ordinary versus display-covering windows, other
processes, desktop-level and transparent windows, MacBook safe-area geometry,
and a display above/left of the main display. Real AVPlayer tests cover
full-screen enter/exit, switching the setting immediately, preserving manual
pause after exit, and preserving battery pause. Migration tests use a version
1.0 library with no full-screen setting and retain its media and preferences.

All integration and migration checks passed on this Mac with one connected
display. A live macOS full-screen Space transition on the built-in notched
display was also detected, and the running app reported "Paused in full screen".
When the full-screen view was no longer active, it reported "Wallpaper is live".
Geometry coverage is a
heuristic: an ordinary window covering a whole display also pauses wallpapers,
which avoids playback while that desktop is obscured. Multiple physical displays
and other apps' full-screen implementations remain unverified.

## Original version 1.0 checks

Built and run on this Apple Silicon Mac using Apple Swift 6.4, targeting macOS 14+.

Passed integration checks with **one connected display**:

- Generated a real one-second H.264 movie with AVAssetWriter.
- Imported and copied the movie, generated a JPEG thumbnail, rejected invalid media.
- Saved and decoded library media/settings without changing their values.
- Played the real video beyond its source duration with AVQueuePlayer/AVPlayerLooper.
- Verified desktop windows ignore clicks, cannot become key, and sit below icon level.
- Paused and resumed the player manually.
- Simulated battery and sleeping state changes and verified player pause/resume.
- Applied a procedural preset to the selected display and switched it with shuffle.
- Stopped wallpapers and verified that all engine windows closed.
- Removed an imported copy while verifying that the source movie remained.
- Opened and visually inspected the real native library window and settings controls.

Run `./test.command` from a normal terminal to reproduce. The tests use a separate
temporary data directory and briefly create wallpaper windows, then close them.
They do not modify the user's regular library or macOS wallpaper setting.

Not verified: physical sleep/wake, physical battery transitions, login startup,
multiple physical monitors, Intel execution, Spaces/Stage Manager combinations,
macOS 14 execution, notarization, or long-running energy usage. Timed shuffle uses
the same switching path tested by manual shuffle, but a full timer interval was
not waited out. The app is ad-hoc signed, not notarized.
