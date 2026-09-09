/// Shared by `WarmthCurve` and `Renderer` — code review on C1 caught that
/// only one of the two pure math functions defensively clamped its input,
/// which is exactly the kind of thing that drifts when each site hand-rolls
/// its own min/max. One tiny, obviously-correct helper instead.
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
