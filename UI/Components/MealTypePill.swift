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

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: mealType.icon)
                .font(AppFont.bold(10))

            Text(mealType.displayName)
                .font(AppFont.regular(11))
        }
        .foregroundColor(mealType.color)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .adaptivePill(borderColor: mealType.color.opacity(0.3), fillColor: mealType.color.opacity(0.15))
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
