//
//  WelcomeView.swift
//  HealthBar
//
//  Created by Claude on 7/13/26.
//
//  B1 — one-time first-launch welcome screen (Overheal).
//

import SwiftUI

/// The one-time first-launch welcome screen shown before the auth flow (B1).
///
/// Renders a FIXED Erewhon-Dark palette and Erewhon fonts REGARDLESS of the user's
/// theme (including pixel themes). It deliberately never routes through `AppFont`
/// (which would send pixel users to Silkscreen) or `settings.activeColors`; instead
/// it uses the fileprivate font/colour helpers at the bottom of this file. Precedent:
/// the R7a fixed-light celebration overlay.
///
/// Navigation state lives in ContentView — this view owns none of it. The two CTAs
/// invoke injected closures (`onGetStarted` / `onLogIn`); ContentView persists the
/// `hasSeenWelcome` flag and drives the NavigationPath. The screen makes ZERO data
/// calls (no Firestore, no SwiftData), so no guest guard applies here.
struct WelcomeView: View {

    // MARK: - Injected actions

    /// "Get Started" — ContentView persists the welcome flag and pushes SignUp.
    let onGetStarted: () -> Void

    /// "Log In" — ContentView persists the welcome flag and pushes the pushed-variant LoginView.
    let onLogIn: () -> Void

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Overheal-bar fill, 0 → 1 of the FULL track width (fills past the 72% cap notch).
    @State private var barFill: CGFloat = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            WelcomePalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Scrollable hero — on SE-class devices this scrolls; on tall devices the
                // trailing spacer balances it so nothing visibly scrolls (Edge Cases).
                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            hero
                            Spacer().frame(height: 22)
                            overhealBar
                            Spacer().frame(height: 20)
                            valueProps
                            Spacer(minLength: 18)   // absorbs extra height on tall screens
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                }

                ctaStack   // pinned below the scroll view, above the home indicator
            }
        }
        // Fixed dark: forces adaptive tokens (Erewhon.onAccent) to resolve their dark
        // variant and keeps the status bar light-on-dark whatever the user's theme is.
        .environment(\.colorScheme, .dark)
        .onAppear(perform: animateBar)
    }

    // MARK: - Hero (eyebrow · wordmark · tagline)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Eyebrow
            Text("WELCOME TO")
                .font(welcomeBebas(15))
                .tracking(3)
                .foregroundColor(WelcomePalette.accent)

            // 2. Wordmark — OVER / HEAL stacked, second line in accent, tight line height.
            VStack(alignment: .leading, spacing: -14) {
                Text("OVER").foregroundColor(WelcomePalette.ink)
                Text("HEAL").foregroundColor(WelcomePalette.accent)
            }
            .font(welcomeBebas(88))
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Overheal")
            .accessibilityAddTraits(.isHeader)

            // 3. Tagline
            Text("Log your meals. Level up your life. Your health quest begins here.")
                .font(welcomeHanken(16))
                .foregroundColor(WelcomePalette.muted)
                .lineSpacing(3)
                .padding(.top, 12)
        }
    }

    // MARK: - Overheal bar motif

    private var overhealBar: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Label row
            HStack(spacing: 0) {
                Text("FIRST QUEST")
                    .font(welcomeBebas(15))
                    .tracking(1.5)
                    .foregroundColor(WelcomePalette.muted)
                Spacer(minLength: 8)
                Text("LV 1")
                    .font(welcomeBebas(15))
                    .tracking(1)
                    .foregroundColor(WelcomePalette.accent)
            }

            // The bar — fills the whole track; the segment past the 72% notch is brighter.
            OverhealBarTrack(fill: barFill)
                .frame(height: 14)
                .accessibilityLabel("Experience bar filling past the level cap")

            // Caption
            Text("Heal past your limits. Every meal you log earns XP.")
                .font(welcomeHanken(13))
                .foregroundColor(WelcomePalette.muted)
        }
    }

    // MARK: - Value props

    private var valueProps: some View {
        VStack(spacing: 0) {
            ForEach(WelcomeValueProp.all, id: \.title) { prop in
                // Each row sits on a soft hairline divider.
                Rectangle()
                    .fill(WelcomePalette.lineSoft)
                    .frame(height: 1)
                valuePropRow(prop)
            }
        }
    }

    private func valuePropRow(_ prop: WelcomeValueProp) -> some View {
        HStack(spacing: 14) {
            // 38pt rounded accent tile
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(WelcomePalette.accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(WelcomePalette.accent.opacity(0.25), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: prop.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(WelcomePalette.accent)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(prop.title)
                    .font(welcomeBebas(19))
                    .tracking(0.5)
                    .foregroundColor(WelcomePalette.ink)
                Text(prop.subtitle)
                    .font(welcomeHanken(13))
                    .foregroundColor(WelcomePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: - CTA stack (pinned footer)

    private var ctaStack: some View {
        VStack(spacing: 14) {
            // Solid accent primary
            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(welcomeHankenSemibold(16))
                    .foregroundColor(DesignSystem.Erewhon.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Erewhon.buttonRadius, style: .continuous)
                            .fill(WelcomePalette.accent)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get Started")
            .accessibilityHint("Double-tap to create your Overheal account")

            // Ghost text button — "Log In" emphasised in the primary ink colour.
            Button(action: onLogIn) {
                HStack(spacing: 5) {
                    Text("Already have an account?")
                        .font(welcomeHanken(15))
                        .foregroundColor(WelcomePalette.muted)
                    Text("Log In")
                        .font(welcomeHankenSemibold(15))
                        .foregroundColor(WelcomePalette.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Already have an account? Log In")
            .accessibilityHint("Double-tap to log into your Overheal account")
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(
            WelcomePalette.bg
                .overlay(alignment: .top) {
                    Rectangle().fill(WelcomePalette.lineSoft).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Animation

    private func animateBar() {
        if reduceMotion {
            barFill = 1.0   // final state immediately (Reduce Motion)
        } else {
            withAnimation(DesignSystem.Erewhon.ease(1.6).delay(0.4)) {
                barFill = 1.0
            }
        }
    }
}

// MARK: - Overheal bar track

/// The two-tone experience bar. The fill sweeps 0 → 100% of the track; everything up to
/// the 72% cap notch is the accent, and the segment BEYOND the notch renders in a brighter
/// "overheal" accent — the health-bar-past-max motif. A 1pt hairline marks the cap.
private struct OverhealBarTrack: View {
    /// 0 → 1 of the full track width.
    var fill: CGFloat

    private let capFraction: CGFloat = 0.72

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Recessed track
                Capsule().fill(WelcomePalette.track)

                // Full-width two-tone bar (accent → overheal at the cap), masked to the
                // animated width so the colour boundary stays anchored at 72% of the TRACK.
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(WelcomePalette.accent)
                        .frame(width: w * capFraction)
                    Rectangle()
                        .fill(WelcomePalette.overheal)   // brighter — beyond max HP
                }
                .frame(width: w)
                .mask(alignment: .leading) {
                    Capsule().frame(width: max(0, w * fill))
                }
                .shadow(color: WelcomePalette.accent.opacity(0.35), radius: 6, y: 0)

                // Cap notch — 1pt hairline at 72%, above the fill so it stays visible.
                Rectangle()
                    .fill(WelcomePalette.ink.opacity(0.6))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .offset(x: w * capFraction)
            }
        }
    }
}

// MARK: - Value-prop data

private struct WelcomeValueProp {
    let icon: String
    let title: String
    let subtitle: String

    static let all: [WelcomeValueProp] = [
        .init(icon: "target",
              title: "TRACK EFFORTLESSLY",
              subtitle: "Describe or photograph a meal — AI logs the rest."),
        .init(icon: "bolt.fill",
              title: "BATTLE FRIENDS",
              subtitle: "Duel head-to-head on real nutrition, not just streaks."),
        .init(icon: "chevron.up.2",
              title: "CLIMB THE RANKS",
              subtitle: "Nine ranks from Stone to Zenith. Earn every one.")
    ]
}

// MARK: - Fixed Erewhon-Dark palette & fonts (B1)

// Erewhon fonts by PostScript name — bypasses AppFont so pixel-theme users still get
// Bebas/Hanken here (registered in --Info.plist UIAppFonts).
private func welcomeBebas(_ size: CGFloat) -> Font { .custom("BebasNeue-Regular", size: size) }
private func welcomeHanken(_ size: CGFloat) -> Font { .custom("HankenGrotesk-Regular", size: size) }
private func welcomeHankenSemibold(_ size: CGFloat) -> Font { .custom("HankenGrotesk-SemiBold", size: size) }

/// Fixed Erewhon-Dark colours, sourced from the `ThemeColors.erewhonDark` constant so the
/// screen is theme-independent. `Erewhon.line`/`.lineSoft` are intentionally NOT used: they
/// key off `SettingsManager.isCleanDark` (the user's live theme) and would resolve to the
/// near-invisible LIGHT hairline for an `erewhonLight` user on this fixed-dark screen — so
/// their dark resolutions are pinned here instead.
private enum WelcomePalette {
    static let bg = ThemeColors.erewhonDark.primaryBackground        // #0D0F13 bg
    static let accent = ThemeColors.erewhonDark.primary             // #4882FF accent
    static let ink = ThemeColors.erewhonDark.textPrimary            // #E8EBF2 ink
    static let muted = ThemeColors.erewhonDark.textSecondary        // #8B94A8 muted
    static let track = ThemeColors.erewhonDark.xpTrackBackground     // #222838 sunk (bar track)

    /// Pinned dark resolution of `DesignSystem.Erewhon.lineSoft` (ink @ 6%) — see note above.
    static let lineSoft = Color(hex: "#E8EBF2").opacity(0.06)
    /// The "overheal" accent for the segment past the cap — a brighter/lighter accent.
    static let overheal = Color(hex: "#8FB4FF")
}

// MARK: - Preview

#Preview {
    WelcomeView(onGetStarted: {}, onLogIn: {})
}
