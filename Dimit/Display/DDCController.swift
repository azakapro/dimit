/// Third-party external-monitor brightness via DDC/CI — CLAUDE.md §3.4.
/// C5's job (IOAVService I2C on Apple Silicon, IOFramebuffer I2C on
/// Intel); this cycle only needs the shape to exist so `BrightnessBackend`
/// resolution order is complete and `PWMSafeCoordinator` correctly reports
/// `.unsupported` for a third-party monitor rather than never checking at
/// all. Always `.unsupported` until C5.
final class DDCBackend: BrightnessBackend {
    let name = "DDC/CI"

    func canControl(_ display: DisplayInfo) -> Bool {
        false // C5
    }

    func get(_ display: DisplayInfo) -> Float? {
        nil
    }

    func set(_ display: DisplayInfo, _ value: Float) -> BrightnessResult {
        .unsupported
    }
}
