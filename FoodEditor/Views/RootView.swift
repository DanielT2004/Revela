import SwiftUI

/// Top-level container that swaps screens based on the `AppRouter` state machine, with a soft
/// fade between them (the mockup's `fadeScreen`). Real screens replace the placeholder per milestone.
struct RootView: View {
    @State private var router: AppRouter
    @State private var session = VideoSession()
    @State private var projects = ProjectService()
    @State private var analysis = AnalysisCoordinator()
    @State private var voiceIso = VoiceIsolationCoordinator()
    @State private var clipImport = ClipImportCoordinator()
    @State private var auth = AuthStore()
    @State private var templates = TemplateService()
    @State private var create = CreateFlow()
    @State private var refine = RefineFlow()
    @State private var appRoute = AppRoute.shared       // notification-tap → navigation signal
    // Cancel-safety: post-M5 a draft carries Reveal answers — anything that discards one confirms first
    // (the library-delete dialog pattern; a silent discard of confirmed signatures is the trust-killer).
    @State private var confirmDiscardCreate = false
    @State private var confirmDiscardEdit = false
    @Environment(\.scenePhase) private var scenePhase

    /// Gate the first screen synchronously (no home-flash): onboarding until the creator has onboarded.
    init() {
        let onboarded = UserDefaults.standard.bool(forKey: AuthStore.hasOnboardedKey)
        _router = State(initialValue: AppRouter(start: onboarded ? .home : .onboarding))
    }

    var body: some View {
        ZStack {
            Color.veCream.ignoresSafeArea()

            Group {
                switch router.screen {
                case .onboarding:
                    OnboardingView()
                case .home:
                    HomeView()
                case .picker:
                    PickerView()
                case .brief:
                    BriefView()
                case .processing:
                    ProcessingView()
                case .segments:
                    FirstCutView()
                case .editor:
                    EditorShellView()
                case .hook:
                    HookSpotlightView()
                case .export:
                    ExportView()
                case .profile:
                    ProfileView()
                case .templateLibrary:
                    TemplateLibraryView()
                case .createSource:
                    CreateSourceView()
                case .createSelect:
                    CreateSelectView()
                case .createAnalyzing:
                    AnalyzingStepView(
                        coordinator: create.coordinator,
                        clips: create.selectedClips,
                        kicker: "NEW TEMPLATE",
                        title: "Learning a different\nside of your edits",
                        narration: AnalyzingStepView.newTemplateNarration,
                        onDone: { template in create.draft = template; router.go(.createReveal) },
                        onBack: { router.back() }
                    )
                case .createReveal:
                    if create.draft != nil {
                        StyleRevealView(
                            template: Binding(get: { create.draft ?? .sample },
                                              set: { create.draft = $0 }),
                            firstName: auth.firstName,
                            onDone: { router.go(.createReview) }
                        )
                    } else {
                        PlaceholderScreen(screen: router.screen)
                    }
                case .createReview:
                    if create.draft != nil {
                        TemplateEditorView(
                            template: Binding(get: { create.draft ?? .sample },
                                              set: { create.draft = $0 }),
                            clips: create.selectedClips,
                            mode: .newTemplate,
                            onSave: {
                                if let draft = create.draft {
                                    templates.save(draft, poster: create.coordinator.posterImage)
                                    templates.setActive(draft.id)   // the freshly-made style becomes active
                                }
                                StyleJobStore.clear()   // durably saved — drop the kill-recovery record (+ its poster file)
                                create.reset()
                                router.go(.templateLibrary)
                            },
                            // Explicit destination, NOT router.back(): back() would pop to .createAnalyzing, whose
                            // .task would re-fire onDone from the still-.done coordinator and bounce the user right
                            // back into the review they just cancelled. reset() clears that .done phase too.
                            onCancel: { confirmDiscardCreate = true }
                        )
                    } else {
                        PlaceholderScreen(screen: router.screen)
                    }
                case .templateEditor:
                    if templates.editingDraft != nil {
                        TemplateEditorView(
                            template: Binding(get: { templates.editingDraft ?? .sample },
                                              set: { templates.editingDraft = $0 }),
                            clips: [],
                            mode: .edit,
                            onSave: {
                                if let draft = templates.editingDraft { templates.save(draft) }
                                if refine.updatedDraft != nil {
                                    // A refinement just got durably saved — drop its recovery record and
                                    // land on the library (back() would pop into the mini-reveal).
                                    StyleJobStore.clear()
                                    refine.reset()
                                    router.home(); router.go(.templateLibrary)
                                } else {
                                    router.back()
                                }
                            },
                            onCancel: {
                                // Only interrupt when there's actually something to lose.
                                let saved = templates.templates.first { $0.id == templates.editingDraft?.id }
                                if let draft = templates.editingDraft, let saved, draft != saved {
                                    confirmDiscardEdit = true
                                } else {
                                    router.back()
                                }
                            },
                            onRefine: { picked in
                                if let base = templates.editingDraft {
                                    refine.begin(base: base, picked: picked)
                                    router.go(.refineAnalyzing)
                                }
                            }
                        )
                    } else {
                        PlaceholderScreen(screen: router.screen)
                    }
                case .refineAnalyzing:
                    AnalyzingStepView(
                        coordinator: refine.coordinator,
                        clips: refine.clips,
                        kicker: "SHARPENING YOUR STYLE",
                        title: "Finding what\nheld up",
                        narration: AnalyzingStepView.newTemplateNarration,
                        onDone: { t in refine.updatedDraft = t; router.go(.refineReveal) },
                        onBack: { router.back() }
                    )
                case .refineReveal:
                    if refine.updatedDraft != nil {
                        StyleRevealView(
                            template: Binding(get: { refine.updatedDraft ?? .sample },
                                              set: { refine.updatedDraft = $0 }),
                            firstName: auth.firstName,
                            diff: refine.coordinator.diff ?? TemplateDiff(),
                            onDone: {
                                // Hand the refined draft to the editor for the final look + save; the
                                // editor's save path clears the record and resets this flow.
                                if let d = refine.updatedDraft { templates.beginEditing(d) }
                                router.go(.templateEditor)
                            }
                        )
                    } else {
                        PlaceholderScreen(screen: router.screen)
                    }
                default:
                    PlaceholderScreen(screen: router.screen)
                }
            }
            .environment(router)
            .environment(session)
            .environment(projects)
            .environment(analysis)
            .environment(voiceIso)
            .environment(clipImport)
            .environment(auth)
            .environment(templates)
            .environment(create)
            .environment(refine)
            .environment(appRoute)
            .transition(.opacity.combined(with: .offset(y: 7)))
            .id(router.screen)
        }
        .animation(.easeOut(duration: 0.3), value: router.screen)
        .confirmationDialog("Discard this style?", isPresented: $confirmDiscardCreate, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                StyleJobStore.clear()   // discarded on purpose — don't re-offer it next launch
                create.reset()
                router.home(); router.go(.templateLibrary)
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your reveal answers and any edits go with it.")
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscardEdit, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) {
                if refine.updatedDraft != nil {
                    // Dropping an unsaved refinement — deliberate, so don't re-offer it next launch.
                    StyleJobStore.clear()
                    refine.reset()
                    router.home(); router.go(.templateLibrary)
                } else {
                    router.back()
                }
            }
            Button("Keep editing", role: .cancel) {}
        }
        // Cold-launch recovery: if the app was KILLED mid-analysis, re-attach to the server job and
        // finish. We DON'T force-navigate — the creator lands on Home, where a "Processing" card shows
        // it's still running (HomeView reads `analysis`). Completion routes to the reveal below.
        .task {
            analysis.resumeIfPending(session: session, projects: projects)
            create.coordinator.resumeIfPending()   // re-attach a killed create-flow style-learn
            refine.coordinator.resumeIfPending()   // re-attach a killed refinement (reloads its base by id)
            await NotificationService.shared.refreshAuthorizationStatus()   // seed the "notifs on?" copy
        }
        // A notification tap (local or remote) explicitly asks to open a result; consume it once safe.
        .onChange(of: appRoute.pending) { _, _ in consumePendingRoute() }
        // When the analysis finishes (whether the creator is on the Home card or the full Processing
        // page), reveal the results — guarded so it never yanks them out of an active edit.
        .onChange(of: analysis.phase) { _, phase in
            if phase == .done { revealIfSafe() }
        }
        // When a create-flow style-learn finishes (live, or resumed after a kill), route to its review page.
        .onChange(of: create.coordinator.phase) { _, phase in
            if phase == .done { revealTemplateIfSafe() }
        }
        // A refinement resumed after a kill completes on Home → route to its mini-reveal (live on-screen
        // completion is owned by the .refineAnalyzing AnalyzingStepView.onDone, same one-navigation rule).
        .onChange(of: refine.coordinator.phase) { _, phase in
            if phase == .done, refine.updatedDraft == nil, router.screen == .home,
               let t = refine.coordinator.template {
                refine.updatedDraft = t
                router.go(.refineReveal)
            }
        }
        // Persist the in-progress project whenever the app backgrounds (covers app kill)…
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                analysis.resumeIfPending(session: session, projects: projects)   // re-attach after a kill
                create.coordinator.resumeIfPending()
                refine.coordinator.resumeIfPending()
                consumePendingRoute()
                Task { await NotificationService.shared.refreshAuthorizationStatus() }   // caught a Settings toggle
            } else {
                // Backgrounding mid-compression interrupts the on-device prep (iOS suspends the
                // AVFoundation export), so it can't finish while away. Ping the creator to come right
                // back. Gated to `.background` (not transient `.inactive`, e.g. Control Center) and to
                // the compress step only — uploading/analysis survive a tap-away on their own.
                if newPhase == .background && analysis.isCompressing {
                    NotificationService.shared.notify(
                        title: "Open Vela to finish",
                        body: "Compression couldn't complete while you were away — please go back to the app to finish prepping your footage.",
                        id: "compress-nudge"   // shared with the style coordinators' nudge → coalesces, never stacks
                    )
                }
                projects.save(session: session, reaching: Self.status(for: router.screen))
            }
        }
        // …and whenever the user leaves the editor back to the Kitchen.
        .onChange(of: router.screen) { old, new in
            if new == .home && old != .home { projects.save(session: session, reaching: Self.status(for: old)) }
            // A route blocked by an unsafe screen (a push tapped mid-edit) fires now that we've moved — so the
            // intent lands the moment the creator reaches a safe screen instead of being silently dropped.
            if appRoute.pending != nil { consumePendingRoute() }
        }
    }

    /// A notification tap asking to open the analysis. From a "safe" pre-editor screen only (never yanks
    /// the creator out of an active edit): if it's already finished → straight to the reveal; if still
    /// running → the Processing page (the `analysis.phase` observer reveals it on completion). A stale tap
    /// with nothing in flight is a harmless no-op. Returns `false` ONLY when blocked by an unsafe screen, so
    /// the caller can keep the pending intent and retry it when the creator reaches a safe screen.
    @discardableResult
    private func routeToAnalysisIfSafe() -> Bool {
        let safe: Set<AppScreen> = [.home, .picker, .brief, .processing]
        guard safe.contains(router.screen) else { return false }
        if analysis.phase == .done, session.store?.plan != nil {
            session.pendingReveal = true
            router.go(.segments)
        } else if analysis.phase == .running {
            router.go(.processing)
        }
        return true   // handled (routed, or a harmless stale no-op) — safe to clear the pending intent
    }

    /// On analysis completion, hand off to the celebratory reveal — from Home (the Processing card),
    /// the Processing page, or the pre-brief screens. Never interrupts an active edit/export/reveal.
    private func revealIfSafe() {
        guard session.store?.plan != nil else { return }
        let safe: Set<AppScreen> = [.home, .processing, .picker, .brief]
        guard safe.contains(router.screen) else { return }
        session.pendingReveal = true
        router.go(.segments)
    }

    /// On a create-flow style-learn completing after a **kill-resume**, hand off to the Reveal from Home
    /// (the paid result AND the moment are both protected — the Reveal resumes any answered cards from its
    /// sidecar). The live on-screen case (`.createAnalyzing`) is owned entirely by
    /// `AnalyzingStepView.onDone`, so we deliberately DON'T fire there — that keeps exactly one navigation
    /// (and one history entry) instead of racing two `.onChange` observers.
    private func revealTemplateIfSafe() {
        guard let t = create.coordinator.template, create.draft == nil else { return }
        guard router.screen == .home else { return }
        create.draft = t
        router.go(.createReveal)
    }

    /// A notification tap asking to open the freshly-learned template. Routes the create flow to its review
    /// (done), the Analyzing screen (running or failed — that screen shows both progress and the error state).
    /// Returns `false` ONLY when it can't act yet (mid-onboarding, or an unsafe screen), so the caller keeps
    /// the pending intent and retries it when the creator reaches a safe screen — the fix for a push tapped
    /// from the editor silently burning the one-shot route.
    @discardableResult
    private func routeToTemplateIfSafe() -> Bool {
        guard auth.hasOnboarded else { return false }   // onboarding recovers its own learn; keep + retry later
        let safe: Set<AppScreen> = [.home, .createSource, .createSelect, .createAnalyzing]
        guard safe.contains(router.screen) else { return false }
        switch create.coordinator.phase {
        case .done where create.coordinator.template != nil:
            // Already revealed (draft set) → handled without navigating, so a stale kept-pending can't yank a
            // browsing user back into review. Not yet revealed → set the draft and open the Reveal.
            if create.draft == nil {
                create.draft = create.coordinator.template
                router.go(.createReveal)   // safe set excludes .createReveal, so never a same-screen push
            }
        case .running where router.screen != .createAnalyzing:
            router.go(.createAnalyzing)     // show the "learning" screen; its onDone reveals on completion
        case .failed where router.screen != .createAnalyzing:
            router.go(.createAnalyzing)     // show the error state (with a working Back/Retry)
        default:
            break                           // already on the right screen, or a stale .idle — nothing to do
        }
        return true   // handled — safe to clear the pending intent
    }

    /// Dispatch a pending notification-tap intent, clearing it ONLY when actually handled. A tap from an
    /// unsafe screen (mid-edit) or mid-onboarding leaves `pending` set so it re-fires from the scenePhase
    /// `.active` and `router.screen` observers — instead of being silently burned by an unconditional clear.
    private func consumePendingRoute() {
        switch appRoute.pending {
        case .analysis: if routeToAnalysisIfSafe() { appRoute.pending = nil }
        case .template: if routeToTemplateIfSafe() { appRoute.pending = nil }
        case .none:     break
        }
    }

    /// Editor screens imply the project has advanced past triage.
    private static func status(for screen: AppScreen) -> ProjectStatus? {
        switch screen {
        case .editor, .hook, .export: return .polishing
        default: return nil
        }
    }
}

/// Temporary stand-in for screens not yet built in the current milestone.
struct PlaceholderScreen: View {
    @Environment(AppRouter.self) private var router
    let screen: AppScreen

    var body: some View {
        VStack(spacing: 14) {
            Text(screen.title)
                .font(VeFont.serif(28))
                .foregroundStyle(Color.veCharcoal)
            Text("Coming in a later milestone")
                .font(VeFont.sans(14))
                .foregroundStyle(Color.veWarmGray)
            Button("← Back to Kitchen") { router.home() }
                .font(VeFont.sans(15, weight: .bold))
                .foregroundStyle(Color.veTerracotta)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.veCream.ignoresSafeArea())
    }
}

#Preview {
    RootView()
}
