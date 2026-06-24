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
                    SegmentListView()
                case .editor:
                    EditorShellView()
                case .hook:
                    HookSpotlightView()
                case .export:
                    ExportView()
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
                        onDone: { template in create.draft = template; router.go(.createReview) },
                        onBack: { router.back() }
                    )
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
                                create.reset()
                                router.go(.templateLibrary)
                            },
                            onCancel: { create.reset(); router.back() }
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
                                router.back()
                            },
                            onCancel: { router.back() }
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
            .transition(.opacity.combined(with: .offset(y: 7)))
            .id(router.screen)
        }
        .animation(.easeOut(duration: 0.3), value: router.screen)
        // Persist the in-progress project whenever the app backgrounds (covers app kill)…
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { projects.save(session: session, reaching: Self.status(for: router.screen)) }
        }
        // …and whenever the user leaves the editor back to the Kitchen.
        .onChange(of: router.screen) { old, new in
            if new == .home && old != .home { projects.save(session: session, reaching: Self.status(for: old)) }
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
