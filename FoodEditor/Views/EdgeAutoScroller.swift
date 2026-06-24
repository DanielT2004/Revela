import QuartzCore
import CoreGraphics

/// Drives "drag-past-the-edge → keep scrolling" for any reorder surface. It is **surface-agnostic**:
/// it knows nothing about `scrollX`, `ScrollView`, or clips. Feed it the finger's position within a
/// viewport each gesture frame; while the finger sits in a leading/trailing edge band it emits a signed
/// per-frame scroll delta (in points, already dt-scaled) via `onTick`, and the consumer decides what the
/// delta means (mutate a manual offset, or pace a `ScrollViewProxy.scrollTo`).
///
/// Driven by `CADisplayLink` so motion is frame-perfect at 60/120 Hz (a `Timer` drifts against the
/// refresh and stutters). The link's target is held **weakly** through `WeakProxy`, and the link is
/// invalidated in `stop()` and `deinit`, so there is no retain cycle.
@MainActor
final class EdgeAutoScroller {
    enum Axis { case vertical, horizontal }

    /// Per-frame callback while in an edge band: signed points to scroll this frame (already dt-scaled).
    /// `+` = toward content end (down / right), `-` = toward start (up / left). The consumer applies + clamps.
    var onTick: ((CGFloat) -> Void)?

    /// Edge band thickness in points — a touch within this of an edge pulls. Capped at half the viewport.
    var bandInset: CGFloat = 64
    /// Scroll speed at the very edge (points/sec).
    var maxPointsPerSecond: CGFloat = 1100
    /// Scroll speed at the inner band boundary (points/sec) — starts gently, accelerates inward.
    var minPointsPerSecond: CGFloat = 120

    private let axis: Axis
    private var link: CADisplayLink?
    private var velocity: CGFloat = 0          // signed points/sec; 0 = idle
    private var lastTimestamp: CFTimeInterval = 0

    init(axis: Axis) { self.axis = axis }

    deinit { link?.invalidate() }

    /// Call every gesture-changed frame. `location` is the finger position along `axis` in the SAME
    /// coordinate space as `viewportLength` (0 = leading/top edge of the viewport). `canScrollStart` /
    /// `canScrollEnd` let the consumer veto a direction at a clamp limit so the link doesn't spin.
    func update(location: CGFloat, viewportLength: CGFloat,
                canScrollStart: Bool, canScrollEnd: Bool) {
        velocity = computeVelocity(location: location, viewportLength: viewportLength,
                                   canScrollStart: canScrollStart, canScrollEnd: canScrollEnd)
        if velocity == 0 { stop() } else { start() }
    }

    /// Stop scrolling. Idempotent; safe to call on gesture end / cancel.
    func stop() {
        link?.invalidate()
        link = nil
        velocity = 0
        lastTimestamp = 0
    }

    // MARK: - Internals

    /// Signed velocity (points/sec) for the current finger position; 0 when outside both bands.
    private func computeVelocity(location: CGFloat, viewportLength: CGFloat,
                                 canScrollStart: Bool, canScrollEnd: Bool) -> CGFloat {
        guard viewportLength > 0 else { return 0 }
        let band = min(bandInset, viewportLength / 2)
        let startDepth = band - location                          // >0 within `band` of the start edge
        let endDepth = location - (viewportLength - band)         // >0 within `band` of the end edge
        // The deeper overlap wins so a tiny viewport doesn't pull both ways.
        if startDepth > 0, canScrollStart, startDepth >= endDepth { return -speed(startDepth, band) }
        if endDepth > 0, canScrollEnd { return speed(endDepth, band) }
        return 0
    }

    /// Accelerating ease-in: crawls at the band boundary, fastest at the very edge.
    private func speed(_ depth: CGFloat, _ band: CGFloat) -> CGFloat {
        let f = max(0, min(depth / band, 1))
        return minPointsPerSecond + (maxPointsPerSecond - minPointsPerSecond) * f * f
    }

    private func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: WeakProxy(self), selector: #selector(WeakProxy.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTimestamp = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard velocity != 0 else { return }
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? link.duration : now - lastTimestamp
        lastTimestamp = now
        onTick?(velocity * CGFloat(max(0, dt)))
    }
}

/// Weak shim between `CADisplayLink` (which retains its target) and the auto-scroller — breaks the cycle.
private final class WeakProxy {
    weak var owner: EdgeAutoScroller?
    init(_ owner: EdgeAutoScroller) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        // The link is added to the main runloop, so this always fires on the main actor.
        MainActor.assumeIsolated { owner?.tick(link) }
    }
}
