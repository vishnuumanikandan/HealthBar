//
//  AddFoodChoiceSheet.swift
//  HealthBar
//
//  Created by Claude on 3/27/26.
//

import SwiftUI

/// Bottom sheet presenting 3 options for adding food:
/// Scan Food (AI), Food Database, or Scan Barcode.
///
/// Presented when the user taps any + button in a meal section.
/// The `pendingMealType` on the viewModel is pre-set before showing this sheet.
struct AddFoodChoiceSheet: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom drag handle
                AdaptivePillShapeStyle()
                    .fill(tc.primary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                // Title row
                HStack {
                    Text("Add Food")
                        .font(AppFont.display(22))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)

                // Choice rows
                VStack(spacing: DesignSystem.Spacing.sm) {
                    // Scan Food (AI text + optional photo recognition)
                    choiceRow(
                        sfSymbol: "sparkles",
                        title: "Scan Food",
                        subtitle: "Describe or snap a photo, AI does the rest",
                        betaBadge: true
                    ) {
                        dismiss()
                        viewModel.openDescribeMeal()
                    }

                    // Food Database
                    choiceRow(
                        sfSymbol: "fork.knife.circle.fill",
                        title: "Food Database",
                        subtitle: "Search thousands of foods",
                        betaBadge: false
                    ) {
                        dismiss()
                        viewModel.showingFoodDatabase = true
                    }

                    // Scan Barcode — navigates to BarcodeOptionsView
                    NavigationLink {
                        BarcodeOptionsView(
                            viewModel: viewModel,
                            onDismissAll: { dismiss() }
                        )
                    } label: {
                        choiceRowLabel(
                            sfSymbol: "barcode.viewfinder",
                            title: "Scan Barcode",
                            subtitle: "Auto-fill from product label",
                            betaBadge: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)

                Spacer()
            }
            .background(tc.cardBackground.ignoresSafeArea())
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.CornerRadius.xl)
    }

    // MARK: - Row Helpers

    private func choiceRow(
        sfSymbol: String,
        title: String,
        subtitle: String,
        betaBadge: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            choiceRowLabel(
                sfSymbol: sfSymbol,
                title: title,
                subtitle: subtitle,
                betaBadge: betaBadge
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func choiceRowLabel(
        sfSymbol: String,
        title: String,
        subtitle: String,
        betaBadge: Bool
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Icon box
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: sfSymbol)
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.primary)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    if betaBadge {
                        Text("BETA")
                            .font(AppFont.bold(9))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tc.macroBarFat)
                            .clipShape(AdaptivePillShapeStyle())
                    }
                }
                Text(subtitle)
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(AppFont.bold(14))
                .foregroundColor(tc.textTertiary)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.primaryBackground)
    }
}
