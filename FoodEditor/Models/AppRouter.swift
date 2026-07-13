import Foundation
import Observation

/// Screens in the flow, mirroring the mockup's screen state machine.
enum AppScreen: Equatable {
    case onboarding
    case home, picker, brief, processing, segments, editor, hook, export, profile
    // Style templates
    case templateLibrary, createSource, createSelect, createAnalyzing, createReveal, createReview, templateEditor
    case refineAnalyzing, refineReveal

    var title: String {
        switch self {
        case .onboarding:      return "Welcome"
        case .home:            return "Kitchen"
        case .picker:          return "Camera roll"
        case .brief:           return "Before we cut"
        case .processing:      return "Working"
        case .segments:        return "Your first cut"
        case .editor:          return "Editor"
        case .hook:            return "Pick your hook"
        case .export:          return "Export"
        case .profile:         return "Profile"
        case .templateLibrary: return "Your templates"
        case .createSource:    return "New template"
        case .createSelect:    return "Pick videos"
        case .createAnalyzing: return "Learning"
        case .createReveal:    return "Your style"
        case .createReview:    return "Review & save"
        case .templateEditor:  return "Review style"
        case .refineAnalyzing: return "Sharpening"
        case .refineReveal:    return "What held up"
        }
    }
}

/// Lightweight navigation state machine with a history stack (matches the mockup's `go`/`back`).
@Observable
final class AppRouter {
    var screen: AppScreen
    private(set) var history: [AppScreen] = []

    /// `start` lets `RootView` open on onboarding for first-run, or the Kitchen otherwise.
    init(start: AppScreen = .home) { self.screen = start }

    func go(_ screen: AppScreen) {
        history.append(self.screen)
        self.screen = screen
    }

    func back() {
        screen = history.popLast() ?? .home
    }

    func home() {
        history.removeAll()
        screen = .home
    }
}
