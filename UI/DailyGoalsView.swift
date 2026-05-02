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
    private var tc: ThemeColors { settings.activeTheme.colors }

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: DailyGoalsViewModel(coordinator: coordinator))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                tc.primaryBackground
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
                    .font(PixelFont.regular(17))
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
                .font(PixelFont.regular(16))
                .foregroundColor(tc.textSecondary)
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
                    iconColor: tc.macroBarCarbs,
                    placeholder: "2000",
                    text: $viewModel.calorieTargetString,
                    unit: "kcal",
                    helperText: "Total calories per day"
                )

                // Protein input
                goalInputField(
                    title: "Protein Target",
                    icon: "leaf.fill",
                    iconColor: tc.primary,
                    placeholder: "150",
                    text: $viewModel.proteinTargetString,
                    unit: "g",
                    helperText: "Protein grams per day"
                )

                // Carbs input
                goalInputField(
                    title: "Carbs Target",
                    icon: "bolt.fill",
                    iconColor: tc.macroBarFat,
                    placeholder: "200",
                    text: $viewModel.carbTargetString,
                    unit: "g",
                    helperText: "Carbohydrate grams per day"
                )

                // Fat input
                goalInputField(
                    title: "Fat Target",
                    icon: "drop.fill",
                    iconColor: tc.primary,
                    placeholder: "65",
                    text: $viewModel.fatTargetString,
                    unit: "g",
                    helperText: "Fat grams per day"
                )

                // Purity input
                goalInputField(
                    title: "Purity Target",
                    icon: "sparkles",
                    iconColor: tc.primaryDark,
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
                PixelCardShape()
                    .fill(DesignSystem.Colors.threeBandFrom(tc.primary))
                    .frame(width: DesignSystem.Sizes.thumbnailLarge, height: DesignSystem.Sizes.thumbnailLarge)
                    .overlay(PixelCardShape().stroke(tc.primary.adjustedBrightness(-0.2), lineWidth: 2))

                Image(systemName: "target")
                    .font(PixelFont.regular(40))
                    .foregroundColor(.white)
            }

            Text("Set Your Goals")
                .font(PixelFont.bold(24))
                .foregroundColor(tc.textPrimary)

            Text("Customize your daily nutrition targets")
                .font(PixelFont.regular(14))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// Error banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(PixelFont.bold(16))
                .foregroundColor(DesignSystem.Colors.danger)

            Text(message)
                .font(PixelFont.regular(14))
                .foregroundColor(DesignSystem.Colors.danger)

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .pixelCard(borderColor: DesignSystem.Colors.danger.opacity(0.4), fillColor: DesignSystem.Colors.danger.opacity(0.1))
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
                    PixelPillShape()
                        .fill(DesignSystem.Colors.threeBandFrom(iconColor))
                        .frame(width: 32, height: 32)
                        .overlay(PixelPillShape().stroke(iconColor.adjustedBrightness(-0.2), lineWidth: 2))

                    Image(systemName: icon)
                        .font(PixelFont.bold(14))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(PixelFont.bold(17))
                    .foregroundColor(tc.textPrimary)

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
                    .font(PixelFont.regular(16))
                    .foregroundColor(tc.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .pixelCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)

            // Helper text
            Text(helperText)
                .font(PixelFont.regular(12))
                .foregroundColor(tc.textTertiary)
                .padding(.leading, DesignSystem.Spacing.xs)
        }
    }

    /// Advanced nutrition goals section
    private var advancedNutritionGoalsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Section header
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(PixelFont.bold(18))
                    .foregroundColor(tc.primary)

                Text("Advanced Nutrition Goals")
                    .font(PixelFont.bold(18))
                    .foregroundColor(tc.textPrimary)

                Spacer()
            }
            .padding(.top, DesignSystem.Spacing.sm)

            Text("Optional targets for detailed tracking. Leave blank to skip.")
                .font(PixelFont.regular(12))
                .foregroundColor(tc.textTertiary)

            // Fiber (minimum target)
            optionalGoalInputField(
                title: "Fiber Target",
                icon: "leaf.fill",
                iconColor: tc.primary,
                placeholder: "25",
                text: $viewModel.fiberTargetString,
                unit: "g",
                helperText: "Aim to reach or exceed (minimum)"
            )

            // Sugar (maximum target)
            optionalGoalInputField(
                title: "Sugar Limit",
                icon: "cube.fill",
                iconColor: tc.macroBarFat,
                placeholder: "50",
                text: $viewModel.sugarTargetString,
                unit: "g",
                helperText: "Try to stay under (maximum)"
            )

            // Sodium (maximum target)
            optionalGoalInputField(
                title: "Sodium Limit",
                icon: "drop.fill",
                iconColor: tc.primary,
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
                iconColor: tc.macroBarCarbs,
                placeholder: "300",
                text: $viewModel.cholesterolTargetString,
                unit: "mg",
                helperText: "Try to stay under (maximum)"
            )

            // Potassium (minimum target)
            optionalGoalInputField(
                title: "Potassium Target",
                icon: "bolt.fill",
                iconColor: tc.primaryDark,
                placeholder: "4700",
                text: $viewModel.potassiumTargetString,
                unit: "mg",
                helperText: "Aim to reach or exceed (minimum)"
            )
        }
        .padding(DesignSystem.Spacing.md)
        .pixelCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
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
                    .font(PixelFont.bold(14))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(PixelFont.regular(16))
                    .foregroundColor(tc.textPrimary)

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
                        .font(PixelFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 25, alignment: .leading)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .pixelCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }

            // Helper text
            Text(helperText)
                .font(PixelFont.regular(10))
                .foregroundColor(tc.textTertiary)
                .padding(.leading, 28)
        }
    }

    /// Warning text about immediate changes
    private var warningText: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(PixelFont.regular(16))
                .foregroundColor(tc.macroBarFat)

            Text("Changes apply immediately and will affect today's progress")
                .font(PixelFont.regular(14))
                .foregroundColor(tc.macroBarFat)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelCard(borderColor: tc.macroBarFat.opacity(0.3), fillColor: tc.macroBarFat.opacity(0.1))
    }

    /// Action buttons
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Button {
                saveGoals()
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if viewModel.isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(PixelFont.bold(17))
                        Text("Save Goals")
                            .font(PixelFont.bold(17))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .pixelCard(
                    borderColor: tc.buttonBorder,
                    fillColor: .clear,
                    fillGradient: DesignSystem.Colors.threeBand(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.isFormValid || viewModel.isSaving)
            .opacity(!viewModel.isFormValid || viewModel.isSaving ? 0.5 : 1.0)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(PixelFont.regular(17))
                    .foregroundColor(tc.textSecondary)
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
                    .font(PixelFont.bold(18))
                    .foregroundColor(.white)

                Text("Goals updated!")
                    .font(PixelFont.bold(17))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .pixelPill(borderColor: tc.primary, fillColor: tc.primary)
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
