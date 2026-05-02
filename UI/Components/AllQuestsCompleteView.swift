//
//  AllQuestsCompleteView.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

/// View displayed when all 3 daily quests are completed
///
/// Features:
/// - Celebratory message
/// - Total XP earned from quests today
/// - Persists until midnight when quests reset
struct AllQuestsCompleteView: View {

    // MARK: - Properties

    private var tc: ThemeColors { SettingsManager.shared.activeTheme.colors }

    /// Total XP earned from quests today
    let totalXPFromQuests: Int

    /// Animation state
    @State private var isAnimating = false
    @State private var emojiScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Celebration emoji
            Text("🎉")
                .font(PixelFont.regular(64))
                .scaleEffect(emojiScale)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: emojiScale)

            // Title
            Text("Daily Quests Complete!")
                .font(PixelFont.bold(DesignSystem.FontSizes.title2))
                .foregroundColor(tc.textPrimary)
                .opacity(textOpacity)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: textOpacity)

            // Subtitle
            Text("New quests available tomorrow")
                .font(PixelFont.regular(DesignSystem.FontSizes.callout))
                .foregroundColor(tc.textSecondary)
                .opacity(textOpacity)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: textOpacity)

            // XP summary (optional)
            if totalXPFromQuests > 0 {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "star.fill")
                        .font(PixelFont.bold(16))
                        .foregroundColor(tc.macroBarCarbs)

                    Text("+\(totalXPFromQuests) XP from quests")
                        .font(PixelFont.bold(DesignSystem.FontSizes.footnote))
                        .foregroundColor(tc.macroBarCarbs)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(tc.macroBarCarbs.opacity(0.15))
                .clipShape(Capsule())
                .opacity(textOpacity)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: textOpacity)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(tc.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
        .onAppear {
            // Trigger animations
            emojiScale = 1.0
            textOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview("All Quests Complete") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        VStack {
            AllQuestsCompleteView(totalXPFromQuests: 130)
                .padding()

            Spacer()
        }
    }
}

#Preview("All Quests Complete - No XP") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        VStack {
            AllQuestsCompleteView(totalXPFromQuests: 0)
                .padding()

            Spacer()
        }
    }
}
