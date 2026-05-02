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
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style == .primary ? .white : DesignSystem.Colors.primary))
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(PixelFont.bold(17))
                    }

                    Text(title)
                        .font(PixelFont.bold(17))
                }
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundView)
            .overlay(
                PixelCardShape()
                    .stroke(style == .secondary ? DesignSystem.Colors.primary : Color(hex: "#047857"), lineWidth: 2)
            )
            .clipShape(PixelCardShape())
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .opacity(isDisabled ? 0.5 : 1.0)
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

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return DesignSystem.Colors.primary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
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
                        .font(PixelFont.bold(18))
                        .foregroundColor(iconColor)
                }

                Spacer()
            }

            // Title
            Text(title)
                .font(PixelFont.regular(14))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Large value display
            Text(value)
                .font(PixelFont.bold(28))
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
        .pixelCard(borderColor: DesignSystem.Colors.primary.opacity(0.25), fillColor: DesignSystem.Colors.cardBackground)
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
                    DesignSystem.Colors.border,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            // Progress ring (green gradient)
            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    DesignSystem.Colors.primaryGradient,
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
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if showPercentage {
                    Text("\(Int(normalizedProgress * 100))%")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
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
                .font(PixelFont.bold(size.fontSize - 2))

            Text("+\(xp) XP")
                .font(PixelFont.bold(size.fontSize))
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
        .clipShape(PixelPillShape())
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

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            // Large icon
            Image(systemName: icon)
                .font(PixelFont.regular(64))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.bottom, DesignSystem.Spacing.sm)

            // Clean typography hierarchy
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(PixelFont.bold(22))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(PixelFont.regular(16))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.primaryBackground)
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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Field label
            Text(label)
                .font(PixelFont.regular(14))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Input field + optional reveal toggle
            ZStack(alignment: .trailing) {
                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(isSecure ? .default : .emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                // Indent right edge when the reveal toggle is present to avoid overlap
                .padding(.leading, DesignSystem.Spacing.md)
                .padding(.trailing, isSecure ? 52 : DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.md)
                .frame(minHeight: 52)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(PixelCardShape())
                .overlay(
                    PixelCardShape()
                        .stroke(
                            errorMessage != nil
                                ? DesignSystem.Colors.danger
                                : DesignSystem.Colors.border,
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
                            .foregroundColor(DesignSystem.Colors.textTertiary)
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
                        .font(PixelFont.regular(12))
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
