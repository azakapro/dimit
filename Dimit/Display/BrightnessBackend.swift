import Foundation

/// One way to read/set a display's hardware backlight — ARCHITECTURE.md
/// §2.5. `PWMSafeCoordinator` tries backends in order and uses the first
/// whose `canControl` returns true; a display with none is `.unsupported`.
protocol BrightnessBackend {
    /// For diagnostics/logging only.
    var name: String { get }
    func canControl(_ display: DisplayInfo) -> Bool
    /// `nil` means "couldn't read" — treated the same as a failed pin
    /// verification, never as 0.
    func get(_ display: DisplayInfo) -> Float?
    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult
}

enum BrightnessResult: Equatable {
    case ok
    case unsupported
    case failed(Int32)
}
