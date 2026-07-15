# Next build — Phase 0 cheap wins (implementation plan)

> The Meka simplicity-pass frustration-removers. Each is self-contained and independently
> shippable/testable. Build in order; **STOP at each ⛔ checkpoint and test on a device** before
> moving on (milestone rhythm). No data-model changes, no prompt changes, no Gemini calls.

Order rationale: momentum scroll first (fully self-contained, one gesture, biggest daily-feel
payoff), then scrub-to-seek (one isolated view), then add-beat (smallest code but needs
instrumenting first, so it benefits from being last).

---

## M1 — Momentum / inertia scroll on the Polish timeline

**Goal:** flick the timeline and it coasts to a decelerating stop, like every real editor. Today it
stops the instant the finger lifts.

**Current state:** [scrubGesture PolishView.swift:1192](FoodEditor/Views/PolishView.swift#L1192). The
`.onChanged` sets `scrollX = clampScroll(scrubStartX - v.translation.width)` and seeks the player;
`.onEnded` just clears `scrubbing`. No velocity is captured, so there's no glide.

**Approach:**
1. In `.onEnded`, read the drag's projected endpoint — `DragGesture.Value.predictedEndTranslation`
   (UIKit's own deceleration projection; matches system feel with almost no code). Compute
   `let target = clampScroll(scrubStartX - v.predictedEndTranslation.width)`.
2. If the projected distance beyond the current `scrollX` is below a small threshold, treat it as a
   precise scrub and land exactly (no glide). Otherwise animate:
   `withAnimation(.easeOut(duration: glide)) { scrollX = target }`.
3. Keep the preview honest: seek during the glide. Simplest correct version — an `.onChange(of:
   scrollX)` (already effectively how the playhead reads `scrollX`) throttled to `seekPlayerOnly(to:
   playheadTime)` every ~3 frames, then a final exact seek when the animation settles. Preview stays
   paused throughout (it already pauses on scrub begin).
4. Guards: skip the glide when `zooming || lifting || narration.isBusy` (same guard as `.onChanged`).
   Cancel any in-flight glide if a new drag begins (set `scrollX` to itself with `.transaction {
   $0.animation = nil }` on the next `.onChanged`).

**If `.easeOut` + `predictedEndTranslation` doesn't feel right:** upgrade to a `CADisplayLink` friction
decay — the codebase already has the exact pattern in
[EdgeAutoScroller.swift](FoodEditor/Views/EdgeAutoScroller.swift) (WeakProxy + dt-scaled ticks). Reuse
it: seed velocity from `v.velocity.width`, apply `velocity *= friction` each tick, stop under a
threshold. Only reach for this if the cheap version reads as floaty.

**Risks:** edge clamps (target at 0 or max) — `.easeOut` lands cleanly, no bounce needed for v1
(rubber-band is parked). Watch that the glide doesn't fight the pinch-zoom `.onChanged`.

**⛔ Checkpoint:** flick coasts and decelerates like CapCut; a slow drag still lands exactly; playhead
+ preview frame are in sync at rest; edges stop cleanly; pinch-zoom unaffected.

---

## M2 — Scrub-to-seek on the Sort expanded-clip player (Meka #12)

**Goal:** drag anywhere on the expanded clip to seek; press-and-hold for 2× fast-preview. Today
[SlicePlayerSheet.swift](FoodEditor/Views/SlicePlayerSheet.swift) is a bare `VideoPlayer` that only
auto-loops [start, end] — no scrub, no speed.

**Approach:**
1. Swap `VideoPlayer` for the controls-free
   [PlayerLayerView](FoodEditor/Views/TimelineView.swift) (playbook: inline players use
   `PlayerLayerView`, the parent owns the `AVPlayer`) so we own the transport. Keep the existing
   `AVPlayer` + periodic time observer; feed the observer into a `@State progress: Double`.
2. **Scrub bar** — a slim track pinned near the bottom spanning [start, end], with a knob at
   `progress`. Put the `DragGesture` on *this bar sub-view only* (playbook: conflicting interactions
   on separate sub-views), so it never fights the sheet's vertical swipe-to-dismiss. Map `x → time`
   in [start, end], `player.seek(to:, toleranceBefore: .zero, toleranceAfter: .zero)` for frame
   accuracy. Direction-gate to `abs(dx) > abs(dy)` as belt-and-suspenders.
3. **Hold-for-2×** — a `LongPressGesture` on the video area: on engage set `player.rate = 2.0` + a
   `.soft`/`.rigid` haptic; on release restore `1.0`. Long-press won't conflict with the vertical
   dismiss drag.
4. **Loop coexistence** — the periodic observer's "jump back to start" must not fight the finger: gate
   it behind an `isScrubbing` flag ([SlicePlayerSheet.swift:57](FoodEditor/Views/SlicePlayerSheet.swift#L57)).
5. Keep the ✕ button and the free `.sheet` swipe-down (permanent full-screen-video rule). Keep the
   caption pill.

**Risks:** the horizontal scrub vs. the sheet's interactive vertical dismiss — mitigated by scoping the
drag to the bar sub-view. Confirm `AudioSession.configureForPlayback()` still runs before play.

**⛔ Checkpoint:** drag the bar → smooth frame-accurate seek; hold the video → 2× with haptic, release
→ 1×; loop still works when untouched; swipe-down still dismisses; sound plays on silent switch.

---

## M3 — Add-beat keyboard focus + tappable time field (Meka #7)

**Goal:** tapping the Text tool brings the keyboard up *immediately* with the cursor in the field, and
the start-time is a visibly tappable/editable control.

**Instrument first (do not guess — see the `instrument-before-fixing-ui-bugs` lesson).** The wiring
already looks correct: [addText PolishView.swift:1254](FoodEditor/Views/PolishView.swift#L1254) sets
`textTab = .keyboard`, `editingText = id`, `selection = .text(id)`, and the sheet's `.onAppear` sets
`textFieldFocused = true`. So Meka's "doesn't focus" is most likely a **timing race** between
`@FocusState` and the sheet-presentation animation, not a missing wire. Add a `Log` line around the
focus set + on the field's `.onAppear`, run on device, read the trace before touching code.

**Likely fix (pending the trace):**
1. Focus race → set `textFieldFocused = true` after the presentation settles: move it into a
   `.task { textFieldFocused = true }` or an async hop, instead of raw `.onAppear`. Standard SwiftUI
   remedy for keyboard-on-present.
2. **Time affordance** → the start time currently has no keyboard-editable control (bounds are set via
   trim handles / `setTextBounds`). Add a small bordered "time chip" (e.g. `0:03`) in the text sheet
   that reads as tappable and, on tap, focuses a numeric entry (or a compact stepper) to set start /
   duration by typing. Warm Editorial styling, `.light` haptic on commit.

**Open question for Meka:** confirm "add beat" means the **Text overlay** tool (we have no separate
beat/music tool). Proceed on the Text interpretation; adjust if he meant something else.

**⛔ Checkpoint:** tap Text → keyboard up instantly, cursor in field; the start time shows an obviously
tappable chip that accepts typed input; on-device confirmed (SourceKit diagnostics ignored).

---

## Build hygiene (all three)

- Authoritative check after each change: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` (CLAUDE.md).
  Ignore SourceKit false-positives.
- Match the playbook: springs for settle, haptics per the table, drag in a **named coordinate space**
  (never `.local`) for anything offset by its own gesture.
- No prompt changes, no Gemini calls, no data-model migrations — these are pure interaction polish.
