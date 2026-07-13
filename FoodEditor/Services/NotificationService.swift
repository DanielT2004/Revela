import Foundation
import UserNotifications
import UIKit

/// Local + remote notifications so the creator gets pinged when the (potentially slow) Gemini analysis
/// finishes. The **local** path covers the app-still-alive case. The **remote** path (APNs) is the only
/// thing that can notify a fully-closed phone: we register for a device token here and hand it to the
/// server with the analyze job, and the `gemini-proxy` worker pushes when the job finishes.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private static let tokenKey = "apnsDeviceToken"

    /// The APNs device token (hex), if registration has succeeded. Persisted so the very first analyze
    /// after a relaunch can attach it synchronously, before registration round-trips again.
    private(set) var deviceTokenHex: String? = UserDefaults.standard.string(forKey: NotificationService.tokenKey)

    /// Cached "are notifications actually enabled" — read at render time by the processing surfaces so they
    /// never promise a ping the user denied. Refreshed on foreground + right after `requestAuthorization`.
    private(set) var notificationsEnabled = false

    /// Re-read the OS authorization status (a pure read — no prompt) and cache it.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    /// Set as the notification-center delegate so notifications also show while the app is foreground.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask once for permission (alert + sound). On grant, also register for **remote** (APNs) pushes so
    /// the server can reach a closed app. Safe to call repeatedly.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            Log.notif("Authorization granted: \(granted)")
            notificationsEnabled = granted
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch {
            Log.notif("Authorization error: \(error.localizedDescription)")
        }
    }

    // MARK: - Remote (APNs) registration callbacks (forwarded from AppDelegate)

    func didRegister(deviceTokenHex hex: String) {
        deviceTokenHex = hex
        UserDefaults.standard.set(hex, forKey: Self.tokenKey)
        Log.notif("APNs device token registered: \(hex.prefix(8))…")
    }

    func didFailToRegister(_ error: Error) {
        // Expected on the simulator and until the Push capability is added (Phase 2). Non-fatal: the
        // token stays nil → the server simply skips the push and the local notification still fires.
        Log.notif("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Posting

    /// Post an immediate local notification. `screen` is stashed in the payload so a tap routes the same
    /// way a remote push does (see `didReceive`). `id` — pass a STABLE identifier when the same logical
    /// alert can fire from more than one place (e.g. both pipelines' "Open Vela to finish" compress
    /// nudges): iOS replaces a request with the same identifier instead of stacking duplicates. Nil keeps
    /// the unique-per-post behavior.
    func notify(title: String, body: String, screen: String? = nil, id: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let screen { content.userInfo = ["screen": screen] }
        let request = UNNotificationRequest(identifier: id ?? UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.notif("Post failed: \(error.localizedDescription)") }
            else { Log.notif("Posted → \(title): \(body)") }
        }
    }

    // MARK: - Delegate

    // Foreground presentation rule: pipeline completion/return pings (anything carrying a `screen`
    // payload — "style is ready", "cut is ready", the snag alerts) are SUPPRESSED while the app is
    // open. In-app, the reveal / Home processing card is the completion signal; a banner on top of it
    // is noise (and the style batch push can land seconds before the client finishes consolidating).
    // Banners still show normally when the phone is locked / app backgrounded — iOS only consults
    // `willPresent` for foreground arrivals, so no state tracking is needed. Notifications WITHOUT a
    // `screen` payload (compress nudges, export toasts) keep the banner: they're informational or
    // only ever post from the background.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isPipelinePing = notification.request.content.userInfo["screen"] != nil
        completionHandler(isPipelinePing ? [] : [.banner, .sound])
    }

    // A tap (local or remote) carrying `{"screen":…}` asks the app to open to a result. We stash the
    // intent on `AppRoute`; `RootView` consumes it once it's safe to navigate. "analysis" → the finished
    // cut; "template" → the freshly-learned style template.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        switch info["screen"] as? String {
        case "analysis": Task { @MainActor in AppRoute.shared.pending = .analysis }
        case "template": Task { @MainActor in AppRoute.shared.pending = .template }
        default:         break
        }
        completionHandler()
    }
}
