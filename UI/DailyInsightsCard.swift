//
//  DailyInsightsCard.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import SwiftUI

/// Data model for daily insights
struct DailyInsights {
    /// Number of meals logged today
    let mealCount: Int

    /// Whether protein goal was hit
    let proteinGoalHit: Bool

    /// Protein progress (0.0 to 1.0+)
    let proteinProgress: Double

    /// Difference from baseline purity (negative = better, positive = worse)
    /// Nil if no baseline data available
    let purityVsBaseline: Double?

    /// Name of today's day (e.g., "Monday")
    let dayName: String

    /// Generates insight message text
    var insightMessage: String {
        var parts: [String] = []

        // Meal count
        if mealCount == 0 {
            parts.append("No meals logged yet")
        } else if mealCount == 1 {
            parts.append("You logged 1 meal")
        } else {
            parts.append("You logged \(mealCount) meals")
        }

        // Protein status
        if proteinGoalHit {
            parts.append("hit protein")
        }

        // Purity trend
        if let purityDiff = purityVsBaseline {
            if purityDiff < -0.1 {
                let percent = Int(abs(purityDiff) * 100)
                parts.append("kept purity \(percent)% below your usual \(dayName)")
            } else if purityDiff > 0.1 {
                let percent = Int(purityDiff * 100)
                parts.append("purity \(percent)% above your usual \(dayName)")
            }
        }

        // Combine into sentence
        if parts.count == 1 {
            return parts[0] + "."
        } else if parts.count == 2 {
            return parts[0] + ", " + parts[1] + "."
        } else {
            return parts[0] + ", " + parts[1] + ", and " + parts[2] + ". Solid day."
        }
    }
}

/// Dismissible card showing daily insights on the home screen
///
/// Displays:
/// - Meal count today
/// - Whether protein goal hit
/// - Purity trend vs personal baseline
///
/// Can be dismissed (persists via @AppStorage with date key).
/// Reappears the next day.
struct DailyInsightsCard: View {

    /// The insights data to display
    let insights: DailyInsights

    /// Called when user dismisses the card
    let onDismiss: () -> Void

    /// Animation state
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Header with dismiss button
            HStack {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.energy)

                    Text("Today's Insights")
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    // Delay dismiss callback to allow animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .accessibilityLabel("Dismiss insights card")
            }

            // Insight message
            Text(insights.insightMessage)
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Quick stats row
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Meal count
                InsightStatPill(
                    icon: "fork.knife",
                    value: "\(insights.mealCount)",
                    label: "meals",
                    color: DesignSystem.Colors.primary
                )

                // Protein status
                InsightStatPill(
                    icon: insights.proteinGoalHit ? "checkmark.circle.fill" : "circle",
                    value: insights.proteinGoalHit ? "Hit" : "\(Int(insights.proteinProgress * 100))%",
                    label: "protein",
                    color: insights.proteinGoalHit ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary
                )

                // Purity trend (if available)
                if let purityDiff = insights.purityVsBaseline {
                    InsightStatPill(
                        icon: purityDiff <= 0 ? "arrow.down" : "arrow.up",
                        value: "\(abs(Int(purityDiff * 100)))%",
                        label: "vs usual",
                        color: purityDiff <= 0 ? DesignSystem.Colors.primary : DesignSystem.Colors.warning
                    )
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .strokeBorder(DesignSystem.Colors.energy.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's insights. \(insights.insightMessage)")
    }
}

/// Small stat pill for insights card
struct InsightStatPill: View {

    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Daily Insights Card") {
    VStack(spacing: DesignSystem.Spacing.lg) {
        DailyInsightsCard(
            insights: DailyInsights(
                mealCount: 3,
                proteinGoalHit: true,
                proteinProgress: 1.1,
                purityVsBaseline: -0.15,
                dayName: "Monday"
            ),
            onDismiss: {}
        )

        DailyInsightsCard(
            insights: DailyInsights(
                mealCount: 1,
                proteinGoalHit: false,
                proteinProgress: 0.45,
                purityVsBaseline: nil,
                dayName: "Tuesday"
            ),
            onDismiss: {}
        )
    }
    .padding()
    .background(DesignSystem.Colors.primaryBackground)
}
