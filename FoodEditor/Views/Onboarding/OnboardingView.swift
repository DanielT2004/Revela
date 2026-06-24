import SwiftUI

/// First-run onboarding. One router screen that owns its own linear `step` machine (mockup steps 0–4):
/// 0 Welcome → 1 Sign up → 2 Connect → 3 Analyzing → 4 Style profile → enter the app.
struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(VideoSession.self) private var session
    @Environment(TemplateService.self) private var templates

    @State private var step = 0
    @State private var styleCoordinator = StyleAnalysisCoordinator()
    @State private var analyzedTemplate: StyleTemplate?

    var body: some View {
        ZStack {
            Color.veCream.ignoresSafeArea()

            Group {
                switch step {
                case 0:
                    WelcomeStepView { goTo(1) }
                case 1:
                    SignUpStepView { goTo(2) }
                case 2:
                    ConnectStepView(onBack: { goTo(1) }, onContinue: { goTo(3) })
                case 3:
                    AnalyzingStepView(
                        coordinator: styleCoordinator,
                        clips: session.clips,
                        onDone: { template in analyzedTemplate = template; goTo(4) },
                        onBack: { goTo(2) }
                    )
                default:
                    if analyzedTemplate != nil {
                        TemplateEditorView(
                            template: Binding($analyzedTemplate)!,
                            clips: session.clips,
                            mode: .onboarding,
                            onSave: { saveAndEnter() }
                        )
                    } else {
                        Color.veCream  // shouldn't happen; step 4 only follows a successful analysis
                    }
                }
            }
            .transition(.opacity.combined(with: .offset(y: 7)))
            .id(step)
        }
        .animation(.easeOut(duration: 0.3), value: step)
    }

    private func goTo(_ next: Int) { step = next }

    private func saveAndEnter() {
        if let t = analyzedTemplate {
            templates.save(t, poster: styleCoordinator.posterImage)   // first template auto-becomes active
        }
        auth.hasOnboarded = true
        router.home()
    }
}
