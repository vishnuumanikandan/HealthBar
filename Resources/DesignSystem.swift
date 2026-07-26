//
//  DesignSystem.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//  Design System for HealthBar - Gamified Weight Loss iOS App
//
//  Visual Theme: LiftOff's sophisticated minimalist structure with bright,
//  energizing sustainability vibe. Clean and modern with lots of breathing room,
//  using vibrant greens and natural tones. Think: growth, vitality, natural wellness.
//

import SwiftUI

// MARK: - Design System

/// Central design system for HealthBar app
/// Provides colors, typography, spacing, and reusable components
enum DesignSystem {

    // MARK: - Colors

    enum Colors {

        // MARK: Background Colors

        /// Clean light background - rich green tint (#DCFCE7 light, #0F1B13 dark forest)
        static let primaryBackground = Color(light: Color(hex: "#DCFCE7"), dark: Color(hex: "#0F1B13"))

        /// Slightly elevated background - deeper mint (#E8F9F0 light, #1A2B1E dark)
        static let secondaryBackground = Color(light: Color(hex: "#E8F9F0"), dark: Color(hex: "#1A2B1E"))

        /// Elevated card background - white with noticeable green (#F3FDF7 light, #1F3326 dark)
        static let cardBackground = Color(light: Color(hex: "#F3FDF7"), dark: Color(hex: "#1F3326"))

        // MARK: Accent Colors

        /// Vibrant deep green (#059669) - main health/success color
        static let primary = Color(hex: "#059669")

        /// Rich emerald (#10B981) - secondary actions, highlights
        static let secondary = Color(hex: "#10B981")

        /// Bold amber (#D97706) - streaks, fire, warmth
        static let energy = Color(hex: "#D97706")

        /// Dark forest green (#047857) - leveling up, achievements
        static let growth = Color(hex: "#047857")

        /// Deep orange (#EA580C) - cautions
        static let warning = Color(hex: "#EA580C")

        /// Strong red (#DC2626) - deletions, errors
        static let danger = Color(hex: "#DC2626")

        // MARK: Neutral Colors

        /// Dark charcoal (#111827 light, #F9FAFB dark)
        static let textPrimary = Color(light: Color(hex: "#111827"), dark: Color(hex: "#F9FAFB"))

        /// Medium gray (#6B7280)
        static let textSecondary = Color(hex: "#6B7280")

        /// Light gray (#9CA3AF)
        static let textTertiary = Color(hex: "#9CA3AF")

        /// Subtle border (#E5E7EB light, #374151 dark)
        static let border = Color(light: Color(hex: "#E5E7EB"), dark: Color(hex: "#374151"))

        // MARK: Gradients

        /// Vibrant green to mint gradient
        static let primaryGradient = LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Subtle white to very light green gradient
        static let cardGradient = LinearGradient(
            colors: [
                Color.white,
                Color(hex: "#F0FDF4") // Very light green
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Green glow effect for achievements
        static let successGlow = primary.opacity(0.3)

        // MARK: - Pixel Theme Palettes

        // Parchment / Quest colors
        static let parchmentFill = Color(hex: "#F5E6C8")
        static let parchmentBorder = Color(hex: "#A0845C")
        static let parchmentText = Color(hex: "#3D2213")
        static let parchmentSecondary = Color(hex: "#7A6548")

        // Gold / XP badge
        static let goldHighlight = Color(hex: "#FFD700")
        static let goldMid = Color(hex: "#F5A623")
        static let goldDark = Color(hex: "#C8860B")
        static let goldBorder = Color(hex: "#8B6914")

        // Wood
        static let woodDark = Color(hex: "#2E1A0E")
        static let woodMid = Color(hex: "#4A2E1C")
        static let woodFill = Color(hex: "#C4A070")
        static let woodHighlight = Color(hex: "#D4B488")
        static let woodShadow = Color(hex: "#B08850")
        static let woodSeam = Color(hex: "#8B6B40")
        static let woodBracket = Color(hex: "#3D2213")
        static let woodNail = Color(hex: "#2E1A0E")

        // Tab bar wood
        static let tabWoodHighlight = Color(hex: "#A0723D")
        static let tabWoodBody = Color(hex: "#8B5A2B")
        static let tabWoodShadow = Color(hex: "#5D3A1A")
        static let tabActive = Color(hex: "#FCD34D")
        static let tabInactive = Color(hex: "#D2B48C")

        // Indigo / Weekly stats
        static let indigoBorder = Color(hex: "#4338CA")
        static let indigoFill = Color(hex: "#EEF2FF")
        static let indigoCardBorder = Color(hex: "#6366F1")
        static let indigoCardFill = Color(hex: "#E0E7FF")
        static let indigoText = Color(hex: "#312E81")
        static let indigoLabel = Color(hex: "#4338CA")
        static let indigoHighlight = Color(hex: "#818CF8")

        // Bookmark red
        static let bookmarkLight = Color(hex: "#EF4444")
        static let bookmarkMid = Color(hex: "#DC2626")
        static let bookmarkDark = Color(hex: "#991B1B")

        // Segmented control
        static let segInactiveFill = Color(hex: "#374151")
        static let segInactiveText = Color(hex: "#D1D5DB")

        // MARK: - 3-Band Gradient Builder

        static func threeBand(light: Color, mid: Color, dark: Color, lightStop: CGFloat = 0.22, darkStop: CGFloat = 0.78) -> LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: light, location: 0),
                    .init(color: light, location: lightStop),
                    .init(color: mid, location: lightStop),
                    .init(color: mid, location: darkStop),
                    .init(color: dark, location: darkStop),
                    .init(color: dark, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // Pre-defined 3-band gradients
        static let band3Green = threeBand(light: Color(hex: "#34D399"), mid: Color(hex: "#10B981"), dark: Color(hex: "#059669"))
        static let band3DarkGreen = threeBand(light: Color(hex: "#059669"), mid: Color(hex: "#047857"), dark: Color(hex: "#064E3B"))
        static let band3Emerald = threeBand(light: Color(hex: "#6EE7B7"), mid: Color(hex: "#34D399"), dark: Color(hex: "#10B981"))
        static let band3Amber = threeBand(light: Color(hex: "#FBBF24"), mid: Color(hex: "#D97706"), dark: Color(hex: "#92400E"))
        static let band3Orange = threeBand(light: Color(hex: "#FB923C"), mid: Color(hex: "#EA580C"), dark: Color(hex: "#C2410C"))
        static let band3Gold = threeBand(light: Color(hex: "#FFD700"), mid: Color(hex: "#F5A623"), dark: Color(hex: "#C8860B"))
        static let band3Indigo = threeBand(light: Color(hex: "#818CF8"), mid: Color(hex: "#6366F1"), dark: Color(hex: "#4338CA"))
        static let band3Gray = threeBand(light: Color(hex: "#D1D5DB"), mid: Color(hex: "#9CA3AF"), dark: Color(hex: "#6B7280"))

        // Button gradient (11% / 81% stops)
        static let band3ButtonGreen = threeBand(light: Color(hex: "#34D399"), mid: Color(hex: "#10B981"), dark: Color(hex: "#047857"), lightStop: 0.11, darkStop: 0.81)

        /// Auto-generate a 3-band gradient from a single color (highlight / body / shadow).
        /// Uses brightness shifts instead of opacity so the shadow band stays opaque.
        static func threeBandFrom(_ color: Color) -> LinearGradient {
            threeBand(
                light: color.opacity(0.7),
                mid: color,
                dark: color.adjustedBrightness(-0.25)
            )
        }

        // MARK: - Adaptive Gradient Helpers (Clean vs RPG)

        /// Returns a 3-band gradient in RPG mode, or a solid fill in clean mode.
        static func adaptiveGradient(light: Color, mid: Color, dark: Color, lightStop: CGFloat = 0.22, darkStop: CGFloat = 0.78) -> LinearGradient {
            if SettingsManager.shared.isCleanUI {
                return LinearGradient(colors: [mid], startPoint: .top, endPoint: .bottom)
            }
            return threeBand(light: light, mid: mid, dark: dark, lightStop: lightStop, darkStop: darkStop)
        }

        /// Returns a 3-band auto-gradient in RPG mode, or a solid fill in clean mode.
        static func adaptiveGradientFrom(_ color: Color) -> LinearGradient {
            if SettingsManager.shared.isCleanUI {
                return LinearGradient(colors: [color], startPoint: .top, endPoint: .bottom)
            }
            return threeBandFrom(color)
        }
    }

    // MARK: - Typography

    enum Typography {

        /// Pixel font for the RPG theme (Silkscreen)
        static func pixel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            let name = weight == .bold ? "Silkscreen-Bold" : "Silkscreen-Regular"
            return .custom(name, size: size)
        }

        /// 34pt, bold - For large titles
        static func largeTitle(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 34, weight: .bold, design: .default))
        }

        /// 28pt, semibold - For primary titles
        static func title(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 28, weight: .semibold, design: .default))
        }

        /// 22pt, semibold - For secondary titles
        static func title2(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 22, weight: .semibold, design: .default))
        }

        /// 17pt, semibold - For headlines
        static func headline(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .default))
        }

        /// 17pt, regular - For body text
        static func body(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 17, weight: .regular, design: .default))
        }

        /// 16pt, regular - For callouts
        static func callout(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 16, weight: .regular, design: .default))
        }

        /// 12pt, regular - For captions
        static func caption(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .default))
        }
    }

    // MARK: - Spacing (8pt grid system)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Common Sizes

    enum Sizes {
        /// Standard icon circle size
        static let iconCircle: CGFloat = 40

        /// Small icon circle size
        static let iconCircleSmall: CGFloat = 36

        /// Medium thumbnail size (food photos, etc)
        static let thumbnail: CGFloat = 60

        /// Large thumbnail size
        static let thumbnailLarge: CGFloat = 80

        /// Floating action button size
        static let floatingButton: CGFloat = 60

        /// Crown/rank badge size
        static let rankBadge: CGFloat = 50
    }

    // MARK: - Font Sizes

    enum FontSizes {
        static let largeTitle: CGFloat = 34
        static let title: CGFloat = 28
        static let title2: CGFloat = 22
        static let title3: CGFloat = 20
        static let headline: CGFloat = 17
        static let body: CGFloat = 17
        static let callout: CGFloat = 16
        static let subheadline: CGFloat = 15
        static let footnote: CGFloat = 14
        static let caption: CGFloat = 12
        static let caption2: CGFloat = 10
    }

    // MARK: - Shadows & Effects

    enum Shadows {
        /// Soft elevation shadow for cards
        static let card = Shadow(
            color: Color.black.opacity(0.08),
            radius: 12,
            x: 0,
            y: 4
        )

        /// Subtle green glow for interactive elements
        static let accentGlow = Shadow(
            color: Colors.primary.opacity(0.25),
            radius: 8,
            x: 0,
            y: 2
        )

        /// Pulsing green glow for achievements
        static let successPulse = Shadow(
            color: Colors.primary.opacity(0.4),
            radius: 16,
            x: 0,
            y: 0
        )
    }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Erewhon Tokens (R1)

    /// Additive token namespace for the Erewhon reskin (R1–R6). Nothing existing moves
    /// here; later R-prompts consume these. Values from the §1 token table, cross-checked
    /// against design/erewhon/arena.html.
    enum Erewhon {
        /// Card corner radius for the Erewhon flat treatment.
        static let cardRadius: CGFloat = 18

        // Rank metals (adaptive Color(light:dark:); tracks the forced scheme appearance).
        static let rankGold = Color(light: Color(hex: "#CE9A33"), dark: Color(hex: "#E0B047"))
        static let rankSilver = Color(light: Color(hex: "#A6AEB9"), dark: Color(hex: "#A6AEB9"))
        static let rankIron = Color(light: Color(hex: "#7E8896"), dark: Color(hex: "#7E8896"))
        static let rankBronze = Color(light: Color(hex: "#B06A3C"), dark: Color(hex: "#C8814A"))
        /// Single-Color representative for the prismatic top three (Sentinel/Prismatic/Zenith).
        /// The plaques themselves sweep a full AngularGradient (see `RankPlaque`); this is the
        /// flat stand-in for anywhere the ladder needs ONE colour per rank.
        static let rankPrismatic = Color(light: Color(hex: "#8F7BE8"), dark: Color(hex: "#8F7BE8"))

        /// Rank-tier avatar metal from `rr`. `nil` → neutral fill. Bronze/iron/gold map to the
        /// Erewhon metal tokens; platinum and diamond use the live accent (mockup `rk-diamond`);
        /// the top three (RR ≥ 1800) are prismatic violet (R7a).
        /// Decorative wash, not a precise per-rank ladder colour.
        static func rankMetal(forRR rr: Int?) -> Color? {
            guard let rr else { return nil }
            switch Rank.getRank(from: rr) {
            case .stone: return nil
            case .copper: return rankBronze
            case .iron: return rankIron
            case .gold: return rankGold
            case .platinum, .diamond: return SettingsManager.shared.activeColors.primary
            case .sentinel, .prismatic, .zenith: return rankPrismatic
            }
        }

        // Reserved hues (consumed by later R-prompts).
        static let pink = Color(light: Color(hex: "#AF4D80"), dark: Color(hex: "#DE77AB"))
        static let social = Color(light: Color(hex: "#00739D"), dark: Color(hex: "#00A4CD"))

        /// Hairline border for the active Erewhon scheme (ink @ 11% light / #E8EBF2 @ 13%
        /// dark). Keyed off `SettingsManager.shared.isCleanDark`, which per D3 now means
        /// "Erewhon Dark".
        static var line: Color {
            SettingsManager.shared.isCleanDark
                ? Color(hex: "#E8EBF2").opacity(0.13)
                : Color(hex: "#111318").opacity(0.11)
        }

        /// Soft separator for the active Erewhon scheme (ink @ 5% light / #E8EBF2 @ 6%
        /// dark). Keyed off `isCleanDark` (Erewhon Dark) per D3.
        static var lineSoft: Color {
            SettingsManager.shared.isCleanDark
                ? Color(hex: "#E8EBF2").opacity(0.06)
                : Color(hex: "#111318").opacity(0.05)
        }

        /// Signature Erewhon easing curve — cubic-bezier(0.16, 1, 0.3, 1), duration-parameterized.
        static func ease(_ duration: Double = 0.5) -> Animation {
            Animation.timingCurve(0.16, 1, 0.3, 1, duration: duration)
        }

        /// Card shadow token (mirrors Shadows.card: black 8%, radius 12, y 4).
        static let cardShadow: (color: Color, radius: CGFloat, y: CGFloat) =
            (Color.black.opacity(0.08), 12, 4)

        // MARK: R2 additions

        /// Text/icon color on accent fills (mockup --on-accent).
        static let onAccent = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#060A1A"))

        /// Button corner radius (mockup .btn 14px; cards stay 18).
        static let buttonRadius: CGFloat = 14

        /// Tab bar content height above the bottom safe area (the mockup's 84px bar
        /// includes the home-indicator region, which safeAreaInset supplies automatically).
        static let tabBarContentHeight: CGFloat = 64

        /// Persistent top-bar content height below the top safe area (R7b §1). Mirror of
        /// `tabBarContentHeight`: the status-bar region is supplied automatically by the
        /// top `safeAreaInset`, so this is the chrome's own height (level/XP · streak).
        static let topBarContentHeight: CGFloat = 52

        /// Subtle raised-element shadow (mockup --shadow-1 approximation).
        static let subtleShadow: (color: Color, radius: CGFloat, y: CGFloat) =
            (Color.black.opacity(0.06), 7, 3)
    }

    // MARK: - Metrics (OCCLUSION-1)

    /// Layout metrics shared across the app. Single source of truth for the custom
    /// bottom tab bar's height.
    enum Metrics {
        /// Breathing room above a tab bar's content, below its top hairline. Both
        /// `CleanTabBar` and `WoodenTabBar` apply it as their top padding, and
        /// `tabBarHeight` below is built from it, so the three can't drift.
        static let tabBarTopInset: CGFloat = 12

        /// Height of the custom bottom tab bar ABOVE the home-indicator safe area — i.e.
        /// the clearance a screen pushed inside a tab's own `NavigationStack` must add so
        /// its last control sits above the bar.
        ///
        /// Root tab screens get this clearance automatically from the TabView's
        /// `.safeAreaInset` bar (`ContentView`), but that inset does NOT propagate into
        /// child `NavigationStack`s — the paid-for R2/R6 lesson OCCLUSION-1 fixes. Pushed
        /// screens (guild chat composer, guild detail's Leave/Disband) therefore clear the
        /// bar by this token.
        ///
        /// Equals `CleanTabBar`'s rendered height: `Erewhon.tabBarContentHeight` (64pt of
        /// content) + `tabBarTopInset` (12) = 76. `WoodenTabBar` renders shorter (~56–64pt
        /// on device), so this single token — the taller, shipping Clean bar — over-clears
        /// the pixel bar harmlessly and serves both themes. (The home-indicator region is
        /// supplied separately by each screen's own bottom safe area, so it is NOT included
        /// here.)
        static let tabBarHeight: CGFloat = Erewhon.tabBarContentHeight + tabBarTopInset

        // MARK: - LB-PAGE-1: leaderboard box heights

        /// Fixed height of the Battle global-standings box (the internally-scrolling, paged
        /// board). Sized so ~10 rows scroll within it, with the pager reached at the bottom.
        static let leaderboardBoxHeight: CGFloat = 338

        /// Fixed height of the compact leaderboard box (guild + friend boards). Shorter than
        /// `leaderboardBoxHeight` — those boards are fully fetched and carry no pager.
        static let leaderboardBoxHeightCompact: CGFloat = 280
    }
}

// MARK: - Reusable SwiftUI Components

// MARK: 1. AppButton

/// Clean rounded button component with LiftOff-style design
/// Supports primary gradient, secondary outline, loading, and disabled states
struct AppButton: View {

    enum Style {
        case primary
        case secondary
    }

    let title: String
    let style: Style
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var icon: String? = nil

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            if !isDisabled && !isLoading {
                action()
            }
        }) {
            Group {
                if SettingsManager.shared.isCleanUI {
                    flatBody      // Erewhon (flat family) — active-theme tokens, mockup buttons
                } else {
                    pixelBody     // pixel — byte-identical to the pre-R2 rendering
                }
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isDisabled ? 0.5 : 1.0)
            // Press animation: flat swaps to the Erewhon ease; pixel keeps the spring.
            .animation(SettingsManager.shared.isCleanUI
                       ? DesignSystem.Erewhon.ease(0.2)
                       : .spring(response: 0.3, dampingFraction: 0.6),
                       value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .disabled(isDisabled || isLoading)
    }

    /// Shared icon + title stack (font size / tints vary by family).
    @ViewBuilder
    private func buttonLabel(fontSize: CGFloat, tint: Color, spinnerTint: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: spinnerTint))
            } else {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppFont.bold(fontSize))
                }

                Text(title)
                    .font(AppFont.bold(fontSize))
            }
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
    }

    // MARK: Erewhon (flat) — active-theme tokens only; ZERO DesignSystem.Colors references.
    private var flatBody: some View {
        let tc = SettingsManager.shared.activeColors
        let isPrimary = (style == .primary)
        // Mockup .btn is 14/700; HankenGrotesk-SemiBold at 15 is the chosen equivalent
        // (the single typographic deviation for AppButton — noted).
        return buttonLabel(
            fontSize: 15,
            tint: isPrimary ? DesignSystem.Erewhon.onAccent : tc.textPrimary,
            spinnerTint: isPrimary ? DesignSystem.Erewhon.onAccent : tc.textPrimary
        )
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Erewhon.buttonRadius)
                .fill(isPrimary ? tc.primary : tc.cardBackground)   // .primary solid; .secondary ghost
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Erewhon.buttonRadius)
                .stroke(isPrimary ? Color.clear : DesignSystem.Erewhon.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Erewhon.buttonRadius))
        .shadow(
            color: isPrimary ? tc.primary.opacity(0.34) : DesignSystem.Erewhon.subtleShadow.color,
            radius: isPrimary ? 9 : DesignSystem.Erewhon.subtleShadow.radius,
            x: 0,
            y: isPrimary ? 6 : DesignSystem.Erewhon.subtleShadow.y
        )
    }

    // MARK: Pixel — preserved exactly (band3Green fill, #047857 2px border, pixel shape).
    private var pixelBody: some View {
        buttonLabel(
            fontSize: 17,
            tint: style == .primary ? .white : DesignSystem.Colors.primary,
            spinnerTint: style == .primary ? .white : DesignSystem.Colors.primary
        )
        .background(pixelBackground)
        .overlay(
            AdaptiveCardShapeStyle()
                .stroke(style == .secondary ? DesignSystem.Colors.primary : Color(hex: "#047857"), lineWidth: 2)
        )
        .clipShape(AdaptiveCardShapeStyle())
    }

    @ViewBuilder
    private var pixelBackground: some View {
        switch style {
        case .primary:
            DesignSystem.Colors.band3Green
        case .secondary:
            Color.clear
        }
    }
}

// MARK: 2. StatCard

/// Minimal card component with generous padding and LiftOff spacing
/// Displays an icon, title, value, and optional progress bar
struct StatCard: View {

    let icon: String
    let title: String
    let value: String
    let iconColor: Color
    var progress: Double? = nil
    var progressColor: Color = DesignSystem.Colors.primary

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Icon with subtle circular background
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(AppFont.bold(18))
                        .foregroundColor(iconColor)
                }

                Spacer()
            }

            // Title
            Text(title)
                .font(AppFont.regular(14))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Large value display
            Text(value)
                .font(AppFont.bold(28))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // Optional thin progress bar
            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DesignSystem.Colors.border)
                            .frame(height: 4)

                        // Progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: DesignSystem.Colors.primary.opacity(0.25), fillColor: DesignSystem.Colors.cardBackground)
    }
}

// MARK: 3. ProgressRing

/// Circular progress indicator with LiftOff-style design
/// Green gradient stroke with center value display and smooth animations
struct ProgressRing: View {

    let progress: Double // 0.0 to 1.0
    let lineWidth: CGFloat
    let size: CGFloat
    var showPercentage: Bool = true
    var centerText: String? = nil

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            // Background ring (muted)
            Circle()
                .stroke(
                    SettingsManager.shared.activeColors.ringEmpty,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            // Progress ring (gradient)
            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    LinearGradient(
                        colors: [SettingsManager.shared.activeColors.xpFillLight, SettingsManager.shared.activeColors.ringFilled],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: normalizedProgress)

            // Center value display
            VStack(spacing: 2) {
                if let centerText = centerText {
                    Text(centerText)
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundColor(SettingsManager.shared.activeColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if showPercentage {
                    Text("\(Int(normalizedProgress * 100))%")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundColor(SettingsManager.shared.activeColors.textPrimary)
                }
            }
            .frame(maxWidth: size - lineWidth * 2) // Constrain text width to ring interior
        }
    }
}

// MARK: 4. XPBadge

/// Minimal pill-shaped XP badge component
/// Displays XP value with green gradient or solid background
struct XPBadge: View {

    let xp: Int
    var useGradient: Bool = true
    var size: BadgeSize = .medium

    enum BadgeSize {
        case small
        case medium
        case large

        var fontSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 14
            case .large: return 16
            }
        }

        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .medium: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .large: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(AppFont.bold(size.fontSize - 2))

            Text("+\(xp) XP")
                .font(AppFont.bold(size.fontSize))
        }
        .foregroundColor(.white)
        .padding(size.padding)
        .background(
            Group {
                if useGradient {
                    DesignSystem.Colors.primaryGradient
                } else {
                    DesignSystem.Colors.primary
                }
            }
        )
        .clipShape(AdaptivePillShapeStyle())
    }
}

// MARK: 5. EmptyStateView

/// Empty state view with generous spacing and clean typography hierarchy
/// LiftOff-style breathing room with large icon and optional action button
struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    /// Active-theme colors (R8: retired statics → themed card treatment).
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            // R8: green-filled empty state → themed card (fill + hairline border).
            VStack(spacing: DesignSystem.Spacing.lg) {
                // R5b tinted icon-box (retired gray glyph → accent glyph on a tinted box)
                Image(systemName: icon)
                    .font(AppFont.regular(40))
                    .foregroundColor(tc.primary)
                    .frame(width: 76, height: 76)
                    .background(tc.primary.opacity(0.14))
                    .clipShape(AdaptivePillShapeStyle())

                // Clean typography hierarchy
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text(title)
                        .font(AppFont.bold(22))
                        .foregroundColor(tc.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                // Optional action button
                if let actionTitle = actionTitle, let action = action {
                    AppButton(
                        title: actionTitle,
                        style: .primary,
                        action: action
                    )
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.md)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xxl)
            .frame(maxWidth: .infinity)
            .adaptiveCard(
                borderColor: tc.primary.opacity(0.3),
                fillColor: tc.cardBackground
            )
            .padding(.horizontal, DesignSystem.Spacing.lg)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground)
    }
}

// MARK: 6. AuthTextField

/// Styled text field for authentication screens (login and sign-up).
///
/// Supports email and secure (password) variants with:
/// - An inline error message beneath the field for per-field validation failures
/// - An eye toggle button to reveal/hide password text
/// - Keyboard return-key routing via `submitLabel` and `onSubmit`
/// - Full VoiceOver support and Dynamic Type compatibility
/// - Minimum 44×44 pt tap target on the reveal toggle
struct AuthTextField: View {

    // MARK: - Configuration

    /// Visible label shown above the input field.
    let label: String

    /// Placeholder text shown when the field is empty.
    let placeholder: String

    /// Two-way binding to the text value (owned by AuthViewModel).
    @Binding var text: String

    /// When `true`, renders a `SecureField` with a reveal toggle.
    var isSecure: Bool = false

    /// When `true`, the field takes the email keyboard and never autocapitalizes.
    /// When `false` (the default), it takes the standard keyboard with word
    /// autocapitalization — correct for names and free text. Secure fields ignore this.
    var isEmailField: Bool = false

    /// Per-field validation error message. When non-nil, the field border turns
    /// red and the message appears beneath the field.
    var errorMessage: String? = nil

    /// The submit/return key label shown on the software keyboard.
    var submitLabel: SubmitLabel = .done

    /// Called when the user taps the keyboard return/submit key.
    /// Use this to route focus to the next field or trigger submission.
    var onSubmit: (() -> Void)? = nil

    // MARK: - Private State

    /// Whether the secure field is currently showing plain text.
    @State private var isRevealed: Bool = false

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Field label
            Text(label)
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)

            // Input field + optional reveal toggle
            ZStack(alignment: .trailing) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(isEmailField ? .emailAddress : .default)
                            // A revealed password takes the secure path's keyboard, so it
                            // must never autocapitalize regardless of `isEmailField`.
                            .textInputAutocapitalization(isEmailField || isSecure ? .never : .words)
                            .autocorrectionDisabled()
                    }
                }
                .font(AppFont.regular(DesignSystem.FontSizes.body))
                .foregroundColor(tc.textPrimary)
                // Indent right edge when the reveal toggle is present to avoid overlap
                .padding(.leading, DesignSystem.Spacing.md)
                .padding(.trailing, isSecure ? 52 : DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
                .frame(minHeight: 52)
                .background(tc.cardBackground)
                .clipShape(AdaptiveCardShapeStyle())
                .overlay(
                    AdaptiveCardShapeStyle()
                        .stroke(
                            errorMessage != nil
                                ? DesignSystem.Colors.danger
                                : tc.primary.opacity(0.3),
                            lineWidth: errorMessage != nil ? 2 : 1
                        )
                )
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
                .accessibilityLabel(label)

                // Reveal / hide toggle (password fields only)
                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(tc.textTertiary)
                            // 44×44 pt minimum tap target (HIG requirement)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                    .padding(.trailing, DesignSystem.Spacing.xs)
                }
            }

            // Inline field-level error message
            if let error = errorMessage {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.danger)

                    Text(error)
                        .font(AppFont.regular(12))
                        .foregroundColor(DesignSystem.Colors.danger)
                }
                // Announce the combined error message to VoiceOver
                .accessibilityElement(children: .combine)
                .accessibilityLabel(error)
            }
        }
    }
}

// MARK: - Pixel Art Shapes

/// Stair-step octagonal shape for cards (4-step × 3px = 12px chamfer)
/// Draws the same polygon as the CSS clip-path from the HTML mockup.
struct PixelCardShape: Shape {
    var step: CGFloat = 3
    var steps: Int = 4

    func path(in rect: CGRect) -> Path {
        let s = step
        let w = rect.width
        let h = rect.height
        let c = s * CGFloat(steps) // 12pt chamfer

        var p = Path()
        // Top edge, left to right
        p.move(to: CGPoint(x: c, y: 0))
        p.addLine(to: CGPoint(x: w - c, y: 0))
        // Top-right stair
        p.addLine(to: CGPoint(x: w - 3*s, y: 0))
        p.addLine(to: CGPoint(x: w - 3*s, y: s))
        p.addLine(to: CGPoint(x: w - 2*s, y: s))
        p.addLine(to: CGPoint(x: w - 2*s, y: 2*s))
        p.addLine(to: CGPoint(x: w - s, y: 2*s))
        p.addLine(to: CGPoint(x: w - s, y: 3*s))
        p.addLine(to: CGPoint(x: w, y: 3*s))
        p.addLine(to: CGPoint(x: w, y: c))
        // Right edge
        p.addLine(to: CGPoint(x: w, y: h - c))
        // Bottom-right stair
        p.addLine(to: CGPoint(x: w, y: h - 3*s))
        p.addLine(to: CGPoint(x: w - s, y: h - 3*s))
        p.addLine(to: CGPoint(x: w - s, y: h - 2*s))
        p.addLine(to: CGPoint(x: w - 2*s, y: h - 2*s))
        p.addLine(to: CGPoint(x: w - 2*s, y: h - s))
        p.addLine(to: CGPoint(x: w - 3*s, y: h - s))
        p.addLine(to: CGPoint(x: w - 3*s, y: h))
        p.addLine(to: CGPoint(x: w - c, y: h))
        // Bottom edge
        p.addLine(to: CGPoint(x: c, y: h))
        // Bottom-left stair
        p.addLine(to: CGPoint(x: 3*s, y: h))
        p.addLine(to: CGPoint(x: 3*s, y: h - s))
        p.addLine(to: CGPoint(x: 2*s, y: h - s))
        p.addLine(to: CGPoint(x: 2*s, y: h - 2*s))
        p.addLine(to: CGPoint(x: s, y: h - 2*s))
        p.addLine(to: CGPoint(x: s, y: h - 3*s))
        p.addLine(to: CGPoint(x: 0, y: h - 3*s))
        p.addLine(to: CGPoint(x: 0, y: h - c))
        // Left edge
        p.addLine(to: CGPoint(x: 0, y: c))
        // Top-left stair
        p.addLine(to: CGPoint(x: 0, y: 3*s))
        p.addLine(to: CGPoint(x: s, y: 3*s))
        p.addLine(to: CGPoint(x: s, y: 2*s))
        p.addLine(to: CGPoint(x: 2*s, y: 2*s))
        p.addLine(to: CGPoint(x: 2*s, y: s))
        p.addLine(to: CGPoint(x: 3*s, y: s))
        p.addLine(to: CGPoint(x: 3*s, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Stair-step pill shape for smaller elements (3-step × 2px = 6px chamfer)
struct PixelPillShape: Shape {
    var step: CGFloat = 2
    var steps: Int = 3

    func path(in rect: CGRect) -> Path {
        let s = step
        let w = rect.width
        let h = rect.height
        let c = s * CGFloat(steps) // 6pt chamfer

        var p = Path()
        p.move(to: CGPoint(x: c, y: 0))
        p.addLine(to: CGPoint(x: w - c, y: 0))
        // Top-right
        p.addLine(to: CGPoint(x: w - 2*s, y: 0))
        p.addLine(to: CGPoint(x: w - 2*s, y: s))
        p.addLine(to: CGPoint(x: w - s, y: s))
        p.addLine(to: CGPoint(x: w - s, y: 2*s))
        p.addLine(to: CGPoint(x: w, y: 2*s))
        p.addLine(to: CGPoint(x: w, y: c))
        // Right edge
        p.addLine(to: CGPoint(x: w, y: h - c))
        // Bottom-right
        p.addLine(to: CGPoint(x: w, y: h - 2*s))
        p.addLine(to: CGPoint(x: w - s, y: h - 2*s))
        p.addLine(to: CGPoint(x: w - s, y: h - s))
        p.addLine(to: CGPoint(x: w - 2*s, y: h - s))
        p.addLine(to: CGPoint(x: w - 2*s, y: h))
        p.addLine(to: CGPoint(x: w - c, y: h))
        // Bottom edge
        p.addLine(to: CGPoint(x: c, y: h))
        // Bottom-left
        p.addLine(to: CGPoint(x: 2*s, y: h))
        p.addLine(to: CGPoint(x: 2*s, y: h - s))
        p.addLine(to: CGPoint(x: s, y: h - s))
        p.addLine(to: CGPoint(x: s, y: h - 2*s))
        p.addLine(to: CGPoint(x: 0, y: h - 2*s))
        p.addLine(to: CGPoint(x: 0, y: h - c))
        // Left edge
        p.addLine(to: CGPoint(x: 0, y: c))
        // Top-left
        p.addLine(to: CGPoint(x: 0, y: 2*s))
        p.addLine(to: CGPoint(x: s, y: 2*s))
        p.addLine(to: CGPoint(x: s, y: s))
        p.addLine(to: CGPoint(x: 2*s, y: s))
        p.addLine(to: CGPoint(x: 2*s, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Pixel card container with stair-step octagonal border
struct PixelCard<Content: View>: View {
    var borderColor: Color = DesignSystem.Colors.primary
    var fillColor: Color = DesignSystem.Colors.cardBackground
    var fillGradient: LinearGradient? = nil
    var step: CGFloat = 3
    var steps: Int = 4
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            PixelCardShape(step: step, steps: steps)
                .fill(borderColor)
            PixelCardShape(step: step, steps: steps)
                .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                .padding(2)
            content()
        }
    }
}

/// Pixel pill container with stair-step pill border
struct PixelPill<Content: View>: View {
    var borderColor: Color = DesignSystem.Colors.primary
    var fillColor: Color = DesignSystem.Colors.cardBackground
    var fillGradient: LinearGradient? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            PixelPillShape()
                .fill(borderColor)
            PixelPillShape()
                .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                .padding(2)
            content()
        }
    }
}

// MARK: - PixelFont Convenience

enum PixelFont {
    static func bold(_ size: CGFloat) -> Font {
        DesignSystem.Typography.pixel(size, weight: .bold)
    }
    static func regular(_ size: CGFloat) -> Font {
        DesignSystem.Typography.pixel(size)
    }
}

// MARK: - Pixel Shape View Modifiers

extension View {
    func pixelCard(
        borderColor: Color = DesignSystem.Colors.primary,
        fillColor: Color = DesignSystem.Colors.cardBackground,
        fillGradient: LinearGradient? = nil
    ) -> some View {
        self
            .background(
                ZStack {
                    PixelCardShape()
                        .fill(borderColor)
                    PixelCardShape()
                        .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                        .padding(2)
                }
            )
            .clipShape(PixelCardShape())
    }

    func pixelPill(
        borderColor: Color = DesignSystem.Colors.primary,
        fillColor: Color = DesignSystem.Colors.cardBackground,
        fillGradient: LinearGradient? = nil
    ) -> some View {
        self
            .background(
                ZStack {
                    PixelPillShape()
                        .fill(borderColor)
                    PixelPillShape()
                        .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                        .padding(2)
                }
            )
            .clipShape(PixelPillShape())
    }
}

// MARK: - AppFont Convenience

/// Adaptive font. The flat family (now Erewhon, formerly Clean — the `isCleanUI` name is
/// retained from the retired Clean era) uses Hanken Grotesk for body/emphasis and Bebas
/// Neue for display; the pixel family uses Silkscreen (byte-identical to before).
///
/// TEXTSIZE-1 INVARIANT: every size-producing member of AppFont MUST apply
/// SettingsManager.shared.textScaleFactor before constructing the Font.
/// New members added later inherit this rule — no exceptions.
enum AppFont {
    /// Emphasis / body-bold. Erewhon: Hanken Grotesk SemiBold (600 — the mockup's
    /// dominant emphasis weight). Pixel: Silkscreen bold.
    static func bold(_ size: CGFloat) -> Font {
        let scaled = size * SettingsManager.shared.textScaleFactor
        if SettingsManager.shared.isCleanUI {
            return .custom("HankenGrotesk-SemiBold", size: scaled)
        }
        return DesignSystem.Typography.pixel(scaled, weight: .bold)
    }

    /// Body / regular. Erewhon: Hanken Grotesk Regular. Pixel: Silkscreen regular.
    static func regular(_ size: CGFloat) -> Font {
        let scaled = size * SettingsManager.shared.textScaleFactor
        if SettingsManager.shared.isCleanUI {
            return .custom("HankenGrotesk-Regular", size: scaled)
        }
        return DesignSystem.Typography.pixel(scaled)
    }

    /// Display type — numerals, titles, and hero/stat text ONLY (never body/paragraph).
    /// Erewhon: Bebas Neue. Pixel: Silkscreen bold.
    static func display(_ size: CGFloat) -> Font {
        let scaled = size * SettingsManager.shared.textScaleFactor
        if SettingsManager.shared.isCleanUI {
            return .custom("BebasNeue-Regular", size: scaled)
        }
        return DesignSystem.Typography.pixel(scaled, weight: .bold)
    }

    /// Legacy app-title treatment. The serif era retired with Clean; the flat branch now
    /// routes to `display` (Bebas Neue). Pixel: Silkscreen bold (unchanged).
    static func serifTitle(_ size: CGFloat) -> Font {
        if SettingsManager.shared.isCleanUI {
            // Delegates to display(_:), which applies textScaleFactor itself. Do NOT
            // pre-scale here — that would double-apply the factor in the Erewhon branch
            // (TEXTSIZE-1: scale exactly once, at the point the Font is constructed).
            return display(size)
        }
        return DesignSystem.Typography.pixel(size * SettingsManager.shared.textScaleFactor, weight: .bold)
    }
}

// MARK: - Adaptive Shape View Modifiers

extension View {
    /// Adaptive card: PixelCardShape in pixel themes, Erewhon flat card otherwise.
    /// (Erewhon branch ignores the passed `cornerRadius` in favor of `Erewhon.cardRadius`
    /// per D6; the param is retained for source compatibility with existing call sites.)
    ///
    /// Selection (R6c): caller-declared via `isSelected`. When true, the Erewhon branch
    /// strokes the active accent at 1.5px so pickers read as selected; otherwise the
    /// Erewhon hairline at 1px. `borderColor` no longer carries selection meaning in the
    /// Erewhon branch — it remains the pixel-branch border. (Meaningful only in the
    /// Erewhon branch; the pixel branch ignores `isSelected`.)
    func adaptiveCard(
        borderColor: Color = DesignSystem.Colors.primary,
        fillColor: Color = DesignSystem.Colors.cardBackground,
        fillGradient: LinearGradient? = nil,
        cornerRadius: CGFloat = 16,
        isSelected: Bool = false
    ) -> some View {
        return Group {
            if SettingsManager.shared.isCleanUI {
                self
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Erewhon.cardRadius)
                            .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Erewhon.cardRadius)
                            .stroke(isSelected ? SettingsManager.shared.activeColors.primary : DesignSystem.Erewhon.line,
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Erewhon.cardRadius))
                    .shadow(color: DesignSystem.Erewhon.cardShadow.color,
                            radius: DesignSystem.Erewhon.cardShadow.radius,
                            x: 0, y: DesignSystem.Erewhon.cardShadow.y)
            } else {
                self.pixelCard(borderColor: borderColor, fillColor: fillColor, fillGradient: fillGradient)
            }
        }
    }

    /// Adaptive pill: PixelPillShape in pixel themes, Erewhon flat capsule otherwise
    /// (fill + hairline). Selection is caller-declared via `isSelected` (mirrors
    /// adaptiveCard); `borderColor` no longer carries selection meaning in the Erewhon
    /// branch, and the pixel branch ignores `isSelected`.
    func adaptivePill(
        borderColor: Color = DesignSystem.Colors.primary,
        fillColor: Color = DesignSystem.Colors.cardBackground,
        fillGradient: LinearGradient? = nil,
        isSelected: Bool = false
    ) -> some View {
        return Group {
            if SettingsManager.shared.isCleanUI {
                self
                    .background(
                        Capsule()
                            .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? SettingsManager.shared.activeColors.primary : DesignSystem.Erewhon.line,
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                    .clipShape(Capsule())
            } else {
                self.pixelPill(borderColor: borderColor, fillColor: fillColor, fillGradient: fillGradient)
            }
        }
    }
}

// MARK: - Adaptive Container Views

/// Adaptive card container. PixelCard in RPG, rounded card in Clean.
/// Selection (R6c): caller-declared via `isSelected`; `borderColor` no longer carries
/// selection meaning in the Erewhon branch (the pixel branch ignores `isSelected`).
struct AdaptiveCard<Content: View>: View {
    var borderColor: Color = DesignSystem.Colors.primary
    var fillColor: Color = DesignSystem.Colors.cardBackground
    var fillGradient: LinearGradient? = nil
    var cornerRadius: CGFloat = 16
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content

    private var isClean: Bool { SettingsManager.shared.isCleanUI }

    var body: some View {
        // Erewhon flat treatment mirrors the .adaptiveCard(...) modifier (radius, hairline,
        // shadow, caller-declared isSelected) so container-form cards match modifier-form cards.
        if isClean {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.Erewhon.cardRadius)
                    .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Erewhon.cardRadius)
                            .stroke(isSelected ? SettingsManager.shared.activeColors.primary : DesignSystem.Erewhon.line,
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                    .shadow(color: DesignSystem.Erewhon.cardShadow.color,
                            radius: DesignSystem.Erewhon.cardShadow.radius,
                            x: 0, y: DesignSystem.Erewhon.cardShadow.y)
                content()
            }
        } else {
            PixelCard(borderColor: borderColor, fillColor: fillColor, fillGradient: fillGradient) {
                content()
            }
        }
    }
}

/// Adaptive pill container. PixelPill in RPG, capsule in Clean.
/// Selection (R6c): caller-declared via `isSelected`; `borderColor` no longer carries
/// selection meaning in the Erewhon branch (the pixel branch ignores `isSelected`).
struct AdaptivePill<Content: View>: View {
    var borderColor: Color = DesignSystem.Colors.primary
    var fillColor: Color = DesignSystem.Colors.cardBackground
    var fillGradient: LinearGradient? = nil
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Erewhon flat capsule mirrors the .adaptivePill(...) modifier (fill + hairline).
        if SettingsManager.shared.isCleanUI {
            ZStack {
                Capsule()
                    .fill(fillGradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(fillColor))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? SettingsManager.shared.activeColors.primary : DesignSystem.Erewhon.line,
                                    lineWidth: isSelected ? 1.5 : 1)
                    )
                content()
            }
        } else {
            PixelPill(borderColor: borderColor, fillColor: fillColor, fillGradient: fillGradient) {
                content()
            }
        }
    }
}

// MARK: - Adaptive Shape Types

/// Adaptive Shape for .clipShape() and .overlay() usages.
struct AdaptiveCardShapeStyle: Shape {
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        SettingsManager.shared.isCleanUI
            ? RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
            : PixelCardShape().path(in: rect)
    }
}

struct AdaptivePillShapeStyle: Shape {
    func path(in rect: CGRect) -> Path {
        SettingsManager.shared.isCleanUI
            ? Capsule().path(in: rect)
            : PixelPillShape().path(in: rect)
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// Initialize Color from hex string
    /// - Parameter hex: Hex color string (e.g., "#10B981" or "10B981")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Initialize Color with light and dark mode variants
    /// - Parameters:
    ///   - light: Color for light mode
    ///   - dark: Color for dark mode
    init(light: Color, dark: Color) {
        self.init(UIColor(light: UIColor(light), dark: UIColor(dark)))
    }

    /// Darken or lighten a color by adjusting its brightness.
    /// Negative values darken, positive values lighten.
    func adjustedBrightness(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s), brightness: max(0, min(1, Double(b) + amount)), opacity: Double(a))
    }
}

extension UIColor {
    /// Initialize UIColor with light and dark mode variants
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return dark
            default:
                return light
            }
        }
    }
}

// MARK: - Preview Components Showcase

#Preview("Design System Showcase") {
    DesignSystemPreview()
}

/// Preview screen showing all components in both light and dark mode
struct DesignSystemPreview: View {

    @State private var progress: Double = 0.65
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {

                    // MARK: Buttons Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Buttons")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        AppButton(
                            title: "Primary Button",
                            style: .primary,
                            action: { print("Primary tapped") },
                            icon: "checkmark.circle.fill"
                        )

                        AppButton(
                            title: "Secondary Button",
                            style: .secondary,
                            action: { print("Secondary tapped") },
                            icon: "arrow.right.circle"
                        )

                        AppButton(
                            title: "Loading Button",
                            style: .primary,
                            action: { },
                            isLoading: true
                        )

                        AppButton(
                            title: "Disabled Button",
                            style: .primary,
                            action: { },
                            isDisabled: true
                        )
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    // MARK: Stat Cards Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Stat Cards")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DesignSystem.Spacing.md) {
                                StatCard(
                                    icon: "flame.fill",
                                    title: "Current Streak",
                                    value: "12 days",
                                    iconColor: DesignSystem.Colors.energy
                                )
                                .frame(width: 200)

                                StatCard(
                                    icon: "chart.line.uptrend.xyaxis",
                                    title: "Weight Lost",
                                    value: "8.5 lbs",
                                    iconColor: DesignSystem.Colors.primary,
                                    progress: 0.65,
                                    progressColor: DesignSystem.Colors.primary
                                )
                                .frame(width: 200)

                                StatCard(
                                    icon: "star.fill",
                                    title: "Total XP",
                                    value: "1,250",
                                    iconColor: DesignSystem.Colors.growth
                                )
                                .frame(width: 200)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                        }
                    }

                    // MARK: Progress Rings Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Progress Rings")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)

                        HStack(spacing: DesignSystem.Spacing.xl) {
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                ProgressRing(
                                    progress: 0.75,
                                    lineWidth: 12,
                                    size: 120,
                                    showPercentage: true
                                )

                                Text("Percentage")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            VStack(spacing: DesignSystem.Spacing.sm) {
                                ProgressRing(
                                    progress: 0.45,
                                    lineWidth: 12,
                                    size: 120,
                                    showPercentage: false,
                                    centerText: "1,450\nkcal"
                                )

                                Text("Custom Text")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // MARK: XP Badges Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("XP Badges")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        HStack(spacing: DesignSystem.Spacing.md) {
                            XPBadge(xp: 10, useGradient: true, size: .small)
                            XPBadge(xp: 25, useGradient: true, size: .medium)
                            XPBadge(xp: 50, useGradient: true, size: .large)
                        }

                        HStack(spacing: DesignSystem.Spacing.md) {
                            XPBadge(xp: 10, useGradient: false, size: .small)
                            XPBadge(xp: 25, useGradient: false, size: .medium)
                            XPBadge(xp: 50, useGradient: false, size: .large)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    // MARK: Typography Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Typography")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Large Title - 34pt Bold")
                                .font(.system(size: 34, weight: .bold))

                            Text("Title - 28pt Semibold")
                                .font(.system(size: 28, weight: .semibold))

                            Text("Title 2 - 22pt Semibold")
                                .font(.system(size: 22, weight: .semibold))

                            Text("Headline - 17pt Semibold")
                                .font(.system(size: 17, weight: .semibold))

                            Text("Body - 17pt Regular")
                                .font(.system(size: 17, weight: .regular))

                            Text("Callout - 16pt Regular")
                                .font(.system(size: 16, weight: .regular))

                            Text("Caption - 12pt Regular")
                                .font(.system(size: 12, weight: .regular))
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    // MARK: Color Palette Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Color Palette")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: DesignSystem.Spacing.md) {
                            ColorSwatch(name: "Primary", color: DesignSystem.Colors.primary)
                            ColorSwatch(name: "Secondary", color: DesignSystem.Colors.secondary)
                            ColorSwatch(name: "Energy", color: DesignSystem.Colors.energy)
                            ColorSwatch(name: "Growth", color: DesignSystem.Colors.growth)
                            ColorSwatch(name: "Warning", color: DesignSystem.Colors.warning)
                            ColorSwatch(name: "Danger", color: DesignSystem.Colors.danger)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    // MARK: Empty State Section
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Empty State")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.lg)

                        EmptyStateView(
                            icon: "fork.knife",
                            title: "No Meals Logged",
                            message: "Start tracking your meals to see your progress and earn XP!",
                            actionTitle: "Log First Meal",
                            action: { print("Log meal tapped") }
                        )
                        .frame(height: 400)
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Design System")
        }
    }
}

/// Color swatch component for preview
struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(color)
                .frame(height: 60)

            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}
