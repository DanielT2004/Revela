# Vela — Feature Backlog

> Parked work, phase-tagged. Source of prioritization truth is the `/ceo` skill's STATE.md;
> this doc is the readable "what's left" so nothing gets forgotten. Ruling made 2026-07-14
> against Phase 0 (Survivable by strangers). **Only the "Build next" section is unfrozen.**

---

## 🔨 Build next — Phase 0 (unfrozen)

The Meka simplicity-pass frustration-removers. Small, bounded, straight from beta feedback #1.
Implementation plan: [NEXT_BUILD_PLAN.md](NEXT_BUILD_PLAN.md).

- **Scrub-to-seek on the Sort expanded-clip player** (Meka #12) — [SlicePlayerSheet.swift](FoodEditor/Views/SlicePlayerSheet.swift) is a bare `VideoPlayer` with no drag-to-scrub. Add a scrub bar + hold-for-2× speed.
- **Momentum / inertia scroll on the Polish timeline** (Daniel) — [scrubGesture PolishView.swift:1192](FoodEditor/Views/PolishView.swift#L1192) captures no velocity on release; the timeline stops dead on finger-lift. Add a decelerating glide.
- **Add-beat keyboard focus + tappable time field** (Meka #7) — ✅ SHIPPED. One-tap: `raiseKeyboard(for:)` asserts focus across the partial-detent sheet's present animation (fixes the "tap twice" bug); added start/duration steppers in the keyboard tab.
- **Drag-to-reveal-full-clip** (Meka #10) — ✅ SHIPPED. Base-clip trim now clamps to the clip's `SourceSpan` (the full original recording) instead of the ~15s segment, in both `baseSourceBounds` (live) and `setIn/setOut` (commit). Reaches the end of its own recording, not a neighboring clip.
- **Verify Reveal discoverability** — StyleRevealView **already self-paces** (tap-advance/back, hold-to-pause, skip at [StyleRevealView.swift:169,248](FoodEditor/Views/StyleRevealView.swift#L169)). Meka #1 ("too fast") is probably invisible tap-zones, not pacing. ~0 code — confirm with Meka.

### The real Phase 0 #1 (not features, but they gate everything above)
- Fix the autoplay-return bug (Meka's only hard defect).
- Device-test the two code-complete-but-untested subsystems: Style Templates v2, Voiceover M3.
- Founding-member paywall + anonymized funnel logging.

---

## 🅿️ Phase 1 gate-check (revisit when testers confirm)

- **Auto-captions** — the biggest round-trip killer and Maya's MUST-have (PERSONA.md feature map). Apple-native path keeps the zero-dependency rule: on-device `Speech` / SpeechAnalyzer against the proxy audio → auto-placed styled text overlays (the export text pipeline already exists via [TextOverlayRenderer.swift](FoodEditor/Assembly/TextOverlayRenderer.swift)). Vela twist: caption style comes from the learned style template. Heavy subsystem — do NOT start until Phase 1 interviews confirm the need.
- **Project persistence** — app-kill mid-edit loses the session. Phase 1 if testers complain, else Phase 3. (Maya Test rule 7: interruptible by design.)

---

## 🅿️ Phase 3+ — post-gate (do not build until Phase 2 passes)

**First off the bench (small delight, Daniel's pick):**
- **Cover-frame picker** — at export, offer a few candidate frames, let the creator pick, save the chosen frame as the video's cover/poster. Kills a CapCut round-trip; on-brand with "post-ready output." Small and self-contained — the first reward build once Phase 0 blockers clear.

**Plate-Safe Reframe (upgrade — crop already half-exists):**
- A crop already ships (pinch+pan, scale 1–4×, [PolishView.swift:338](FoodEditor/Views/PolishView.swift#L338), [setCrop EditPlanStore.swift:594](FoodEditor/Models/EditPlanStore.swift#L594)). The upgrade adds flip + rotation + TikTok safe-zone overlay + snap/haptic + cream selection border, all routed through a single `ReframeTransform` so preview==export. Milestones M-R1 (model+math+assembler) → M-R2 (gestures+snap) → M-R3 (chrome/safe-zone). Unlocks **auto punch-in** later. Model: Clip v4 (+cropRotation +cropFlipH), base spine clips only in v1.
- **3 pre-existing bugs to fix alongside** (fix these even in Phase 0 if the crop is touched): double-pushUndo race in the crop gesture ([beginCrop PolishView.swift:363](FoodEditor/Views/PolishView.swift#L363)); b-roll crop preview-parity (base crop under a covering overlay); FullScreenPlayer ignores crop ([PolishView.swift:2644](FoodEditor/Views/PolishView.swift#L2644) wraps a raw `VideoPlayer`).

**AI-native one-taps (moat versions — grounded in the Edit Plan's scene labels):**
- Money-shot slow-mo suggestion — a chip on `money_shot` clips ("Slow this cheese pull? 0.5×"), applied through the existing `clipSpeed`.
- Hook-text auto-placement — one-tap hook text in the safe zone, in the creator's caption style.
- Seamless-loop ending — TikTok autoloops (also in virality backlog).

**Editor mechanics missing vs. CapCut (polish, none gate-moving):**
- Food color-grade presets (3–5 appetite LUTs, `CIFilter` pass — NOT 50 filters).
- Freeze frame (used for the final-plate hold) and reverse clip.
- Per-clip audio fade in/out (assembler has `AVMutableAudioMix`; no user-facing fade → hard cuts sound amateur).
- Real sampled audio waveforms (current [WaveformBar PolishView.swift:1176](FoodEditor/Views/PolishView.swift#L1176) is decorative/deterministic).
- Filmstrip that densifies with zoom (currently 1 thumbnail per clip).
- Replace-clip (swap footage into a slot, keep timing/speed/text).
- Duplicate clip / copy-paste / multi-select.
- Magnetic snapping + visual alignment guides (only narration takes snap today, [EditPlanStore.swift:789](FoodEditor/Models/EditPlanStore.swift#L789)).
- Playhead snap-to-cut-points (biggest precision-trim upgrade; cheap).
- Text animation presets (pop/typewriter via the existing `CALayer` renderer).
- Text safe-zone guides (same overlay the Reframe safe-zone adds).
- Auto-follow playhead during playback; zoom-to-fit / zoom reset; long-press context menu (duplicate/split/delete).
- Sound-effects micro-library (sizzle/pop/whoosh) — licensing/asset work, park hard.

**Already parked in STATE.md (unchanged):** transitions/crossfades (Phase 3), AI script assist for VO (Phase 3), montage reproduction (Phase 4), niche expansion (Phase 4), accounts/sync (Phase 3+).

---

## ❌ Explicitly not building

Stickers/GIFs, green screen, effects library, keyframe/speed-curve editors, music library —
TikTok's own tools or CapCut's territory; each drags us into a parity war or asset licensing.
Vela wins by finishing the video *faster with taste*, not by matching feature count.
