//
//  PurityScoreInfoSheet.swift
//  HealthBar
//
//  Created by Claude on 1/27/26.
//

import SwiftUI

/// Educational sheet explaining what the Purity Score means
///
/// Displays in half-height sheet style with tap-outside-to-dismiss behavior.
/// Explains Nova group scoring, nutrition grades, and how the toxin score is calculated.
struct PurityScoreInfoSheet: View {

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                // Header
                headerSection

                // What is Purity Score
                whatIsPurityScoreSection

                // How it's calculated
                howCalculatedSection

                // Nova Groups explanation
                novaGroupsSection

                // Tips for improving
                tipsSection

                // Bottom padding for safe area
                Spacer()
                    .frame(height: DesignSystem.Spacing.xl)
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    /// Header with icon and title
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Purity Score")
                .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Understanding food processing levels")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// What is the Purity Score section
    private var whatIsPurityScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader(icon: "questionmark.circle.fill", title: "What is it?")

            Text("The Purity Score measures how processed your food is on a scale of 0-100. A lower score means cleaner, less processed food.")
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Score ranges
            VStack(spacing: DesignSystem.Spacing.sm) {
                scoreRangeRow(range: "0-20", label: "Clean", description: "Unprocessed whole foods", color: DesignSystem.Colors.primary)
                scoreRangeRow(range: "21-40", label: "Good", description: "Minimally processed", color: DesignSystem.Colors.growth)
                scoreRangeRow(range: "41-60", label: "Moderate", description: "Processed foods", color: DesignSystem.Colors.warning)
                scoreRangeRow(range: "61-80", label: "High", description: "Heavily processed", color: DesignSystem.Colors.energy)
                scoreRangeRow(range: "81-100", label: "Very High", description: "Ultra-processed", color: DesignSystem.Colors.danger)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    /// How the score is calculated section
    private var howCalculatedSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader(icon: "function", title: "How it's calculated")

            Text("When you scan a barcode, the Purity Score is automatically calculated using:")
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                factorRow(icon: "1.circle.fill", title: "NOVA Group", description: "Food processing classification (most important)")
                factorRow(icon: "2.circle.fill", title: "Nutrition Grade", description: "Overall nutritional quality (A-E)")
                factorRow(icon: "3.circle.fill", title: "Additives Count", description: "Number of food additives")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    /// Nova Groups explanation section
    private var novaGroupsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader(icon: "chart.bar.fill", title: "NOVA Food Groups")

            Text("NOVA is a scientific food classification system based on processing level:")
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DesignSystem.Spacing.sm) {
                novaGroupRow(
                    group: "1",
                    title: "Unprocessed",
                    examples: "Fresh fruits, vegetables, eggs, meat, fish",
                    color: DesignSystem.Colors.primary
                )
                novaGroupRow(
                    group: "2",
                    title: "Culinary Ingredients",
                    examples: "Oils, butter, sugar, salt, flour",
                    color: DesignSystem.Colors.growth
                )
                novaGroupRow(
                    group: "3",
                    title: "Processed",
                    examples: "Canned vegetables, cheese, bread",
                    color: DesignSystem.Colors.warning
                )
                novaGroupRow(
                    group: "4",
                    title: "Ultra-Processed",
                    examples: "Soft drinks, chips, instant meals, candy",
                    color: DesignSystem.Colors.danger
                )
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    /// Tips for improving section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader(icon: "lightbulb.fill", title: "Tips for a Lower Score")

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                tipRow(icon: "leaf.fill", tip: "Choose whole foods like fruits, vegetables, and unprocessed meats")
                tipRow(icon: "cart.fill", tip: "Shop the perimeter of the grocery store")
                tipRow(icon: "book.fill", tip: "Read ingredient lists — fewer ingredients is usually better")
                tipRow(icon: "house.fill", tip: "Cook more meals at home from scratch")
                tipRow(icon: "xmark.circle.fill", tip: "Avoid products with ingredients you can't pronounce")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    // MARK: - Helper Views

    /// Section header with icon
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)

            Text(title)
                .font(.system(size: DesignSystem.FontSizes.title3, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }

    /// Score range row
    private func scoreRangeRow(range: String, label: String, description: String, color: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(range)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
        }
    }

    /// Factor row for calculation explanation
    private func factorRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    /// Nova group row
    private func novaGroupRow(group: String, title: String, examples: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Text(group)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(examples)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    /// Tip row
    private func tipRow(icon: String, tip: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 20)

            Text(tip)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview("Purity Score Info Sheet") {
    Text("Tap to show sheet")
        .sheet(isPresented: .constant(true)) {
            PurityScoreInfoSheet()
        }
}
