import Foundation
import QuartzCore
import CoreGraphics

/// Fling-to-coast for a manually-offset scroll surface (the Polish timeline). Seed it with the finger's
/// lift velocity; it decays that velocity with exponential friction and emits a signed per-frame delta
/// (points, already dt-scaled) via `onTick` until it drops below a cutoff, then fires `onStop`. The
/// consumer applies the delta to its own offset and clamps — the same contract as `EdgeAutoScroller`,
/// but driven by an initial velocity instead of an edge band.
///
/// Driven by `CADisplayLink` so the glide is frame-perfect at 60/120 Hz (a `Timer` drifts and stutters).
/// The link target is held **weakly** through `MomentumWeakProxy`, and the link is invalidated in
/// `stop()` and `deinit`, so there is no retain cycle.
@MainActor
final class MomentumScroller {
    /// Signed points to scroll this frame (already dt-scaled). `+` = toward content end, `-` = start.
    var onTick: ((CGFloat) -> Void)?
    /// Fired once when the glide decays below the cutoff (NOT called on an explicit `stop()`).
    var onStop: (() -> Void)?

    /// Higher = the flick stops sooner. ~5 gives a natural scroll-view-like glide.
    var friction: Double = 5.0
    /// Below this speed (points/sec) the glide ends.
    var minPointsPerSecond: CGFloat = 12

    private var link: CADisplayLink?
    private var velocity: CGFloat = 0          // signed points/sec; 0 = idle
    private var lastTimestamp: CFTimeInterval = 0

    deinit { link?.invalidate() }

    /// Begin a glide at `velocity` (signed points/sec). A near-zero velocity is a no-op — the finger
    /// lifted without a flick, so the scrub should land exactly where it stopped.
    func start(velocity v: CGFloat) {
        velocity = v
        guard abs(v) > minPointsPerSecond else { velocity = 0; return }
        guard link == nil else { return }
        let l = CADisplayLink(target: MomentumWeakProxy(self), selector: #selector(MomentumWeakProxy.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTimestamp = 0
    }

    /// Stop the glide immediately. Idempotent; does NOT fire `onStop`. Safe on gesture begin / teardown.
    func stop() {
        link?.invalidate()
        link = nil
        velocity = 0
        lastTimestamp = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard velocity != 0 else { return }
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? link.duration : now - lastTimestamp
        lastTimestamp = now
        let step = max(0, dt)
        onTick?(velocity * CGFloat(step))
        velocity *= CGFloat(exp(-friction * step))   // exponential friction → smooth ease-out
        if abs(velocity) < minPointsPerSecond {
            stop()
            onStop?()
        }
    }
}

/// Weak shim between `CADisplayLink` (which retains its target) and the scroller — breaks the cycle.
private final class MomentumWeakProxy {
    weak var owner: MomentumScroller?
    init(_ owner: MomentumScroller) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        // The link is added to the main runloop, so this always fires on the main actor.
        MainActor.assumeIsolated { owner?.tick(link) }
    }
}
