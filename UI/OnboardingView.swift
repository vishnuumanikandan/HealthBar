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
                                .clipShape(Circle())
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
                    .fill(DesignSystem.Colors.primaryGradient)
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
                Circle()
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 110, height: 110)
                Image(systemName: "heart.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(
                color: DesignSystem.Colors.primary.opacity(0.35),
                radius: 16, x: 0, y: 6
            )

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("HealthBar")
                    .font(.system(size: DesignSystem.FontSizes.largeTitle, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Your AI-powered nutrition journey")
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Let's build your health profile")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Answer a few questions and our AI will create personalized calorie and macro targets just for you.")
                    .font(.system(size: DesignSystem.FontSizes.callout))
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
                    .font(.system(size: 64, weight: .bold))
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
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
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
                    Button {
                        pace = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                Text("\(option, specifier: "%.1f") lbs / week")
                                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                                    .foregroundColor(pace == option ? .white : DesignSystem.Colors.textPrimary)
                                Text(paceDescription(option))
                                    .font(.system(size: DesignSystem.FontSizes.caption))
                                    .foregroundColor(pace == option ? .white.opacity(0.85) : DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            if pace == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(pace == option ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .stroke(pace == option ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option, specifier: "%.1f") lbs per week, \(paceDescription(option))")
                    .accessibilityAddTraits(pace == option ? .isSelected : [])
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
                    Button {
                        activityLevel = level.id
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(activityLevel == level.id
                                          ? Color.white.opacity(0.25)
                                          : DesignSystem.Colors.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: level.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(activityLevel == level.id ? .white : DesignSystem.Colors.primary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                                    .foregroundColor(activityLevel == level.id ? .white : DesignSystem.Colors.textPrimary)
                                Text(level.description)
                                    .font(.system(size: DesignSystem.FontSizes.caption))
                                    .foregroundColor(activityLevel == level.id ? .white.opacity(0.85) : DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            if activityLevel == level.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(activityLevel == level.id
                                    ? DesignSystem.Colors.primary
                                    : DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .stroke(activityLevel == level.id ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.title): \(level.description)")
                    .accessibilityAddTraits(activityLevel == level.id ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Step 7: Diet Style

private struct DietStyleStep: View {
    @Binding var dietStyle: String

    private let styles: [(id: String, icon: String, title: String)] = [
        ("standard",      "fork.knife",              "Standard"),
        ("keto",          "drop.fill",               "Keto"),
        ("vegan",         "leaf.fill",               "Vegan"),
        ("vegetarian",    "carrot.fill",             "Vegetarian"),
        ("paleo",         "flame.fill",              "Paleo"),
        ("mediterranean", "fish.fill",               "Mediterranean")
    ]

    var body: some View {
        OnboardingStepContainer(
            title: "Diet Style",
            subtitle: "Your preferred way of eating shapes your macro split."
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(styles, id: \.id) { style in
                        Button {
                            dietStyle = style.id
                        } label: {
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                ZStack {
                                    Circle()
                                        .fill(dietStyle == style.id
                                              ? DesignSystem.Colors.primary
                                              : DesignSystem.Colors.primary.opacity(0.1))
                                        .frame(width: 64, height: 64)
                                    Image(systemName: style.icon)
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(dietStyle == style.id ? .white : DesignSystem.Colors.primary)
                                }
                                Text(style.title)
                                    .font(.system(size: DesignSystem.FontSizes.subheadline, weight: .medium))
                                    .foregroundColor(dietStyle == style.id
                                                     ? DesignSystem.Colors.primary
                                                     : DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 88)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(dietStyle == style.id
                                        ? DesignSystem.Colors.primary.opacity(0.1)
                                        : DesignSystem.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                    .stroke(dietStyle == style.id
                                            ? DesignSystem.Colors.primary
                                            : DesignSystem.Colors.border, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(style.title) diet style")
                        .accessibilityAddTraits(dietStyle == style.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
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
                    .font(.system(size: 64, weight: .bold))
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
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(allergies.isEmpty ? .white : DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.md)
                        .background(allergies.isEmpty ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .stroke(allergies.isEmpty ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
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
                .font(.system(size: DesignSystem.FontSizes.subheadline, weight: .medium))
                .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(isSelected ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
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
            ZStack {
                Circle()
                    .fill(isSelected
                          ? Color.white.opacity(0.25)
                          : DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? .white : DesignSystem.Colors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
                Text(option.description)
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : DesignSystem.Colors.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(isSelected ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
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
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 120, height: 120)
                ProgressView()
                    .scaleEffect(2.0)
                    .tint(DesignSystem.Colors.primary)
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Building Your Plan")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Personalizing your plan with AI...")
                    .font(.system(size: DesignSystem.FontSizes.callout))
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
                        .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("AI-personalized for your goals and lifestyle")
                        .font(.system(size: DesignSystem.FontSizes.callout))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                // Calorie target
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Daily Calories")
                        .font(.system(size: DesignSystem.FontSizes.subheadline, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Text("\(viewModel.calculatedCalories)")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        .accessibilityLabel("\(viewModel.calculatedCalories) calories per day")

                    Text("kcal / day")
                        .font(.system(size: DesignSystem.FontSizes.callout))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                .shadow(
                    color: DesignSystem.Shadows.card.color,
                    radius: DesignSystem.Shadows.card.radius,
                    x: DesignSystem.Shadows.card.x,
                    y: DesignSystem.Shadows.card.y
                )

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
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("Your Coaching Tip")
                                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        Text(viewModel.aiTip)
                            .font(.system(size: DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .accessibilityLabel("Coaching tip: \(viewModel.aiTip)")
                }

                // Error message
                if let error = viewModel.saveError {
                    Text(error)
                        .font(.system(size: DesignSystem.FontSizes.caption))
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
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                .foregroundColor(color)
                .accessibilityLabel("\(title): \(value)")
            Text(title)
                .font(.system(size: DesignSystem.FontSizes.caption))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
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
                        .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitle)
                        .font(.system(size: DesignSystem.FontSizes.callout))
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
                .font(.system(size: DesignSystem.FontSizes.subheadline, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
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
            .navigationTitle("Go to Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
        }
    }
}
