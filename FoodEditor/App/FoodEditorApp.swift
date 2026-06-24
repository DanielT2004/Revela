import SwiftUI

@main
struct FoodEditorApp: App {
    init() {
        Log.app("FoodEditor (Vela) launched — MVP build. Verbose logging is ON.")
        NotificationService.shared.configure()
        AudioSession.configureForPlayback()
        #if DEBUG
        AuthStore.runSelfTest()
        StyleTemplate.runSelfTest()
        FileTemplateStore.runSelfTest()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light) // Warm Editorial is a light scheme.
        }
    }
}
