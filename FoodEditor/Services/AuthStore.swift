import Foundation
import Observation
import AuthenticationServices

/// How the creator got into Vela. `phoneStub`/`guest` are local placeholders — real SMS auth needs a
/// backend, and Sign in with Apple needs a paid developer account.
enum AuthMethod: String, Codable { case apple, phoneStub, guest, none }

/// The signed-in creator. The Apple `user` id is the stable key (survives reinstalls on the same Apple ID);
/// the name is only handed to us on the *first* Apple authorization, so we persist it immediately.
struct VelaUser: Codable, Equatable {
    var appleUserId: String?
    var displayName: String?
    var phone: String?
    var method: AuthMethod
    /// First sign-in date — drives the Profile's "Cooking with Vela since {Month Year}" line.
    /// Optional with a default so pre-existing persisted JSON (and call sites) keep working.
    var joinedAt: Date? = nil
    /// `FoodTone` index personalizing the avatar gradient (nil = the classic warm amber).
    var avatarTone: Int? = nil
}

/// Owns the creator's identity + the first-run flag. Injected into the environment (like `ProjectService`).
/// Persists `VelaUser` as JSON under Application Support; `hasOnboarded` lives in `UserDefaults` so `RootView`
/// can read it synchronously at launch to pick the starting screen with no home-flash.
///
/// Real phone/SMS auth is out of scope (needs a backend) — `signInWithPhoneStub` just records a local name.
@Observable
final class AuthStore {
    static let hasOnboardedKey = "vela.hasOnboarded"

    private(set) var user: VelaUser?

    var isSignedIn: Bool { user != nil }

    /// First word of the saved name, for "Welcome in, {name}" / the avatar initial. Falls back to "there".
    var firstName: String {
        let given = (user?.displayName ?? "").split(separator: " ").first.map(String.init) ?? ""
        return given.isEmpty ? "there" : given
    }

    // MARK: - First-run flag (UserDefaults so launch can read it synchronously)

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasOnboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasOnboardedKey) }
    }

    // MARK: - Persistence

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private let userURL: URL

    init(rootOverride: URL? = nil) {
        let base = rootOverride
            ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AuthStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        userURL = dir.appendingPathComponent("user.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: userURL),
              let decoded = try? decoder.decode(VelaUser.self, from: data) else { return }
        user = decoded
        // One-time self-heal for users who signed in before `joinedAt` existed.
        if user?.joinedAt == nil {
            user?.joinedAt = Date()
            persist()
        }
        Log.app("🍳 Restored signed-in user (\(decoded.method.rawValue)).")
    }

    private func persist() {
        guard let user else { try? fm.removeItem(at: userURL); return }
        do { try encoder.encode(user).write(to: userURL, options: .atomic) }
        catch { Log.app("⚠️ Couldn't persist user: \(error.localizedDescription)") }
    }

    // MARK: - Sign in

    /// Persist the Apple credential. The name only arrives on first authorization — keep it if present,
    /// otherwise retain whatever we previously stored for this user.
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) {
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        let keptName = name.isEmpty ? user?.displayName : name
        user = VelaUser(appleUserId: credential.user, displayName: keptName, phone: user?.phone, method: .apple,
                        joinedAt: user?.joinedAt ?? Date(), avatarTone: user?.avatarTone)
        persist()
        Log.app("🍳 Signed in with Apple (…\(String(credential.user.suffix(4)))), name: \(keptName ?? "—").")
    }

    /// Local sign-in (auth still stubbed): records the chosen display name (nil = skipped the field) and
    /// stamps `joinedAt` exactly once, so "since {Month Year}" survives repeat onboarding runs.
    func signIn(displayName: String?) {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        user = VelaUser(appleUserId: user?.appleUserId,
                        displayName: (trimmed?.isEmpty == false) ? trimmed : user?.displayName,
                        phone: user?.phone, method: .guest,
                        joinedAt: user?.joinedAt ?? Date(), avatarTone: user?.avatarTone)
        persist()
        Log.app("🍳 Signed in, name: \(user?.displayName ?? "—"). // TODO: wire real Apple/phone auth later.")
    }

    /// Placeholder sign-in: marks the user present without any real auth (used while login is stubbed).
    func signInAsGuest() { signIn(displayName: nil) }

    /// Rename from the Profile page. Empty/whitespace input is ignored (the field reverts instead).
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard user != nil, !trimmed.isEmpty else { return }
        user?.displayName = trimmed
        persist()
        Log.app("🍳 Display name updated → \(trimmed).")
    }

    /// Persist the avatar's `FoodTone` index chosen on the Profile page.
    func setAvatarTone(_ tone: Int) {
        guard user != nil else { return }
        user?.avatarTone = tone
        persist()
    }

    /// Local stub — no real SMS. Records an optional display name and marks the user present.
    func signInWithPhoneStub(name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        user = VelaUser(appleUserId: nil, displayName: (trimmed?.isEmpty == false) ? trimmed : nil,
                        phone: nil, method: .phoneStub)
        persist()
        Log.app("🍳 Signed in (phone stub), name: \(trimmed ?? "—"). // TODO: real SMS auth needs a backend.")
    }

    func signOut() {
        user = nil
        persist()
    }

    #if DEBUG
    /// Wipe identity + first-run flag so the onboarding ⛔ test repeats without reinstalling.
    func resetForTesting() {
        user = nil
        persist()
        UserDefaults.standard.removeObject(forKey: Self.hasOnboardedKey)
        // Re-arm the in-editor one-shot teaching moments too, so a reset replays the FULL
        // first-run experience (the "How Vela works" pages themselves keep no persistent state).
        UserDefaults.standard.removeObject(forKey: "veFirstDeckHints")     // Sort deck teaching line
        UserDefaults.standard.removeObject(forKey: "velaTrimCoachShown")   // trim-bar coach line
        Log.app("🍳 AuthStore reset for testing — next launch shows onboarding.")
    }

    /// Encode→decode round-trip sanity check (mirrors FileProjectStore.runSelfTest).
    static func runSelfTest() {
        // Whole-second date on purpose: the .iso8601 strategy drops fractional seconds, so a Date() here
        // would round-trip unequal and false-fail the test.
        let sample = VelaUser(appleUserId: "001234.abcd", displayName: "Mara Vance", phone: nil, method: .apple,
                              joinedAt: Date(timeIntervalSince1970: 1_750_000_000), avatarTone: 3)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? e.encode(sample), let back = try? d.decode(VelaUser.self, from: data), back == sample else {
            Log.app("⚠️ AuthStore self-test MISMATCH."); return
        }
        Log.app("🍳 AuthStore self-test round-trip OK.")
    }
    #endif
}
