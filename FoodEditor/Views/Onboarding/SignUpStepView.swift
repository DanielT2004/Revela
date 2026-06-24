import SwiftUI

/// Onboarding step 1 — "Create your profile".
///
/// ⚠️ Auth is intentionally stubbed for now: both buttons are placeholders that just fast-forward into the
/// app (no real Apple/phone sign-in). Real **Sign in with Apple** needs a paid Apple Developer account
/// (the capability is hidden on a free/personal team), and phone needs an SMS backend — both deferred so we
/// don't burn time on login. `AuthStore.signInWithApple(_:)` is kept for when we wire it up later.
struct SignUpStepView: View {
    @Environment(AuthStore.self) private var auth
    /// Called once the user taps a sign-in button (advances onboarding).
    let onComplete: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0xC9764F), Color(hex: 0x8C4632)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("First, let's\nkeep your style\nsomewhere safe.")
                    .font(VeFont.serif(30, italic: true))
                    .foregroundStyle(Color.veOnTerracotta)
                    .lineSpacing(3)
                    .padding(.horizontal, 34)
                    .padding(.top, 40)

                Spacer(minLength: 24)

                sheet
            }
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xD8CFBD)).frame(width: 42, height: 5)
                .padding(.top, 14).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text("Create your profile")
                    .font(VeFont.serif(24)).foregroundStyle(Color.veCharcoal)
                Text("Drafts, saved cuts and your templates, on every device.")
                    .font(VeFont.sans(14)).foregroundStyle(Color.veNoteText).lineSpacing(2)
                    .padding(.top, 7)

                // Placeholder — styled like the mockup's Apple button, but just fast-forwards for now.
                Button(action: fastForward) {
                    Text("Continue with Apple")
                        .font(VeFont.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: 0x16130F), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                // Placeholder — fast-forwards for now.
                Button(action: fastForward) {
                    Text("Continue with phone number")
                        .font(VeFont.sans(16, weight: .semibold))
                        .foregroundStyle(Color.veCharcoal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(hex: 0xE2DACB), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 11)

                Text("We never post anything without you.")
                    .font(VeFont.sans(11.5))
                    .foregroundStyle(Color.veFaintGray)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
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

    /// Stubbed sign-in: record a local guest user so the rest of the app has an identity, then advance.
    private func fastForward() {
        auth.signInAsGuest()
        onComplete()
    }
}
