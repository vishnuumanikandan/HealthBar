//
//  OnboardingView.swift
//  HealthBar
//
//  Created by Claude on 3/31/26.
//

import SwiftUI

/// 14-step AI-powered onboarding questionnaire.
///
/// Presented as a fullScreenCover when no completed UserProfile exists for the
/// current user. Also accessible from Profile tab as "Edit Health Profile".
struct OnboardingView: View {

    // MARK: - State

    @State private var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss

    // Tracks transition direction so slide goes left/right correctly
    @State private var stepHistory: [Int] = []

    // Controls the step-jump sheet (edit mode only)
    @State private var showStepPicker: Bool = false

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        existingProfile: UserProfile? = nil
    ) {
        self._viewModel = State(
            initialValue: OnboardingViewModel(
                coordinator: coordinator,
                authService: authService,
                existingProfile: existingProfile
            )
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Close button row — only in edit mode so new users can't bail mid-onboarding
            if viewModel.isEditMode {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .accessibilityLabel("Close profile editor")
                    .padding(.trailing, DesignSystem.Spacing.md)
                    .padding(.top, DesignSystem.Spacing.md)
                }
            }

            // Progress bar (hidden on Welcome step)
            // In edit mode, a jump-to-step button sits at the trailing end of the bar.
            if viewModel.currentStep > 0 {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    progressBar

                    if viewModel.isEditMode && viewModel.currentStep <= 11 {
                        Button {
                            showStepPicker = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(7)
                                .background(DesignSystem.Colors.cardBackground)
                                .clipShape(AdaptivePillShapeStyle())
                        }
                        .accessibilityLabel("Jump to a different step")
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }

            // Step content with slide animation
            ZStack {
                stepContent(viewModel.currentStep)
                    .id(viewModel.currentStep)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingForward ? .trailing : .leading),
                        removal: .move(edge: goingForward ? .leading : .trailing)
                    ))
            }
            .animation(
                .spring(response: 0.35, dampingFraction: 0.85),
                value: viewModel.currentStep
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons (hidden on step 0, 12, 13)
            if viewModel.currentStep > 0
                && viewModel.currentStep < 12 {
                navigationButtons
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .onChange(of: viewModel.authService.currentUserEmail) { _, _ in
            viewModel.resetForNewUser()
        }
        .sheet(isPresented: $showStepPicker) {
            StepPickerSheet(
                currentStep: viewModel.currentStep,
                onSelect: { step in
                    stepHistory.append(viewModel.currentStep)
                    viewModel.jumpToStep(step)
                    showStepPicker = false
                }
            )
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignSystem.Colors.border)
                    .frame(height: 6)

                Capsule()
                    .fill(DesignSystem.Colors.primary)
                    .frame(
                        width: geo.size.width * progressFraction,
                        height: 6
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.currentStep)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Step \(viewModel.currentStep) of 13")
    }

    private var progressFraction: CGFloat {
        guard viewModel.currentStep > 0 else { return 0 }
        return CGFloat(viewModel.currentStep) / 13.0
    }

    // MARK: - Navigation buttons (steps 1–11)

    private var goingForward: Bool {
        guard let last = stepHistory.last else { return true }
        return viewModel.currentStep > last
    }

    private var navigationButtons: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Back button
            AppButton(
                title: "Back",
                style: .secondary,
                action: {
                    stepHistory.append(viewModel.currentStep)
                    viewModel.previousStep()
                },
                isDisabled: viewModel.currentStep <= 1
            )

            // Next button
            AppButton(
                title: "Next",
                style: .primary,
                action: {
                    stepHistory.append(viewModel.currentStep)
                    viewModel.nextStep()
                },
                isDisabled: !viewModel.canAdvance(from: viewModel.currentStep)
            )
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private func stepContent(_ step: Int) -> some View {
        switch step {
        case 0:  WelcomeStep(onGetStarted: {
            stepHistory.append(0)
            viewModel.nextStep()
        })
        case 1:  SexStep(sex: $viewModel.sex)
        case 2:  AgeStep(age: $viewModel.age)
        case 3:  WeightHeightStep(
            useImperial: $viewModel.useImperial,
            weightInput: $viewModel.weightInput,
            heightFtInput: $viewModel.heightFtInput,
            heightInInput: $viewModel.heightInInput,
            heightCmInput: $viewModel.heightCmInput
        )
        case 4:  GoalWeightStep(
            useImperial: $viewModel.useImperial,
            goalWeightInput: $viewModel.goalWeightInput,
            directionLabel: viewModel.weightDirectionLabel
        )
        case 5:  WeeklyPaceStep(pace: $viewModel.weeklyPaceLbs)
        case 6:  ActivityLevelStep(activityLevel: $viewModel.activityLevel)
        case 7:  DietStyleStep(dietStyle: $viewModel.dietStyle)
        case 8:  MealsPerDayStep(mealsPerDay: $viewModel.mealsPerDay)
        case 9:  AllergiesStep(allergies: $viewModel.allergies)
        case 10: SleepQualityStep(sleepQuality: $viewModel.sleepQuality)
        case 11: StressLevelStep(
            stressLevel: $viewModel.stressLevel,
            onNext: {
                stepHistory.append(11)
                viewModel.nextStep()
            }
        )
        case 12: CalculatingStep(viewModel: viewModel)
        case 13: ResultsStep(
            viewModel: viewModel,
            onDone: {
                Task {
                    do {
                        try await viewModel.saveResults()
                        dismiss()
                    } catch {
                        // saveError is set in viewModel
                    }
                }
            }
        )
        default: EmptyView()
        }
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            // App icon / logo area
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(
                        DesignSystem.Colors.adaptiveGradient(
                            light: Color(hex: "#34D399"),
                            mid: Color(hex: "#10B981"),
                            dark: Color(hex: "#059669")
                        )
                    )
                    .frame(width: 110, height: 110)
                    .overlay(
                        AdaptiveCardShapeStyle()
                            .stroke(Color(hex: "#047857"), lineWidth: 2)
                    )

                Image(systemName: "heart.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Overheal")
                    .font(AppFont.bold(34))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Your AI-powered nutrition journey")
                    .font(AppFont.regular(16))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Let's build your health profile")
                    .font(AppFont.bold(22))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Answer a few questions and our AI will create personalized calorie and macro targets just for you.")
                    .font(AppFont.regular(16))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
            }

            Spacer()

            AppButton(
                title: "Get Started",
                style: .primary,
                action: onGetStarted
            )
            .padding(.horizontal, DesignSystem.Spacing.md)
            .accessibilityLabel("Get started with health profile setup")
        }
        .padding(.bottom, DesignSystem.Spacing.xl)
    }
}

// MARK: - Step 1: Sex

private struct SexStep: View {
    @Binding var sex: String

    var body: some View {
        OnboardingStepContainer(
            title: "Biological Sex",
            subtitle: "Used to calculate your metabolic rate accurately."
        ) {
            Picker("Sex", selection: $sex) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Select biological sex")
        }
    }
}

// MARK: - Step 2: Age

private struct AgeStep: View {
    @Binding var age: Int

    var body: some View {
        OnboardingStepContainer(
            title: "Your Age",
            subtitle: "Age affects your metabolic rate and calorie needs."
        ) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Text("\(age)")
                    .font(AppFont.bold(64))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .accessibilityLabel("Age: \(age) years")

                Stepper(
                    "Age: \(age)",
                    value: $age,
                    in: 13...80
                )
                .labelsHidden()
                .accessibilityLabel("Adjust age, current value \(age)")
            }
        }
    }
}

// MARK: - Step 3: Weight & Height

private struct WeightHeightStep: View {
    @Binding var useImperial: Bool
    @Binding var weightInput: String
    @Binding var heightFtInput: String
    @Binding var heightInInput: String
    @Binding var heightCmInput: String

    var body: some View {
        OnboardingStepContainer(
            title: "Weight & Height",
            subtitle: "Stored in metric. Converted once at input."
        ) {
            VStack(spacing: DesignSystem.Spacing.md) {
                // Unit toggle
                Picker("Units", selection: $useImperial) {
                    Text("Imperial (lbs / ft)").tag(true)
                    Text("Metric (kg / cm)").tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Select measurement units")

                // Weight field
                OnboardingTextField(
                    label: useImperial ? "Weight (lbs)" : "Weight (kg)",
                    placeholder: useImperial ? "e.g. 175" : "e.g. 80",
                    text: $weightInput,
                    keyboardType: .decimalPad
                )

                // Height fields
                if useImperial {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        OnboardingTextField(
                            label: "Height (ft)",
                            placeholder: "5",
                            text: $heightFtInput,
                            keyboardType: .numberPad
                        )
                        OnboardingTextField(
                            label: "Height (in)",
                            placeholder: "10",
                            text: $heightInInput,
                            keyboardType: .decimalPad
                        )
                    }
                } else {
                    OnboardingTextField(
                        label: "Height (cm)",
                        placeholder: "e.g. 178",
                        text: $heightCmInput,
                        keyboardType: .decimalPad
                    )
                }
            }
        }
    }
}

// MARK: - Step 4: Goal Weight

private struct GoalWeightStep: View {
    @Binding var useImperial: Bool
    @Binding var goalWeightInput: String
    let directionLabel: String

    var body: some View {
        OnboardingStepContainer(
            title: "Goal Weight",
            subtitle: "What's your target weight?"
        ) {
            VStack(spacing: DesignSystem.Spacing.md) {
                OnboardingTextField(
                    label: useImperial ? "Goal Weight (lbs)" : "Goal Weight (kg)",
                    placeholder: useImperial ? "e.g. 160" : "e.g. 72",
                    text: $goalWeightInput,
                    keyboardType: .decimalPad
                )

                if !directionLabel.isEmpty {
                    Text(directionLabel)
                        .font(AppFont.regular(16))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .clipShape(AdaptiveCardShapeStyle())
                        .accessibilityLabel(directionLabel)
                }
            }
        }
    }
}

// MARK: - Step 5: Weekly Pace

private struct WeeklyPaceStep: View {
    @Binding var pace: Double
    private let options: [Double] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        OnboardingStepContainer(
            title: "Weekly Goal",
            subtitle: "How quickly do you want to reach your goal?"
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(options, id: \.self) { option in
                    let isSelected = pace == option
                    Button {
                        pace = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("\(option, specifier: "%.1f") lbs / week")
                                    .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(paceDescription(option))
                                    .font(AppFont.regular(13))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .adaptiveCard(
                            borderColor: isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                            fillColor: isSelected ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option, specifier: "%.1f") lbs per week, \(paceDescription(option))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func paceDescription(_ lbs: Double) -> String {
        switch lbs {
        case 0.5: return "Gentle — easier to sustain long-term"
        case 1.0: return "Steady — recommended for most people"
        case 1.5: return "Aggressive — requires strong discipline"
        case 2.0: return "Maximum — best with medical oversight"
        default:  return ""
        }
    }
}

// MARK: - Step 6: Activity Level

private struct ActivityLevelStep: View {
    @Binding var activityLevel: String

    private let levels: [(id: String, icon: String, title: String, description: String)] = [
        ("sedentary",  "chair.lounge.fill",            "Sedentary",          "Desk job, little or no exercise"),
        ("light",      "figure.walk",                   "Lightly Active",     "Light exercise 1–3 days/week"),
        ("moderate",   "figure.run",                    "Moderately Active",  "Moderate exercise 3–5 days/week"),
        ("active",     "figure.strengthtraining.traditional", "Very Active",  "Hard exercise 6–7 days/week"),
        ("very_active","bolt.fill",                     "Athlete",            "Physical job + daily training")
    ]

    var body: some View {
        OnboardingStepContainer(
            title: "Activity Level",
            subtitle: "How active are you on a typical week?"
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(levels, id: \.id) { level in
                    let isSelected = activityLevel == level.id
                    Button {
                        activityLevel = level.id
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: level.icon)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    DesignSystem.Colors.adaptiveGradient(
                                        light: isSelected ? Color(hex: "#34D399") : Color(hex: "#D1D5DB"),
                                        mid: isSelected ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"),
                                        dark: isSelected ? Color(hex: "#059669") : Color(hex: "#6B7280")
                                    )
                                )
                                .clipShape(AdaptivePillShapeStyle())
                                .overlay(AdaptivePillShapeStyle().stroke(
                                    isSelected ? Color(hex: "#047857") : Color(hex: "#6B7280"),
                                    lineWidth: 2
                                ))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(level.description)
                                    .font(AppFont.regular(13))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .adaptiveCard(
                            borderColor: isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                            fillColor: isSelected ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.title): \(level.description)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Step 7: Diet Style

private struct DietStyleStep: View {
    @Binding var dietStyle: String

    private let styles: [(id: String, icon: String, title: String, description: String)] = [
        ("standard",      "fork.knife",   "Standard",
         "Balanced meals with no restrictions — a mix of all food groups."),
        ("keto",          "drop.fill",    "Keto",
         "Very low carb, high fat. Pushes your body to burn fat for fuel."),
        ("vegan",         "leaf.fill",    "Vegan",
         "No animal products. Plant-based proteins like beans, tofu, and nuts."),
        ("vegetarian",    "carrot.fill",  "Vegetarian",
         "No meat, but dairy and eggs are fine. Flexible and easy to follow."),
        ("paleo",         "flame.fill",   "Paleo",
         "Whole foods only — meat, fish, nuts, veggies. No grains or dairy."),
        ("mediterranean", "fish.fill",    "Mediterranean",
         "Olive oil, fish, veggies, whole grains. Heart-healthy and sustainable.")
    ]

    var body: some View {
        OnboardingStepContainer(
            title: "Diet Style",
            subtitle: "Your preferred way of eating shapes your macro split."
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(styles, id: \.id) { style in
                    let isSelected = dietStyle == style.id
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dietStyle = style.id
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: style.icon)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(
                                    DesignSystem.Colors.adaptiveGradient(
                                        light: isSelected ? Color(hex: "#34D399") : Color(hex: "#D1D5DB"),
                                        mid: isSelected ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"),
                                        dark: isSelected ? Color(hex: "#059669") : Color(hex: "#6B7280")
                                    )
                                )
                                .clipShape(AdaptivePillShapeStyle())
                                .overlay(AdaptivePillShapeStyle().stroke(
                                    isSelected ? Color(hex: "#047857") : Color(hex: "#6B7280"),
                                    lineWidth: 2
                                ))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title)
                                    .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(style.description)
                                    .font(AppFont.regular(13))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .adaptiveCard(
                            borderColor: isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                            fillColor: isSelected ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
                        )
                        .scaleEffect(isSelected ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.title): \(style.description)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Step 8: Meals Per Day

private struct MealsPerDayStep: View {
    @Binding var mealsPerDay: Int

    var body: some View {
        OnboardingStepContainer(
            title: "Meals Per Day",
            subtitle: "How many meals do you typically eat per day?"
        ) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                Text("\(mealsPerDay)")
                    .font(AppFont.bold(64))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .accessibilityLabel("\(mealsPerDay) meals per day")

                Stepper(
                    "Meals: \(mealsPerDay)",
                    value: $mealsPerDay,
                    in: 2...5
                )
                .labelsHidden()
                .accessibilityLabel("Adjust meals per day, current value \(mealsPerDay)")

                Text("2–5 meals per day")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Step 9: Allergies

private struct AllergiesStep: View {
    @Binding var allergies: [String]

    private let options = ["gluten", "dairy", "nuts", "soy", "eggs"]
    private let labels  = ["Gluten", "Dairy", "Nuts", "Soy", "Eggs"]

    var body: some View {
        OnboardingStepContainer(
            title: "Food Allergies",
            subtitle: "Select all that apply. Your AI plan will account for these."
        ) {
            VStack(spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(Array(zip(options, labels)), id: \.0) { id, label in
                        allergyChip(id: id, label: label)
                    }
                }

                // "None" button
                Button {
                    allergies = []
                } label: {
                    Text("None")
                        .font(allergies.isEmpty ? AppFont.bold(16) : AppFont.regular(16))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.md)
                        .adaptiveCard(
                            borderColor: allergies.isEmpty ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                            fillColor: allergies.isEmpty ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("No allergies")
                .accessibilityAddTraits(allergies.isEmpty ? .isSelected : [])
            }
        }
    }

    private func allergyChip(id: String, label: String) -> some View {
        let isSelected = allergies.contains(id)
        return Button {
            if isSelected {
                allergies.removeAll { $0 == id }
            } else {
                allergies.append(id)
            }
        } label: {
            Text(label)
                .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .adaptiveCard(
                    borderColor: isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                    fillColor: isSelected ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) allergy")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Step 10: Sleep Quality

private struct SleepQualityStep: View {
    @Binding var sleepQuality: String

    private let options: [(id: String, icon: String, title: String, description: String)] = [
        ("poor", "moon.zzz.fill", "Poor",  "Often restless or under 6 hrs"),
        ("fair", "moon.fill",     "Fair",  "Around 6–7 hrs, some issues"),
        ("good", "sparkles",      "Good",  "7–9 hrs, feeling rested")
    ]

    var body: some View {
        OnboardingStepContainer(
            title: "Sleep Quality",
            subtitle: "Poor sleep affects metabolism and hunger hormones."
        ) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(options, id: \.id) { option in
                    qualityCard(option: option, binding: $sleepQuality)
                }
            }
        }
    }
}

// MARK: - Step 11: Stress Level

private struct StressLevelStep: View {
    @Binding var stressLevel: String
    let onNext: () -> Void

    private let options: [(id: String, icon: String, title: String, description: String)] = [
        ("low",      "leaf.fill",    "Low",      "Mostly calm, rarely overwhelmed"),
        ("moderate", "wind",         "Moderate", "Some stress, manageable"),
        ("high",     "bolt.fill",    "High",     "Frequently stressed or anxious")
    ]

    var body: some View {
        OnboardingStepContainer(
            title: "Stress Level",
            subtitle: "Chronic stress raises cortisol and can slow fat loss."
        ) {
            VStack(spacing: DesignSystem.Spacing.md) {
                ForEach(options, id: \.id) { option in
                    qualityCard(option: option, binding: $stressLevel)
                }

                // Explicit CTA on final data step
                AppButton(
                    title: "Analyze My Profile",
                    style: .primary,
                    action: onNext
                )
                .padding(.top, DesignSystem.Spacing.md)
                .accessibilityLabel("Analyze my health profile with AI")
            }
        }
    }
}

/// Shared card row for Sleep Quality and Stress Level steps.
private func qualityCard(
    option: (id: String, icon: String, title: String, description: String),
    binding: Binding<String>
) -> some View {
    let isSelected = binding.wrappedValue == option.id
    return Button {
        binding.wrappedValue = option.id
    } label: {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: option.icon)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    DesignSystem.Colors.adaptiveGradient(
                        light: isSelected ? Color(hex: "#34D399") : Color(hex: "#D1D5DB"),
                        mid: isSelected ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"),
                        dark: isSelected ? Color(hex: "#059669") : Color(hex: "#6B7280")
                    )
                )
                .clipShape(AdaptivePillShapeStyle())
                .overlay(AdaptivePillShapeStyle().stroke(
                    isSelected ? Color(hex: "#047857") : Color(hex: "#6B7280"),
                    lineWidth: 2
                ))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(option.description)
                    .font(AppFont.regular(13))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.primary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
            fillColor: isSelected ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.cardBackground
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(option.title): \(option.description)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
}

// MARK: - Step 12: Calculating

private struct CalculatingStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            Spacer()

            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 120, height: 120)
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(DesignSystem.Colors.primary)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Building Your Plan")
                    .font(AppFont.bold(22))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Personalizing your plan with AI...")
                    .font(AppFont.regular(16))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .task {
            await viewModel.calculateAndFetchAI()
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Calculating your personalized nutrition plan")
    }
}

// MARK: - Step 13: Results

private struct ResultsStep: View {
    let viewModel: OnboardingViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)

                    Text("Your Plan is Ready")
                        .font(AppFont.bold(28))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("AI-personalized for your goals and lifestyle")
                        .font(AppFont.regular(16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                // Calorie target
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Daily Calories")
                        .font(AppFont.regular(14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Text("\(viewModel.calculatedCalories)")
                        .font(AppFont.bold(52))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        .accessibilityLabel("\(viewModel.calculatedCalories) calories per day")

                    Text("kcal / day")
                        .font(AppFont.regular(16))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
                .adaptiveCard(borderColor: DesignSystem.Colors.primary, fillColor: DesignSystem.Colors.cardBackground)

                // Macro grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          spacing: DesignSystem.Spacing.md) {
                    macroCard(title: "Protein", value: "\(viewModel.calculatedProtein)g", color: .blue)
                    macroCard(title: "Carbs",   value: "\(viewModel.calculatedCarbs)g",   color: .orange)
                    macroCard(title: "Fat",     value: "\(viewModel.calculatedFat)g",     color: DesignSystem.Colors.energy)
                }

                // AI Tip
                if !viewModel.aiTip.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    DesignSystem.Colors.adaptiveGradient(
                                        light: Color(hex: "#34D399"),
                                        mid: Color(hex: "#10B981"),
                                        dark: Color(hex: "#059669")
                                    )
                                )
                                .clipShape(AdaptivePillShapeStyle())
                                .overlay(AdaptivePillShapeStyle().stroke(Color(hex: "#047857"), lineWidth: 2))
                            Text("Your Coaching Tip")
                                .font(AppFont.bold(17))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        Text(viewModel.aiTip)
                            .font(AppFont.regular(16))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: DesignSystem.Colors.primary.opacity(0.3), fillColor: DesignSystem.Colors.primary.opacity(0.08))
                    .accessibilityLabel("Coaching tip: \(viewModel.aiTip)")
                }

                // Error message
                if let error = viewModel.saveError {
                    Text(error)
                        .font(AppFont.regular(12))
                        .foregroundColor(DesignSystem.Colors.danger)
                        .multilineTextAlignment(.center)
                }

                // CTA
                AppButton(
                    title: "Start My Journey",
                    style: .primary,
                    action: onDone,
                    isLoading: viewModel.isSaving
                )
                .accessibilityLabel("Start my health journey")

                Spacer(minLength: DesignSystem.Spacing.xxl)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }

    private func macroCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(value)
                .font(AppFont.bold(22))
                .foregroundColor(color)
                .accessibilityLabel("\(title): \(value)")
            Text(title)
                .font(AppFont.regular(12))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: color.opacity(0.5), fillColor: DesignSystem.Colors.cardBackground)
    }
}

// MARK: - Shared: OnboardingStepContainer

/// Consistent layout wrapper for data-entry steps.
private struct OnboardingStepContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text(title)
                        .font(AppFont.bold(28))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitle)
                        .font(AppFont.regular(16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                content()
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
    }
}

// MARK: - Shared: OnboardingTextField

private struct OnboardingTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(AppFont.regular(14))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(AdaptiveCardShapeStyle())
                .overlay(
                    AdaptiveCardShapeStyle()
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Step Picker Sheet (edit mode only)

/// A sheet that lists all 11 data steps so the user can jump directly to any one.
/// Only presented in edit mode — new users must step through sequentially.
private struct StepPickerSheet: View {
    let currentStep: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private let steps: [(step: Int, title: String)] = [
        (1,  "Biological Sex"),
        (2,  "Age"),
        (3,  "Weight & Height"),
        (4,  "Goal Weight"),
        (5,  "Weekly Goal"),
        (6,  "Activity Level"),
        (7,  "Diet Style"),
        (8,  "Meals Per Day"),
        (9,  "Food Allergies"),
        (10, "Sleep Quality"),
        (11, "Stress Level")
    ]

    var body: some View {
        NavigationStack {
            List(steps, id: \.step) { item in
                Button {
                    onSelect(item.step)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(
                                size: DesignSystem.FontSizes.body,
                                weight: item.step == currentStep ? .semibold : .regular
                            ))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        if item.step == currentStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }
                }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item.step == currentStep ? .isSelected : [])
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Go to Step")
                        .font(AppFont.bold(18))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
        }
    }
}
