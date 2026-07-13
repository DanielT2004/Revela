import SwiftUI
import UIKit
import Photos
import UserNotifications

/// The creator's profile — reached from the Home avatar. Edit the display name (the serif
/// text-as-field idiom), personalize the avatar's food-tone gradient, jump to templates, see real
/// project stats, fix notification permission, and send beta feedback. Cards cascade in on appear
/// (RootView's `.id(router.screen)` recreates the view per visit, so the entrance replays).
struct ProfileView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthStore.self) private var auth
    @Environment(TemplateService.self) private var templates
    @Environment(ProjectService.self) private var projects

    @State private var appeared = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool
    /// Brief ✓ flash after a rename commits.
    @State private var savedFlash = false
    @State private var projectCount = 0
    @State private var exportedCount = 0
    @State private var notifStatus: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow.cascade(appeared, 0)
                identityCard.padding(.top, 18).cascade(appeared, 1)
                toneRow.padding(.top, 12).cascade(appeared, 2)
                styleRow.padding(.top, 12).cascade(appeared, 3)
                statsRow.padding(.top, 12).cascade(appeared, 4)
                notificationsCard.padding(.top, 12).cascade(appeared, 5)
                feedbackCard.padding(.top, 22).cascade(appeared, 6)
                footer.padding(.top, 26).cascade(appeared, 7)
            }
            .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.veCream.ignoresSafeArea())
        .onAppear {
            nameDraft = auth.user?.displayName ?? ""
            let list = projects.allProjects()
            projectCount = list.count
            exportedCount = list.filter { $0.status == .exported }.count
            appeared = true   // the per-card .animation(value:) springs each section in, staggered
        }
        .task { await refreshNotifStatus() }
        // Returning from Settings (or anywhere) → re-read the live permission state.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshNotifStatus() }
        }
        // Tapping Done commits via onSubmit; tapping AWAY (focus loss) must commit too.
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
    }

    // MARK: header

    private var topRow: some View {
        HStack {
            BackChevronButton { router.back() }
            Spacer()
            Text("YOUR PROFILE")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.4).foregroundStyle(Color.veTerracotta)
            Spacer()
            Color.clear.frame(width: 36, height: 36)   // balance the chevron so the eyebrow centers
        }
    }

    // MARK: identity

    private var identityCard: some View {
        HStack(spacing: 16) {
            VelaAvatar(name: liveName, tone: auth.user?.avatarTone, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    TextField("Your name", text: $nameDraft)
                        .font(VeFont.serif(28)).foregroundStyle(Color.veCharcoal)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                    if savedFlash {
                        ZStack {
                            Circle().fill(Color.veSage).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        }
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                if let joined = auth.user?.joinedAt {
                    Text("Cooking with Vela since \(joined.formatted(.dateTime.month(.wide).year()))")
                        .font(VeFont.sans(12.5)).foregroundStyle(Color.veWarmGray)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: savedFlash)
    }

    /// While typing, the avatar previews the draft; at rest it shows the saved name.
    private var liveName: String? {
        nameFocused ? nameDraft : (auth.user?.displayName ?? nameDraft)
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = auth.user?.displayName ?? ""   // never commit an empty name — revert
            return
        }
        guard trimmed != auth.user?.displayName else { return }
        auth.updateDisplayName(trimmed)
        nameDraft = trimmed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            savedFlash = false
        }
    }

    // MARK: avatar color

    private var toneRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Avatar color")
                    .font(VeFont.sans(13, weight: .bold)).foregroundStyle(Color.veCharcoal)
                Spacer()
                Text("Your color around the kitchen")
                    .font(VeFont.sans(11)).foregroundStyle(Color.veWarmGray)
            }
            HStack(spacing: 0) {
                ForEach(Array(FoodTone.allCases.enumerated()), id: \.offset) { i, tone in
                    let selected = auth.user?.avatarTone == i
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            auth.setAvatarTone(i)
                        }
                    } label: {
                        Circle()
                            .fill(tone.gradient)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(Color.veCharcoal, lineWidth: selected ? 2 : 0)
                                    .padding(-3.5)
                            )
                            .scaleEffect(selected ? 1.12 : 1)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)   // distributes evenly on every device width
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: auth.user?.avatarTone)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: style

    private var styleRow: some View {
        Button { router.go(.templateLibrary) } label: {
            HStack(spacing: 13) {
                ZStack {
                    if let active = templates.active {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                            ForEach(0..<4, id: \.self) { i in
                                let t = active.tones.isEmpty ? [0, 1, 4, 5] : active.tones
                                FoodTone.tone(for: t[i % t.count]).gradient
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.veSurface)
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 17)).foregroundStyle(Color.veTerracotta)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(templates.active != nil ? "ACTIVE STYLE" : "YOUR STYLE")
                        .font(VeFont.sans(10.5, weight: .bold)).tracking(0.8).foregroundStyle(Color.veTerracotta)
                    Text(templates.active?.name ?? "No style yet — teach Vela one")
                        .font(VeFont.sans(15, weight: .bold)).foregroundStyle(Color.veCharcoal).lineLimit(1)
                    Text("\(templates.templates.count) template\(templates.templates.count == 1 ? "" : "s") · tap to manage")
                        .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xCFC6B6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: stats (all real values — no fake metrics)

    private var statsRow: some View {
        HStack(spacing: 9) {
            statTile("\(projectCount)", "projects")
            statTile("\(exportedCount)", "exported")
            statTile("\(templates.templates.count)", "templates")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(VeFont.serif(22)).foregroundStyle(Color.veCharcoal)
            Text(label).font(VeFont.sans(11)).foregroundStyle(Color.veWarmGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.05), radius: 9, y: 3)
    }

    // MARK: notifications

    @ViewBuilder private var notificationsCard: some View {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral:
            notifRow(icon: "bell.fill", tint: Color.veSage,
                     title: "Notifications on",
                     subtitle: "We'll ping you the moment your cut is ready.",
                     action: nil)
        case .denied:
            notifRow(icon: "bell.slash.fill", tint: Color.veTerracotta,
                     title: "Notifications are off",
                     subtitle: "Turn them on in Settings and Vela can ping you when a cut is ready.") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .notDetermined:
            notifRow(icon: "bell.badge", tint: Color.veTerracotta,
                     title: "Turn on notifications",
                     subtitle: "Analysis takes a minute — get pinged instead of waiting around.") {
                Task {
                    await NotificationService.shared.requestAuthorization()
                    await refreshNotifStatus()
                }
            }
        default:
            EmptyView()   // still loading — the card cascades in once status arrives
        }
    }

    private func notifRow(icon: String, tint: Color, title: String, subtitle: String,
                          action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.12))
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VeFont.sans(14.5, weight: .bold)).foregroundStyle(Color.veCharcoal)
                Text(subtitle)
                    .font(VeFont.sans(12)).foregroundStyle(Color.veWarmGray).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.veFaintGray)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.veCharcoal.opacity(0.06), radius: 12, y: 4)

        return Group {
            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private func refreshNotifStatus() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: beta feedback

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BETA KITCHEN")
                .font(VeFont.sans(11, weight: .bold)).tracking(1.0).foregroundStyle(Color(hex: 0xE8B65E))
            Text("Found a bug? Loved a cut?")
                .font(VeFont.serif(19)).foregroundStyle(Color.veCream)
                .padding(.top, 5).padding(.bottom, 6)
            Text("You're cooking with an early build. A quick note about what broke — or what felt great — makes the next one better.")
                .font(VeFont.sans(12)).foregroundStyle(Color.veCream.opacity(0.6)).lineSpacing(2)
                .padding(.bottom, 14)
            Button(action: sendFeedback) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill").font(.system(size: 13, weight: .bold))
                    Text("Send feedback").font(VeFont.sans(14, weight: .bold))
                }
                .foregroundStyle(Color.veCharcoal)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.veCream, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.veCharcoal, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sendFeedback() {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = "daniel.t7504@gmail.com"
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "Vela beta feedback"),
            URLQueryItem(name: "body",
                         value: "What happened (or what you loved):\n\n\n—\nVela \(Self.appVersion) · iOS \(UIDevice.current.systemVersion)"),
        ]
        if let url = comps.url { UIApplication.shared.open(url) }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Vela \(Self.appVersion)")
                .font(VeFont.sans(11.5)).foregroundStyle(Color.veFaintGray)
                .frame(maxWidth: .infinity)
            #if DEBUG
            // Dev convenience — mirrors the Home avatar's long-press reset.
            Button("Reset onboarding") {
                auth.resetForTesting()
                router.go(.onboarding)
            }
            .font(VeFont.sans(12, weight: .semibold))
            .foregroundStyle(Color.veTerracotta)
            #endif
        }
    }

    private static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - entrance cascade

private struct CascadeIn: ViewModifier {
    let shown: Bool
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.05), value: shown)
    }
}

private extension View {
    /// Staggered fade-and-rise entrance (index = position in the cascade).
    func cascade(_ shown: Bool, _ index: Int) -> some View {
        modifier(CascadeIn(shown: shown, index: index))
    }
}

#Preview {
    ProfileView()
        .environment(AppRouter())
        .environment(AuthStore())
        .environment(TemplateService())
        .environment(ProjectService())
}
