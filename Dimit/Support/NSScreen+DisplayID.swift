import AppKit
import CoreGraphics

extension NSScreen {
    /// `CGDirectDisplayID` has no public "give me the matching NSScreen"
    /// API; the mapping goes through the `NSScreenNumber` device-description
    /// key. Verified against a live probe in C2: that key's value equals the
    /// display's `CGDirectDisplayID`.
    ///
    /// Shared rather than duplicated — code review caught this exact
    /// predicate copy-pasted into both `DisplayManager` (for the display's
    /// human-readable name) and `OverlayDimmer` (for the overlay window's
    /// frame). It matters that there's one copy: this is an unofficial
    /// mapping, not documented API, so if it ever needs a workaround for
    /// mirrored/Sidecar/AirPlay displays, there should be exactly one place
    /// to fix.
    static func matching(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
