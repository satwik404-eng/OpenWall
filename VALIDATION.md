# Validation — 23 October 2026

## Version 1.2

Mac app and bundled screen saver build successfully on Apple Silicon, targeting macOS 14+. The installed app is version 1.2.0 in Applications. All Mac integration checks pass with one connected display, including all seven timer durations, exact expiry, ordered wraparound, Forever, a real Foundation timer firing, immediate application, active-entry removal, reorder, pause-aware countdowns, persisted remaining time, and legacy shuffle migration. Nine unique motion wallpapers are included.

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
