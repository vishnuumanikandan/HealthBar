//
//  WelcomeView.swift
//  HealthBar
//
//  Created by Claude on 7/13/26.
//
//  B1 — one-time first-launch welcome screen (Overheal).
//  PC1 — restyled to the pixel-clean visual language of the marketing site.
//

import SwiftUI

/// The one-time first-launch welcome screen shown before the auth flow (B1, restyled in PC1).
///
/// Renders a FIXED pixel-clean palette pinned to the marketing site's hex values, REGARDLESS
/// of the user's theme (including pixel themes). It deliberately never routes through
/// `AppFont` (which would send pixel users to Silkscreen wholesale) or `settings.activeColors`;
/// instead it uses the fileprivate font/colour helpers at the bottom of this file. Silkscreen
/// appears here only as an ACCENT face (eyebrow, bar labels, prop titles, tags, primary CTA)
/// alongside Bebas/Hanken. Precedent: the R7a fixed-light celebration overlay.
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// HP-bar fill, 0 → 1 of the FULL track width (sweeps past the max notch into overheal).
    @State private var barFill: CGFloat = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            WelcomePalette.bg.ignoresSafeArea()

            // Ambient colour washes — decorative, dropped under Reduce Transparency.
            if !reduceTransparency {
                backgroundWashes
            }

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

            // Scanline sits ABOVE the content by design (it overlays the whole screen on the
            // site, footer included) — decorative only, so it never intercepts touches.
            if !reduceTransparency {
                scanline
            }
        }
        // Fixed dark: keeps the status bar light-on-dark whatever the user's theme is.
        .environment(\.colorScheme, .dark)
        .onAppear(perform: animateBar)
    }

    // MARK: - Decorative background layers

    /// Two blurred colour washes — blue top-trailing, cyan bottom-leading. Positioned by the
    /// mockup's edge insets (the circle overhangs the screen edge by the named amount).
    private var backgroundWashes: some View {
        ZStack {
            wash(size: WelcomeMetrics.washTopSize, tint: WelcomePalette.blueTint,
                 opacity: WelcomeMetrics.washTopOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: WelcomeMetrics.washTopInsetX, y: -WelcomeMetrics.washTopInsetY)

            wash(size: WelcomeMetrics.washBottomSize, tint: WelcomePalette.cyanTint,
                 opacity: WelcomeMetrics.washBottomOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -WelcomeMetrics.washBottomInsetX, y: WelcomeMetrics.washBottomInsetY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func wash(size: CGFloat, tint: Color, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: tint, location: 0),
                        .init(color: .clear, location: WelcomeMetrics.washFadeStop)
                    ]),
                    center: .center,
                    startRadius: 0,
                    // Farthest-CORNER extent, matching the default of the mockup's CSS
                    // radial-gradient: the fade stop lands outside the circle's own radius,
                    // so the tint carries to the edge instead of dying well inside it.
                    endRadius: size / 2 * WelcomeMetrics.washGradientExtent
                )
            )
            .frame(width: size, height: size)
            .blur(radius: WelcomeMetrics.washBlur)
            .opacity(opacity)
    }

    /// 1pt horizontal pixel scanlines every 3pt, full-bleed.
    private var scanline: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: WelcomeMetrics.scanlineWidth)),
                    with: .color(.black.opacity(WelcomeMetrics.scanlineOpacity))
                )
                y += WelcomeMetrics.scanlinePitch
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Hero (eyebrow · wordmark · tagline)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Eyebrow — Silkscreen chip with a square pixel dot.
            eyebrow

            // 2. Wordmark — OVER/HEAL on ONE line, the second word in the blue accent.
            //    Measured 196.7pt at 64pt against a 264pt content box on a 320pt screen,
            //    so it needs no scale fallback.
            Text(wordmark)
                .font(welcomeBebas(WelcomeMetrics.wordmarkFont))
                .padding(.top, 6)
                .accessibilityLabel("Overheal")
                .accessibilityAddTraits(.isHeader)

            // 3. Tagline
            Text("Your health quest begins here.")
                .font(welcomeHanken(WelcomeMetrics.taglineFont))
                .foregroundColor(WelcomePalette.inkSoft)
                .lineSpacing(WelcomeMetrics.taglineLineSpacing)
                .padding(.top, WelcomeMetrics.taglineTopPadding)
        }
    }

    /// Two-tone wordmark as ONE attributed run, so it renders as a single Text (single line,
    /// single accessibility element). `Text + Text` concatenation is deprecated as of iOS 26.
    private var wordmark: AttributedString {
        var over = AttributedString("OVER")
        over.foregroundColor = WelcomePalette.ink
        var heal = AttributedString("HEAL")
        heal.foregroundColor = WelcomePalette.blue2
        return over + heal
    }

    private var eyebrow: some View {
        HStack(spacing: WelcomeMetrics.eyebrowSpacing) {
            Rectangle()
                .fill(WelcomePalette.cyan)
                .frame(width: WelcomeMetrics.eyebrowDot, height: WelcomeMetrics.eyebrowDot)
                .shadow(color: WelcomePalette.pixelDotShadow, radius: 0,
                        x: WelcomeMetrics.shadowPixelDot, y: WelcomeMetrics.shadowPixelDot)

            Text("WELCOME TO")
                .font(welcomeSilkscreen(WelcomeMetrics.eyebrowFont))
                .tracking(WelcomeMetrics.eyebrowTracking)
                .foregroundColor(WelcomePalette.cyan)
        }
        .padding(.vertical, WelcomeMetrics.eyebrowPaddingV)
        .padding(.horizontal, WelcomeMetrics.eyebrowPaddingH)
        .background(
            RoundedRectangle(cornerRadius: WelcomeMetrics.chipRadius, style: .continuous)
                .fill(WelcomePalette.cyanTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WelcomeMetrics.chipRadius, style: .continuous)
                .stroke(WelcomePalette.line, lineWidth: 1)
        )
    }

    // MARK: - HP bar motif

    private var overhealBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label row
            HStack(spacing: 0) {
                Text("FIRST QUEST")
                    .font(welcomeSilkscreen(WelcomeMetrics.barHeaderFont))
                    .tracking(WelcomeMetrics.barHeaderTracking)
                    .foregroundColor(WelcomePalette.inkMute)
                Spacer(minLength: 8)
                Text("LV 1")
                    .font(welcomeSilkscreen(WelcomeMetrics.barLevelFont))
                    .foregroundColor(WelcomePalette.cyan)
            }
            .padding(.bottom, WelcomeMetrics.barHeaderBottomPadding)

            // The bar — fills the whole track; the segment past the max notch is the
            // brighter "overheal" cyan.
            OverhealBarTrack(fill: barFill)
                .frame(height: WelcomeMetrics.barHeight)
                .accessibilityLabel("Health bar filling past the maximum")
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
        HStack(spacing: WelcomeMetrics.propRowSpacing) {
            iconTile(prop.icon)

            VStack(alignment: .leading, spacing: WelcomeMetrics.propTextSpacing) {
                Text(prop.title)
                    .font(welcomeSilkscreen(WelcomeMetrics.propTitleFont))
                    .tracking(WelcomeMetrics.propTitleTracking)
                    .foregroundColor(WelcomePalette.ink)
                Text(prop.subtitle)
                    .font(welcomeHanken(WelcomeMetrics.propSubtitleFont))
                    .foregroundColor(WelcomePalette.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            pixelTag(prop.tag)
        }
        .padding(.vertical, WelcomeMetrics.propRowPaddingV)
        .accessibilityElement(children: .combine)
    }

    /// The hard shadow is attached to the tile SHAPE (before the icon overlay) so only the
    /// tile casts it — a trailing `.shadow` would also stamp an offset copy of the glyph,
    /// which shows through the translucent fill.
    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: WelcomeMetrics.chipRadius, style: .continuous)
            .fill(WelcomePalette.blueTint)
            .frame(width: WelcomeMetrics.tileSize, height: WelcomeMetrics.tileSize)
            .shadow(color: WelcomePalette.hard, radius: 0,
                    x: WelcomeMetrics.shadowTile, y: WelcomeMetrics.shadowTile)
            .overlay(
                RoundedRectangle(cornerRadius: WelcomeMetrics.chipRadius, style: .continuous)
                    .stroke(WelcomePalette.line, lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: WelcomeMetrics.tileIconFont, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(WelcomePalette.blue3)
            )
            .accessibilityHidden(true)
    }

    /// Squared Silkscreen tag — decorative, so it is hidden from VoiceOver.
    private func pixelTag(_ text: String) -> some View {
        Text(text)
            .font(welcomeSilkscreen(WelcomeMetrics.tagFont))
            .foregroundColor(WelcomePalette.cyan)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, WelcomeMetrics.tagPaddingV)
            .padding(.horizontal, WelcomeMetrics.tagPaddingH)
            .background(Rectangle().fill(WelcomePalette.cyanTint))
            .overlay(Rectangle().stroke(WelcomePalette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }

    // MARK: - CTA stack (pinned footer)

    private var ctaStack: some View {
        VStack(spacing: 14) {
            // Chunky pixel primary — squared, hard offset shadow, presses INTO the shadow.
            Button(action: onGetStarted) {
                Text("GET STARTED")
                    .font(welcomeSilkscreen(WelcomeMetrics.ctaFont))
                    .tracking(WelcomeMetrics.ctaTracking)
                    .foregroundColor(.white)
            }
            .buttonStyle(PixelButtonStyle(reduceMotion: reduceMotion))
            // Breathing room so the hard shadow renders fully instead of running into the
            // screen edge (the footer's 6pt bottom padding covers the vertical side).
            .padding(.trailing, WelcomeMetrics.shadowPrimary)
            .accessibilityLabel("Get Started")
            .accessibilityHint("Double-tap to create your Overheal account")

            // Ghost text button — "Log In" emphasised in the primary ink colour.
            Button(action: onLogIn) {
                HStack(spacing: 5) {
                    Text("Already have an account?")
                        .font(welcomeHanken(WelcomeMetrics.loginFont))
                        .foregroundColor(WelcomePalette.inkMute)
                    Text("Log In")
                        .font(welcomeHankenSemibold(WelcomeMetrics.loginFont))
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
            withAnimation(DesignSystem.Erewhon.ease(WelcomeMetrics.barFillDuration)
                .delay(WelcomeMetrics.barFillDelay)) {
                barFill = 1.0
            }
        }
    }
}

// MARK: - HP bar track

/// The squared pixel HP bar. The fill sweeps 0 → 100% of the track; everything up to the
/// max notch is the HP blue, a 4pt white notch marks maximum, and the segment BEYOND it
/// renders in the brighter "overheal" cyan — the health-bar-past-max motif. Segment stripes
/// sit above the fill, and the 3pt border is drawn LAST so the stripes never cover it.
private struct OverhealBarTrack: View {
    /// 0 → 1 of the full track width.
    var fill: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let segments = WelcomeMetrics.barSegments(trackWidth: w)

            ZStack(alignment: .leading) {
                // Recessed track
                Rectangle().fill(WelcomePalette.track)

                // Full-width three-part bar, masked to the animated width so the colour
                // boundaries stay anchored to fractions of the TRACK, not of the fill.
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(WelcomePalette.hpBorder)
                        .frame(width: segments.fill)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: segments.notch)
                    Rectangle()
                        .fill(WelcomePalette.hpOver)   // brighter — beyond max HP
                        .shadow(color: WelcomePalette.hpOver.opacity(WelcomeMetrics.overGlowOpacity),
                                radius: WelcomeMetrics.overGlowRadius)
                }
                .frame(width: w)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(0, w * fill))
                }

                // Pixel segment stripes — above the fill, below the border.
                segmentStripes(trackWidth: w)

                // Border drawn OVER the interior so nothing paints across it.
                Rectangle()
                    .strokeBorder(WelcomePalette.hpBorder, lineWidth: WelcomeMetrics.barBorder)
            }
        }
    }

    private func segmentStripes(trackWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(0..<WelcomeMetrics.stripeUnitCount(trackWidth: trackWidth)), id: \.self) { _ in
                Color.clear
                    .frame(width: WelcomeMetrics.stripePitch)
                Rectangle()
                    .fill(Color.black.opacity(WelcomeMetrics.stripeOpacity))
                    .frame(width: WelcomeMetrics.stripeWidth)
            }
        }
        .frame(width: trackWidth, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Pixel button style

/// Squared button that presses INTO its own hard shadow: the content shifts by the press
/// offset while the shadow shortens by the same amount, so the shadow's far edge stays put.
private struct PixelButtonStyle: ButtonStyle {
    /// Passed in from the view — a ButtonStyle cannot read the accessibility environment itself.
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadowOffset = pressed ? WelcomeMetrics.shadowPressed : WelcomeMetrics.shadowPrimary
        let shift = pressed ? WelcomeMetrics.ctaPressOffset : 0

        return configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: WelcomeMetrics.ctaHeight)
            .background(
                Rectangle()   // radius 0 — squared by design
                    .fill(WelcomePalette.blue)
                    .shadow(color: WelcomePalette.hard, radius: 0, x: shadowOffset, y: shadowOffset)
            )
            .offset(x: shift, y: shift)
            .animation(reduceMotion ? nil : DesignSystem.Erewhon.ease(WelcomeMetrics.ctaPressDuration),
                       value: pressed)
    }
}

// MARK: - Value-prop data

private struct WelcomeValueProp {
    let icon: String
    let title: String
    let subtitle: String
    let tag: String

    static let all: [WelcomeValueProp] = [
        .init(icon: "target",
              title: "TRACK EFFORTLESSLY",
              subtitle: "Simply type in what you had for a meal, and AI will quick log it for you.",
              tag: "AI"),
        .init(icon: "bolt.fill",
              title: "BATTLE FRIENDS",
              subtitle: "Duel with your friends to have the better daily macros.",
              tag: "1V1"),
        .init(icon: "chevron.up.2",
              title: "CLIMB THE RANKS",
              subtitle: "Nine ranks from Stone to Zenith. Can you make it to the top?",
              tag: "9 RANKS")
    ]
}

// MARK: - Fixed pixel-clean palette, metrics & fonts (PC1)

// Erewhon fonts by PostScript name — bypasses AppFont so pixel-theme users still get
// Bebas/Hanken here (registered in --Info.plist UIAppFonts).
private func welcomeBebas(_ size: CGFloat) -> Font { .custom("BebasNeue-Regular", size: size) }
private func welcomeHanken(_ size: CGFloat) -> Font { .custom("HankenGrotesk-Regular", size: size) }
private func welcomeHankenSemibold(_ size: CGFloat) -> Font { .custom("HankenGrotesk-SemiBold", size: size) }

/// Silkscreen ACCENT face. The PostScript name mirrors the regular branch of
/// `DesignSystem.Typography.pixel` — the canonical registration site — rather than routing
/// through `AppFont`, which would swap the whole screen's type for pixel-theme users.
private func welcomeSilkscreen(_ size: CGFloat) -> Font { .custom("Silkscreen-Regular", size: size) }

// TODO-pixelclean-tokens: migrate to the shared pixel-clean token layer when it lands in DesignSystem.
/// Fixed pixel-clean colours, pinned to the marketing site's hex values so this screen matches
/// the site rather than the in-app theme. Nothing here reads `ThemeColors` or `SettingsManager`:
/// theme-derived tokens key off the user's live theme and would resolve wrongly on this
/// fixed-dark screen.
private enum WelcomePalette {
    static let bg = Color(hex: "#070B14")            // screen background
    static let ink = Color(hex: "#EAF0FB")           // primary text
    static let inkSoft = Color(hex: "#A9B7CF")       // tagline
    static let inkMute = Color(hex: "#6E7C97")       // secondary / labels
    static let blue = Color(hex: "#2563EB")          // primary button fill
    static let blue2 = Color(hex: "#3B82F6")         // wordmark accent
    static let blue3 = Color(hex: "#60A5FA")         // value-prop icons
    static let blueTint = Color(hex: "#3B82F6").opacity(0.15)   // icon tile fill, top wash
    static let cyan = Color(hex: "#38BDF8")          // eyebrow, pixel tags, "LV 1"
    static let cyanTint = Color(hex: "#38BDF8").opacity(0.15)   // eyebrow/tag fill, bottom wash
    static let hpBorder = Color(hex: "#2E6BFF")      // HP bar border + fill
    static let hpOver = Color(hex: "#48D6FF")        // overheal segment
    static let track = Color(hex: "#050E20")         // HP bar track
    static let line = Color.white.opacity(0.09)      // chip / tile borders
    static let lineSoft = Color.white.opacity(0.05)  // row dividers, footer hairline
    static let hard = Color.black.opacity(0.55)      // hard offset shadows
    static let pixelDotShadow = Color.black.opacity(0.25)   // eyebrow dot micro-shadow
}

/// Layout constants for the screen. "Hard shadow, offset N" throughout means
/// `.shadow(color: hard, radius: 0, x: N, y: N)` — zero blur, equal x/y.
private enum WelcomeMetrics {

    // MARK: Hard shadow offsets
    static let shadowPrimary: CGFloat = 5     // Get Started, at rest
    static let shadowPressed: CGFloat = 2     // Get Started, pressed
    static let shadowTile: CGFloat = 3        // value-prop icon tiles
    static let shadowPixelDot: CGFloat = 2    // eyebrow dot

    // MARK: Eyebrow
    static let eyebrowDot: CGFloat = 7
    static let eyebrowSpacing: CGFloat = 9
    static let eyebrowFont: CGFloat = 10
    static let eyebrowTracking: CGFloat = 1.2   // 0.12em at 10pt
    static let eyebrowPaddingV: CGFloat = 7
    static let eyebrowPaddingH: CGFloat = 12
    /// Shared by the eyebrow chip and the value-prop icon tiles.
    static let chipRadius: CGFloat = 7

    // MARK: Wordmark & tagline
    static let wordmarkFont: CGFloat = 64
    static let taglineFont: CGFloat = 16
    static let taglineLineSpacing: CGFloat = 3
    static let taglineTopPadding: CGFloat = 12

    // MARK: HP bar
    static let barHeight: CGFloat = 24
    static let barBorder: CGFloat = 3
    static let fillFraction: CGFloat = 0.66
    static let notchWidth: CGFloat = 4
    static let stripePitch: CGFloat = 18
    static let stripeWidth: CGFloat = 3
    static let stripeOpacity: Double = 0.4
    static let overGlowRadius: CGFloat = 6
    static let overGlowOpacity: Double = 0.5
    static let barHeaderFont: CGFloat = 9
    static let barHeaderTracking: CGFloat = 1.1
    static let barLevelFont: CGFloat = 12
    static let barHeaderBottomPadding: CGFloat = 9
    static let barFillDuration: Double = 1.6
    static let barFillDelay: Double = 0.4

    // MARK: Value props
    static let tileSize: CGFloat = 40
    static let tileIconFont: CGFloat = 17
    static let propRowSpacing: CGFloat = 14
    static let propRowPaddingV: CGFloat = 12
    static let propTextSpacing: CGFloat = 3
    static let propTitleFont: CGFloat = 12
    static let propTitleTracking: CGFloat = 0.7
    static let propSubtitleFont: CGFloat = 12.5
    static let tagFont: CGFloat = 8
    static let tagPaddingV: CGFloat = 4
    static let tagPaddingH: CGFloat = 7

    // MARK: CTA footer
    static let ctaFont: CGFloat = 14
    static let ctaTracking: CGFloat = 0.6
    static let ctaHeight: CGFloat = 56
    static let ctaPressOffset: CGFloat = 2
    static let ctaPressDuration: Double = 0.18
    static let loginFont: CGFloat = 15

    // MARK: Decorative background
    // Wash sizes/insets/blur are VISUAL-APPROXIMATE — matched to the mockup by eye. The
    // insets are edge overhangs: the circle hangs `insetX` past the horizontal edge and
    // `insetY` past the vertical one.
    static let washBlur: CGFloat = 70
    static let washFadeStop: CGFloat = 0.7
    /// √2 — CSS radial-gradients extend to the farthest CORNER of their box by default.
    static let washGradientExtent: CGFloat = 1.41421356
    static let washTopSize: CGFloat = 340
    static let washTopInsetX: CGFloat = 90
    static let washTopInsetY: CGFloat = 130
    static let washTopOpacity: Double = 0.9
    static let washBottomSize: CGFloat = 300
    static let washBottomInsetX: CGFloat = 100
    static let washBottomInsetY: CGFloat = 120
    static let washBottomOpacity: Double = 0.8
    static let scanlinePitch: CGFloat = 3
    static let scanlineWidth: CGFloat = 1
    static let scanlineOpacity: Double = 0.05

    // MARK: Bar geometry
    // Verified standalone before transcription (the HealthBar scheme has no <Testables>):
    // segment widths sum to the track and clamp at zero on degenerate widths; the stripe
    // count always covers the full track.

    /// Widths of the three interior bar segments across the full track: the blue
    /// fill, the white max notch, and the cyan overheal remainder.
    static func barSegments(trackWidth: CGFloat) -> (fill: CGFloat, notch: CGFloat, over: CGFloat) {
        let fill = max(0, trackWidth * fillFraction)
        let over = max(0, trackWidth - fill - notchWidth)
        return (fill, notchWidth, over)
    }

    /// Number of `stripePitch` gap + `stripeWidth` stripe units needed to cover the track.
    static func stripeUnitCount(trackWidth: CGFloat) -> Int {
        let period = stripePitch + stripeWidth
        guard trackWidth > 0, period > 0 else { return 0 }
        return Int((trackWidth / period).rounded(.up))
    }
}

// MARK: - Preview

#Preview {
    WelcomeView(onGetStarted: {}, onLogIn: {})
}
