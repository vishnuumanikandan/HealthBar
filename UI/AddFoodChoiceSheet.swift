//
//  AddFoodChoiceSheet.swift
//  HealthBar
//
//  Created by Claude on 3/27/26.
//

import SwiftUI

/// Bottom sheet presenting 3 options for adding food:
/// Food Database, Scan Barcode, or Scan Food (AI, BETA).
///
/// Presented when the user taps any + button in a meal section.
/// The `pendingMealType` on the viewModel is pre-set before showing this sheet.
struct AddFoodChoiceSheet: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom drag handle
                Capsule()
                    .fill(DesignSystem.Colors.border)
                    .frame(width: 40, height: 4)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                // Title row
                HStack {
                    Text("Add Food")
                        .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)

                // Three choice rows
                VStack(spacing: DesignSystem.Spacing.sm) {
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

                    // Scan Food (BETA)
                    choiceRow(
                        sfSymbol: "camera.aperture",
                        title: "Scan Food",
                        subtitle: "AI photo recognition",
                        betaBadge: true
                    ) {
                        dismiss()
                        viewModel.showToastMessage("Coming soon!")
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)

                Spacer()
            }
            .background(DesignSystem.Colors.cardBackground.ignoresSafeArea())
        }
        .presentationDetents([.height(320)])
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
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: sfSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    if betaBadge {
                        Text("BETA")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.warning)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
    }
}
