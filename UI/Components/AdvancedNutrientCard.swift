//
//  AdvancedNutrientCard.swift
//  HealthBar
//
//  Created by Claude on 1/27/26.
//

import SwiftUI

/// Mini card for displaying advanced nutrition values
///
/// Smaller than main macro cards, designed to show optional tracked nutrients
/// like fiber, sugar, sodium, etc. Includes progress bar if goal is set.
struct AdvancedNutrientCard: View {

    // MARK: - Properties

    let icon: String
    let title: String
    let currentValue: Double
    let targetValue: Double?
    let unit: String
    let iconColor: Color

    /// Whether this nutrient has a maximum (stay under) or minimum (reach) target
    var isMaximumTarget: Bool = true

    // MARK: - Computed Properties

    /// Progress percentage (0.0 to 1.0)
    private var progress: Double {
        guard let target = targetValue, target > 0 else { return 0 }
        return currentValue / target
    }

    /// Formatted current value text
    private var currentValueText: String {
        if currentValue >= 1000 {
            return String(format: "%.1fk", currentValue / 1000)
        } else if currentValue == Double(Int(currentValue)) {
            return "\(Int(currentValue))"
        } else {
            return String(format: "%.1f", currentValue)
        }
    }

    /// Formatted target value text
    private var targetValueText: String {
        guard let target = targetValue else { return "-" }
        if target >= 1000 {
            return String(format: "%.1fk", target / 1000)
        } else if target == Double(Int(target)) {
            return "\(Int(target))"
        } else {
            return String(format: "%.1f", target)
        }
    }

    /// VoiceOver label for accessibility
    private var accessibilityLabel: String {
        let unitName = unit == "g" ? "grams" : "milligrams"
        if let target = targetValue {
            return "\(title): \(currentValueText) \(unitName) out of \(targetValueText) \(unitName) goal"
        } else {
            return "\(title): \(currentValueText) \(unitName), no goal set"
        }
    }

    /// Progress bar color based on whether target is min or max
    private var progressColor: Color {
        if isMaximumTarget {
            // For max targets (sugar, sodium, etc.), green when under, red when over
            return progress > 1.0 ? DesignSystem.Colors.danger : DesignSystem.Colors.primary
        } else {
            // For min targets (fiber, potassium), green when reached
            return progress >= 1.0 ? DesignSystem.Colors.primary : iconColor
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Icon and title row
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()
            }

            // Value display
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currentValueText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Text("/")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Text(targetValueText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                if targetValue != nil {
                    Text(unit)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }

            // Progress bar (only if target is set)
            if targetValue != nil {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DesignSystem.Colors.border)
                            .frame(height: 3)

                        // Progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1.2), height: 3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Advanced Nutrients Grid

/// Responsive grid for displaying advanced nutrient mini cards
struct AdvancedNutrientsGrid: View {

    let entries: [FoodEntry]
    let goal: DailyGoal?

    // MARK: - Computed Totals

    private var totalFiber: Double {
        entries.compactMap { $0.fiber }.reduce(0, +)
    }

    private var totalSugar: Double {
        entries.compactMap { $0.sugar }.reduce(0, +)
    }

    private var totalSodium: Double {
        entries.compactMap { $0.sodium }.reduce(0, +)
    }

    private var totalSaturatedFat: Double {
        entries.compactMap { $0.saturatedFat }.reduce(0, +)
    }

    private var totalCholesterol: Double {
        entries.compactMap { $0.cholesterol }.reduce(0, +)
    }

    private var totalPotassium: Double {
        entries.compactMap { $0.potassium }.reduce(0, +)
    }

    /// Whether any advanced nutrition has been logged
    private var hasAdvancedNutrition: Bool {
        totalFiber > 0 || totalSugar > 0 || totalSodium > 0 ||
        totalSaturatedFat > 0 || totalCholesterol > 0 || totalPotassium > 0
    }

    /// Nutrients to display (only those with values > 0)
    private var nutrientsToShow: [NutrientData] {
        var nutrients: [NutrientData] = []

        if totalFiber > 0 {
            nutrients.append(NutrientData(
                icon: "leaf.fill",
                title: "Fiber",
                current: totalFiber,
                target: goal?.fiberTarget,
                unit: "g",
                color: DesignSystem.Colors.primary,
                isMaxTarget: false
            ))
        }

        if totalSugar > 0 {
            nutrients.append(NutrientData(
                icon: "cube.fill",
                title: "Sugar",
                current: totalSugar,
                target: goal?.sugarTarget,
                unit: "g",
                color: DesignSystem.Colors.warning,
                isMaxTarget: true
            ))
        }

        if totalSodium > 0 {
            nutrients.append(NutrientData(
                icon: "drop.fill",
                title: "Sodium",
                current: totalSodium,
                target: goal?.sodiumTarget,
                unit: "mg",
                color: DesignSystem.Colors.secondary,
                isMaxTarget: true
            ))
        }

        if totalSaturatedFat > 0 {
            nutrients.append(NutrientData(
                icon: "heart.fill",
                title: "Sat. Fat",
                current: totalSaturatedFat,
                target: goal?.saturatedFatTarget,
                unit: "g",
                color: DesignSystem.Colors.danger,
                isMaxTarget: true
            ))
        }

        if totalCholesterol > 0 {
            nutrients.append(NutrientData(
                icon: "heart.circle.fill",
                title: "Cholesterol",
                current: totalCholesterol,
                target: goal?.cholesterolTarget,
                unit: "mg",
                color: DesignSystem.Colors.energy,
                isMaxTarget: true
            ))
        }

        if totalPotassium > 0 {
            nutrients.append(NutrientData(
                icon: "bolt.fill",
                title: "Potassium",
                current: totalPotassium,
                target: goal?.potassiumTarget,
                unit: "mg",
                color: DesignSystem.Colors.growth,
                isMaxTarget: false
            ))
        }

        return nutrients
    }

    // MARK: - Body

    var body: some View {
        if hasAdvancedNutrition {
            let columns = adaptiveColumns

            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.sm) {
                ForEach(nutrientsToShow) { nutrient in
                    AdvancedNutrientCard(
                        icon: nutrient.icon,
                        title: nutrient.title,
                        currentValue: nutrient.current,
                        targetValue: nutrient.target,
                        unit: nutrient.unit,
                        iconColor: nutrient.color,
                        isMaximumTarget: nutrient.isMaxTarget
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nutrientsToShow.count)
        }
    }

    /// Adaptive grid columns based on screen size
    private var adaptiveColumns: [GridItem] {
        // Use 2 columns for smaller screens, 3 for larger
        [
            GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
            GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
            GridItem(.flexible(), spacing: DesignSystem.Spacing.sm)
        ]
    }
}

// MARK: - Supporting Types

private struct NutrientData: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let current: Double
    let target: Double?
    let unit: String
    let color: Color
    let isMaxTarget: Bool
}

// MARK: - Preview

#Preview("Advanced Nutrient Card") {
    VStack(spacing: DesignSystem.Spacing.md) {
        HStack(spacing: DesignSystem.Spacing.sm) {
            AdvancedNutrientCard(
                icon: "leaf.fill",
                title: "Fiber",
                currentValue: 15,
                targetValue: 25,
                unit: "g",
                iconColor: DesignSystem.Colors.primary,
                isMaximumTarget: false
            )

            AdvancedNutrientCard(
                icon: "cube.fill",
                title: "Sugar",
                currentValue: 35,
                targetValue: 50,
                unit: "g",
                iconColor: DesignSystem.Colors.warning
            )

            AdvancedNutrientCard(
                icon: "drop.fill",
                title: "Sodium",
                currentValue: 1500,
                targetValue: 2300,
                unit: "mg",
                iconColor: DesignSystem.Colors.secondary
            )
        }

        HStack(spacing: DesignSystem.Spacing.sm) {
            AdvancedNutrientCard(
                icon: "heart.fill",
                title: "Sat. Fat",
                currentValue: 8,
                targetValue: nil,
                unit: "g",
                iconColor: DesignSystem.Colors.danger
            )

            AdvancedNutrientCard(
                icon: "bolt.fill",
                title: "Potassium",
                currentValue: 3200,
                targetValue: 4700,
                unit: "mg",
                iconColor: DesignSystem.Colors.growth,
                isMaximumTarget: false
            )
        }
    }
    .padding()
    .background(DesignSystem.Colors.primaryBackground)
}
