import SwiftUI
import UIKit

/// Onboarding step 1 — "what should Vela call you?".
///
/// ⚠️ Real login is still deferred: **Sign in with Apple** needs the paid-account capability and phone
/// needs an SMS backend, and a visibly fake auth button is worse than none. So this step asks for a
/// first name instead — it signs the Kitchen greeting, the avatar, and the profile page.
/// `AuthStore.signInWithApple(_:)` is kept for when real auth lands. Skippable — never block
/// onboarding on a text field.
struct SignUpStepView: View {
    @Environment(AuthStore.self) private var auth
    /// Called once the user continues (advances onboarding).
    let onComplete: () -> Void

    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0xC9764F), Color(hex: 0x8C4632)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Before we start —\nwhat should\nVela call you?")
                    .font(VeFont.serif(30, italic: true))
                    .foregroundStyle(Color.veOnTerracotta)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 34)
                    .padding(.top, 40)

                Spacer(minLength: 24)

                sheet
            }
        }
        // Focus the field only after the step's 0.3s entrance fade has settled (keyboard mid-transition
        // makes the sheet jump).
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            nameFocused = true
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xD8CFBD)).frame(width: 42, height: 5)
                .padding(.top, 14).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text("Introduce yourself")
                    .font(VeFont.serif(24)).foregroundStyle(Color.veCharcoal)
                Text("A first name is plenty — it signs your kitchen, your cuts and your templates.")
                    .font(VeFont.sans(14)).foregroundStyle(Color.veNoteText).lineSpacing(2)
                    .padding(.top, 7)

                // Live preview: the avatar springs the initial in as they type (same mark as Home).
                HStack(spacing: 14) {
                    VelaAvatar(name: name, tone: nil, size: 56)
                    TextField("Your name", text: $name)
                        .font(VeFont.serif(31)).foregroundStyle(Color.veCharcoal)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(continueTapped)
                }
                .padding(.top, 22)

                PrimaryActionButton(title: "That's me", enabled: !trimmed.isEmpty, action: continueTapped)
                    .padding(.top, 20)

                Button {
                    auth.signIn(displayName: nil)
                    onComplete()
                } label: {
                    Text("Skip for now")
                        .font(VeFont.sans(13.5, weight: .semibold))
                        .foregroundStyle(Color.veWarmGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                Text("Saved on your phone — change it anytime in your profile.")
                    .font(VeFont.sans(11.5))
                    .foregroundStyle(Color.veFaintGray)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Color.veCream)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.veCharcoal.opacity(0.25), radius: 20, y: -6)
        )
    }

    /// Commit the typed name: light haptic (confirmation), record it, advance.
    private func continueTapped() {
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        auth.signIn(displayName: trimmed)
        onComplete()
    }
}
