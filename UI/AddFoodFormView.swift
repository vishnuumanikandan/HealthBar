//
//  AddFoodFormView.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import SwiftUI

/// Modal form for adding a new food entry
///
/// Features:
/// - Text field for food name
/// - Number inputs for calories and macros
/// - Toxin score slider (0-100)
/// - Form validation
/// - Save and Cancel buttons
struct AddFoodFormView: View {

    // MARK: - Properties

    /// Reference to the FoodLogViewModel
    @Bindable var viewModel: FoodLogViewModel

    /// Dismiss action for the sheet
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    headerSection

                    // Food name input
                    inputSection(
                        title: "Food Name",
                        icon: "fork.knife",
                        placeholder: "e.g., Grilled Chicken Salad",
                        text: $viewModel.formFoodName,
                        errorMessage: viewModel.formValidationErrors["foodName"]
                    )

                    // Nutrition inputs
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Text("Nutrition Info")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Calories
                        numberInputField(
                            title: "Calories",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.energy,
                            placeholder: "0",
                            text: $viewModel.formCalories,
                            unit: "cal",
                            errorMessage: viewModel.formValidationErrors["calories"]
                        )

                        // Protein
                        numberInputField(
                            title: "Protein",
                            icon: "leaf.fill",
                            iconColor: DesignSystem.Colors.primary,
                            placeholder: "0",
                            text: $viewModel.formProtein,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["protein"]
                        )

                        // Carbs
                        numberInputField(
                            title: "Carbs",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.warning,
                            placeholder: "0",
                            text: $viewModel.formCarbs,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["carbs"]
                        )

                        // Fat
                        numberInputField(
                            title: "Fat",
                            icon: "drop.fill",
                            iconColor: DesignSystem.Colors.secondary,
                            placeholder: "0",
                            text: $viewModel.formFat,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["fat"]
                        )
                    }

                    // Toxin score slider
                    toxinScoreSection

                    // Action buttons
                    actionButtons
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    /// Header section with icon and description
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: DesignSystem.Sizes.thumbnailLarge, height: DesignSystem.Sizes.thumbnailLarge)

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Log Your Meal")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Enter the nutritional information for your meal")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// Generic input section with optional error message
    private func inputSection(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                if let errorMessage = errorMessage {
                    Text("• \(errorMessage)")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.danger)
                }
            }

            TextField(placeholder, text: text)
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(errorMessage != nil ? DesignSystem.Colors.danger : DesignSystem.Colors.border, lineWidth: 1)
                )
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    viewModel.validateField("foodName")
                }
        }
    }

    /// Number input field with icon, unit, and optional error message
    private func numberInputField(
        title: String,
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        unit: String,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Title
                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Input field
                HStack(spacing: DesignSystem.Spacing.xs) {
                    TextField(placeholder, text: text)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)

                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .stroke(errorMessage != nil ? DesignSystem.Colors.danger : DesignSystem.Colors.border, lineWidth: 1)
                )
            }

            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
                    .padding(.leading, DesignSystem.Sizes.iconCircle + DesignSystem.Spacing.md)
            }
        }
        .onChange(of: text.wrappedValue) { oldValue, newValue in
            // Validate the specific field
            let fieldName = title.lowercased()
            viewModel.validateField(fieldName)
        }
    }

    /// Toxin score slider section
    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Toxin Score")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Lower is better (0-100)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Text("\(Int(viewModel.formToxinScore))")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(toxinScoreColor)
            }

            // Slider
            Slider(value: $viewModel.formToxinScore, in: 0...100, step: 1)
                .tint(toxinScoreColor)

            // Labels
            HStack {
                Text("Clean")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                Text("Processed")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    /// Action buttons (Save and Cancel)
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            AppButton(
                title: "Save Meal",
                style: .primary,
                action: saveFood,
                isLoading: viewModel.isSubmittingForm,
                isDisabled: viewModel.isSubmittingForm,
                icon: "checkmark.circle.fill"
            )

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.top, DesignSystem.Spacing.md)
    }

    // MARK: - Computed Properties

    /// Color for toxin score (green to red gradient)
    private var toxinScoreColor: Color {
        if viewModel.formToxinScore < 30 {
            return DesignSystem.Colors.primary
        } else if viewModel.formToxinScore < 60 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    // MARK: - Actions

    /// Validates and saves the food entry
    private func saveFood() {
        Task {
            await viewModel.submitForm()

            // Dismiss the sheet if successful (no error)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview("Add Food Form") {
    // Create mock view model
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let coordinator = AppCoordinator(modelContext: context)
    let viewModel = FoodLogViewModel(coordinator: coordinator)

    return AddFoodFormView(viewModel: viewModel)
}
