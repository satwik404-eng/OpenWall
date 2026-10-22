# Validation — 22 October 2026

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
