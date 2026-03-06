//
//  MealTypePill.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import SwiftUI

/// Small capsule-shaped pill showing meal type (breakfast/lunch/dinner/snack)
///
/// Displays an icon and label for the meal type with subtle background tint.
/// Non-interactive - purely for display purposes.
struct MealTypePill: View {

    /// The meal type to display
    let mealType: MealType

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: mealType.icon)
                .font(.system(size: 10, weight: .semibold))

            Text(mealType.displayName)
                .font(.system(size: DesignSystem.FontSizes.caption2, weight: .medium))
        }
        .foregroundColor(mealType.color)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(mealType.color.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel("Meal type: \(mealType.displayName)")
    }
}

// MARK: - Preview

#Preview("Meal Type Pills") {
    VStack(spacing: DesignSystem.Spacing.md) {
        ForEach(MealType.allCases, id: \.self) { mealType in
            MealTypePill(mealType: mealType)
        }
    }
    .padding()
    .background(DesignSystem.Colors.primaryBackground)
}
