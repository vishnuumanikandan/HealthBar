//
//  DailyGoalsView.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import SwiftUI
import SwiftData

/// Screen for editing daily nutrition goals
///
/// Features:
/// - Editable fields for calories, protein, carbs, fat, purity
/// - Pre-filled with current values
/// - Helper text explaining changes apply immediately
/// - Save and Cancel buttons
struct DailyGoalsView: View {

    // MARK: - Properties

    @State private var viewModel: DailyGoalsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: DailyGoalsViewModel(coordinator: coordinator))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                DesignSystem.Colors.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else {
                    contentView
                }

                // Success toast overlay
                if viewModel.showSuccessToast {
                    successToast
                }
            }
            .navigationTitle("Daily Goals")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadCurrentGoals()
            }
        }
    }

    // MARK: - Subviews

    /// Loading indicator
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading goals...")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// Main content view
    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                headerSection

                // Error message
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                // Calorie input
                goalInputField(
                    title: "Daily Calorie Target",
                    icon: "flame.fill",
                    iconColor: DesignSystem.Colors.energy,
                    placeholder: "2000",
                    text: $viewModel.calorieTargetString,
                    unit: "kcal",
                    helperText: "Total calories per day"
                )

                // Protein input
                goalInputField(
                    title: "Protein Target",
                    icon: "leaf.fill",
                    iconColor: DesignSystem.Colors.primary,
                    placeholder: "150",
                    text: $viewModel.proteinTargetString,
                    unit: "g",
                    helperText: "Protein grams per day"
                )

                // Carbs input
                goalInputField(
                    title: "Carbs Target",
                    icon: "bolt.fill",
                    iconColor: DesignSystem.Colors.warning,
                    placeholder: "200",
                    text: $viewModel.carbTargetString,
                    unit: "g",
                    helperText: "Carbohydrate grams per day"
                )

                // Fat input
                goalInputField(
                    title: "Fat Target",
                    icon: "drop.fill",
                    iconColor: DesignSystem.Colors.secondary,
                    placeholder: "65",
                    text: $viewModel.fatTargetString,
                    unit: "g",
                    helperText: "Fat grams per day"
                )

                // Purity input
                goalInputField(
                    title: "Purity Target",
                    icon: "sparkles",
                    iconColor: DesignSystem.Colors.growth,
                    placeholder: "50",
                    text: $viewModel.purityTargetString,
                    unit: "score",
                    helperText: "Lower toxin score = cleaner eating (0-100)"
                )

                // Advanced Nutrition Goals (when enabled)
                if settings.trackAdvancedNutrition {
                    advancedNutritionGoalsSection
                }

                // Warning text
                warningText

                // Save button
                actionButtons
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    /// Header section
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: DesignSystem.Sizes.thumbnailLarge, height: DesignSystem.Sizes.thumbnailLarge)

                Image(systemName: "target")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Set Your Goals")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Customize your daily nutrition targets")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// Error banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.danger)

            Text(message)
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                .foregroundColor(DesignSystem.Colors.danger)

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.danger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    /// Goal input field component
    private func goalInputField(
        title: String,
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        unit: String,
        helperText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Title row
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()
            }

            // Input field
            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField(placeholder, text: text)
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)

                Text(unit)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
            )

            // Helper text
            Text(helperText)
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.leading, DesignSystem.Spacing.xs)
        }
    }

    /// Advanced nutrition goals section
    private var advancedNutritionGoalsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Section header
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.secondary)

                Text("Advanced Nutrition Goals")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()
            }
            .padding(.top, DesignSystem.Spacing.sm)

            Text("Optional targets for detailed tracking. Leave blank to skip.")
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            // Fiber (minimum target)
            optionalGoalInputField(
                title: "Fiber Target",
                icon: "leaf.fill",
                iconColor: DesignSystem.Colors.primary,
                placeholder: "25",
                text: $viewModel.fiberTargetString,
                unit: "g",
                helperText: "Aim to reach or exceed (minimum)"
            )

            // Sugar (maximum target)
            optionalGoalInputField(
                title: "Sugar Limit",
                icon: "cube.fill",
                iconColor: DesignSystem.Colors.warning,
                placeholder: "50",
                text: $viewModel.sugarTargetString,
                unit: "g",
                helperText: "Try to stay under (maximum)"
            )

            // Sodium (maximum target)
            optionalGoalInputField(
                title: "Sodium Limit",
                icon: "drop.fill",
                iconColor: DesignSystem.Colors.secondary,
                placeholder: "2300",
                text: $viewModel.sodiumTargetString,
                unit: "mg",
                helperText: "Try to stay under (maximum)"
            )

            // Saturated Fat (maximum target)
            optionalGoalInputField(
                title: "Saturated Fat Limit",
                icon: "heart.fill",
                iconColor: DesignSystem.Colors.danger,
                placeholder: "20",
                text: $viewModel.saturatedFatTargetString,
                unit: "g",
                helperText: "Try to stay under (maximum)"
            )

            // Cholesterol (maximum target)
            optionalGoalInputField(
                title: "Cholesterol Limit",
                icon: "heart.circle.fill",
                iconColor: DesignSystem.Colors.energy,
                placeholder: "300",
                text: $viewModel.cholesterolTargetString,
                unit: "mg",
                helperText: "Try to stay under (maximum)"
            )

            // Potassium (minimum target)
            optionalGoalInputField(
                title: "Potassium Target",
                icon: "bolt.fill",
                iconColor: DesignSystem.Colors.growth,
                placeholder: "4700",
                text: $viewModel.potassiumTargetString,
                unit: "mg",
                helperText: "Aim to reach or exceed (minimum)"
            )
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
    }

    /// Optional goal input field (smaller, for advanced nutrients)
    private func optionalGoalInputField(
        title: String,
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        unit: String,
        helperText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Title row
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                // Input field
                HStack(spacing: DesignSystem.Spacing.xs) {
                    TextField(placeholder, text: text)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)

                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 25, alignment: .leading)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                )
            }

            // Helper text
            Text(helperText)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.leading, 28)
        }
    }

    /// Warning text about immediate changes
    private var warningText: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.warning)

            Text("Changes apply immediately and will affect today's progress")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                .foregroundColor(DesignSystem.Colors.warning)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    /// Action buttons
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            AppButton(
                title: "Save Goals",
                style: .primary,
                action: saveGoals,
                isLoading: viewModel.isSaving,
                isDisabled: !viewModel.isFormValid || viewModel.isSaving,
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

    /// Success toast
    private var successToast: some View {
        VStack {
            Spacer()

            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text("Goals updated!")
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .clipShape(Capsule())
            .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 8, y: 4)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showSuccessToast)
        .allowsHitTesting(false)
        .onAppear {
            // Auto-dismiss after showing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    /// Saves goals and dismisses on success
    private func saveGoals() {
        Task {
            let success = await viewModel.saveGoals()
            if success {
                // Toast will auto-dismiss the view
            }
        }
    }
}

// MARK: - Preview

#Preview("Daily Goals") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    // Add sample goal
    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )
    context.insert(sampleGoal)

    let coordinator = AppCoordinator(modelContext: context)

    return DailyGoalsView(coordinator: coordinator)
}
