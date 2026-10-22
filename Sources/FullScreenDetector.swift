import AppKit
import CoreGraphics

/// Only window geometry and process IDs are used; no screen capture or window titles.
enum FullScreenDetector {
    struct DisplayGeometry {
        let bounds: CGRect
        let topSafeArea: CGFloat
    }

    struct WindowGeometry {
        let ownerPID: pid_t
        let bounds: CGRect
        let layer: Int
        let alpha: Double
    }

    static func detectsFullScreen(frontmostPID: pid_t, windows: [WindowGeometry], displays: [DisplayGeometry]) -> Bool {
        windows.contains { window in
            guard window.ownerPID == frontmostPID, window.layer >= 0,
                  window.layer < Int(CGWindowLevelForKey(.mainMenuWindow)), window.alpha > 0.01 else { return false }
            return displays.contains { display in
                guard display.bounds.width > 0, display.bounds.height > 0 else { return false }
                // Some MacBook apps leave the camera housing strip above their full-screen window.
                let usableBounds = CGRect(x: display.bounds.minX,
                                          y: display.bounds.minY + display.topSafeArea,
                                          width: display.bounds.width,
                                          height: display.bounds.height - display.topSafeArea)
                return covers(window.bounds, display.bounds) || covers(window.bounds, usableBounds)
            }
        }
    }

    private static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        return window.minX <= display.minX + tolerance && window.minY <= display.minY + tolerance
            && window.maxX >= display.maxX - tolerance && window.maxY >= display.maxY - tolerance
    }

    @MainActor static var isActive: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let displays = NSScreen.screens.compactMap { screen -> DisplayGeometry? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayGeometry(bounds: CGDisplayBounds(number.uint32Value), topSafeArea: screen.safeAreaInsets.top)
        }
        let windows = info.compactMap { entry -> WindowGeometry? in
            guard let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == app.processIdentifier,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            return WindowGeometry(ownerPID: owner.int32Value, bounds: bounds, layer: layer.intValue,
                                  alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
        return detectsFullScreen(frontmostPID: app.processIdentifier, windows: windows, displays: displays)
    }
}
