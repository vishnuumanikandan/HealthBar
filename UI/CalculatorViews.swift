//
//  CalculatorViews.swift
//  HealthBar
//
//  Created by Claude on 3/30/26.
//

import SwiftUI

// MARK: - Shared Helpers

private enum UnitSystem: String, CaseIterable {
    case imperial = "Imperial (lbs/ft/in)"
    case metric   = "Metric (kg/cm)"
}

// Reusable disclaimer at the bottom of every calculator
private struct CalculatorDisclaimer: View {
    var body: some View {
        Text("These are estimates based on scientific formulas. Consult a healthcare professional for personalized advice.")
            .font(.system(size: DesignSystem.FontSizes.caption))
            .foregroundColor(DesignSystem.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.sm)
    }
}

// Reusable results card container
private struct ResultCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            content
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }
}

// Reusable result row
private struct ResultRow: View {
    let label: String
    let value: String
    var highlight: Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: DesignSystem.FontSizes.callout,
                              weight: highlight ? .semibold : .regular))
                .foregroundColor(highlight ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .bold))
                .foregroundColor(highlight ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
        }
    }
}

// Reusable info sheet
private struct InfoSheet: View {
    let title: String
    let bodyText: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(bodyText)
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// Labeled numeric field
private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .decimalPad
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .font(.system(size: DesignSystem.FontSizes.body))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
        }
    }
}

// MARK: - Calculator 1: TDEE

struct TDEEView: View {

    let toolsViewModel: ToolsViewModel

    @State private var units: UnitSystem = .imperial
    @State private var sex: String = "Male"
    @State private var ageText: String = ""
    @State private var weightText: String = ""
    @State private var heightFtText: String = ""
    @State private var heightInText: String = ""
    @State private var heightCmText: String = ""
    @State private var activityIndex: Int = 0
    @State private var showInfo: Bool = false

    private let activityLabels = [
        "Sedentary (desk job, no exercise)",
        "Lightly Active (1–3 days/week)",
        "Moderately Active (3–5 days/week)",
        "Very Active (6–7 days/week)",
        "Extremely Active (physical job + daily training)"
    ]
    private let activityMultipliers = [1.2, 1.375, 1.55, 1.725, 1.9]

    private var bmr: Double? {
        guard let age = Double(ageText), age > 0,
              let w = Double(weightText), w > 0 else { return nil }
        let kg = units == .imperial ? w * 0.453592 : w
        let cm: Double
        if units == .imperial {
            let ft = Double(heightFtText) ?? 0
            let inches = Double(heightInText) ?? 0
            cm = (ft * 12 + inches) * 2.54
        } else {
            cm = Double(heightCmText) ?? 0
        }
        guard cm > 0 else { return nil }
        return sex == "Male"
            ? 10 * kg + 6.25 * cm - 5 * age + 5
            : 10 * kg + 6.25 * cm - 5 * age - 161
    }

    private var tdee: Double? {
        guard let b = bmr else { return nil }
        return b * activityMultipliers[activityIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Sex", selection: $sex) {
                    Text("Male").tag("Male"); Text("Female").tag("Female")
                }
                .pickerStyle(.segmented)

                LabeledField(label: "Age (years)", placeholder: "25", text: $ageText, keyboard: .numberPad)

                if units == .imperial {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        LabeledField(label: "Height (ft)", placeholder: "5", text: $heightFtText, keyboard: .numberPad)
                        LabeledField(label: "Height (in)", placeholder: "10", text: $heightInText)
                    }
                    LabeledField(label: "Weight (lbs)", placeholder: "175", text: $weightText)
                } else {
                    LabeledField(label: "Height (cm)", placeholder: "178", text: $heightCmText)
                    LabeledField(label: "Weight (kg)", placeholder: "80", text: $weightText)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Activity Level")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Activity", selection: $activityIndex) {
                        ForEach(activityLabels.indices, id: \.self) { i in
                            Text(activityLabels[i]).tag(i)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .background(DesignSystem.Colors.cardBackground.clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }

                if let b = bmr, let t = tdee {
                    ResultCard {
                        Text("Results").font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold)).foregroundColor(DesignSystem.Colors.textTertiary)
                        ResultRow(label: "Basal Metabolic Rate (BMR)", value: "\(Int(b)) cal/day")
                        Divider()
                        ResultRow(label: "Maintenance (TDEE)", value: "\(Int(t)) cal", highlight: true)
                        ResultRow(label: "Fat Loss (−500)", value: "\(Int(t - 500)) cal")
                        ResultRow(label: "Aggressive Fat Loss (−750)", value: "\(Int(t - 750)) cal")
                        ResultRow(label: "Muscle Gain (+300)", value: "\(Int(t + 300)) cal")
                    }
                    .onAppear { toolsViewModel.lastTDEE = t }
                    .onChange(of: t) { _, newVal in toolsViewModel.lastTDEE = newVal }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("TDEE Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "How TDEE is Calculated", bodyText: """
            TDEE (Total Daily Energy Expenditure) tells you how many calories you burn per day.

            Step 1 – BMR (Basal Metabolic Rate) using Mifflin-St Jeor:
            • Male:   BMR = (10 × kg) + (6.25 × cm) − (5 × age) + 5
            • Female: BMR = (10 × kg) + (6.25 × cm) − (5 × age) − 161

            Step 2 – Multiply BMR by an activity factor:
            • Sedentary → ×1.2
            • Lightly Active (1–3 days/week) → ×1.375
            • Moderately Active (3–5 days/week) → ×1.55
            • Very Active (6–7 days/week) → ×1.725
            • Extremely Active → ×1.9

            Goal targets:
            • Fat Loss = TDEE − 500 cal/day (~1 lb/week)
            • Aggressive Fat Loss = TDEE − 750 cal/day
            • Muscle Gain = TDEE + 300 cal/day (lean bulk)
            """)
        }
    }
}

// MARK: - Calculator 2: Protein

struct ProteinView: View {

    @State private var units: UnitSystem = .imperial
    @State private var weightText: String = ""
    @State private var goal: String = "Fat Loss"
    @State private var activityLevel: String = "Active"
    @State private var showInfo: Bool = false

    private let goals = ["Fat Loss", "Maintenance", "Muscle Gain"]
    private let activityLevels = ["Sedentary", "Active", "Very Active"]

    private var dailyMinG: Double? {
        guard let w = Double(weightText), w > 0 else { return nil }
        let lbs = units == .imperial ? w : w * 2.20462
        return lbs * minMultiplier
    }

    private var dailyMaxG: Double? {
        guard let w = Double(weightText), w > 0 else { return nil }
        let lbs = units == .imperial ? w : w * 2.20462
        return lbs * maxMultiplier
    }

    private var minMultiplier: Double {
        switch (goal, activityLevel) {
        case ("Maintenance", "Sedentary"): return 0.6
        case ("Fat Loss", _): return 0.8
        case ("Muscle Gain", "Very Active"): return 1.0
        case ("Muscle Gain", _): return 1.0
        default: return 0.7
        }
    }

    private var maxMultiplier: Double {
        switch (goal, activityLevel) {
        case ("Maintenance", "Sedentary"): return 0.6
        case ("Fat Loss", _): return 1.0
        case ("Muscle Gain", "Very Active"): return 1.2
        case ("Muscle Gain", _): return 1.0
        default: return 0.8
        }
    }

    private var note: String {
        switch goal {
        case "Fat Loss": return "Protein needs are higher during fat loss to preserve muscle mass."
        case "Muscle Gain" where activityLevel == "Very Active": return "Higher intake supports muscle protein synthesis under heavy training."
        case "Muscle Gain": return "1g per pound of bodyweight is the standard muscle-building target."
        default: return "Moderate protein to maintain muscle with moderate activity."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledField(label: units == .imperial ? "Weight (lbs)" : "Weight (kg)", placeholder: units == .imperial ? "175" : "80", text: $weightText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Goal").font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium)).foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Goal", selection: $goal) {
                        ForEach(goals, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Activity Level").font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium)).foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Activity", selection: $activityLevel) {
                        ForEach(activityLevels, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let minG = dailyMinG, let maxG = dailyMaxG {
                    ResultCard {
                        Text("Results").font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold)).foregroundColor(DesignSystem.Colors.textTertiary)
                        if Int(minG) == Int(maxG) {
                            ResultRow(label: "Daily Protein Target", value: "\(Int(minG))g", highlight: true)
                            ResultRow(label: "Per Meal (÷4)", value: "\(Int(minG / 4))g")
                        } else {
                            ResultRow(label: "Daily Protein Target", value: "\(Int(minG))–\(Int(maxG))g", highlight: true)
                            ResultRow(label: "Per Meal (÷4)", value: "\(Int(minG / 4))–\(Int(maxG / 4))g")
                        }
                        Divider()
                        Text(note)
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Protein Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "How Protein is Calculated", bodyText: """
            Protein targets in grams per pound of bodyweight (g/lb):

            • Sedentary, Maintenance: 0.6 g/lb
            • Active, Fat Loss: 0.8–1.0 g/lb — higher during deficit preserves muscle
            • Muscle Gain: 1.0 g/lb
            • Very Active / Hard Training: 1.0–1.2 g/lb

            The per-meal target divides the daily total by 4 to spread intake throughout the day, which research suggests maximises muscle protein synthesis.
            """)
        }
    }
}

// MARK: - Calculator 3: One Rep Max

struct OneRepMaxView: View {

    @State private var units: UnitSystem = .imperial
    @State private var weightText: String = ""
    @State private var reps: Int = 5
    @State private var showInfo: Bool = false

    private let percentages: [(pct: Double, label: String)] = [
        (0.95, "Near-maximal strength"),
        (0.85, "Heavy strength (3–5 reps)"),
        (0.75, "Hypertrophy (8–10 reps)"),
        (0.65, "Volume work (12–15 reps)"),
        (0.50, "Warm-up / technique")
    ]

    private var oneRM: Double? {
        guard let w = Double(weightText), w > 0, reps >= 1 else { return nil }
        let epley = w * (1 + 0.0333 * Double(reps))
        let brz   = w / (1.0278 - 0.0278 * Double(reps))
        return (epley + brz) / 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledField(label: units == .imperial ? "Weight Lifted (lbs)" : "Weight Lifted (kg)", placeholder: "185", text: $weightText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text("Reps Performed")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Text("\(reps)")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .bold))
                            .foregroundColor(reps > 10 ? DesignSystem.Colors.warning : DesignSystem.Colors.textPrimary)
                    }
                    Stepper("", value: $reps, in: 1...12).labelsHidden()
                    if reps > 10 {
                        Text("⚠️ Accuracy decreases above 10 reps")
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                }

                if let rm = oneRM {
                    ResultCard {
                        Text("Estimated 1RM")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text(String(format: "%.1f", rm) + (units == .imperial ? " lbs" : " kg"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.primary)
                        Divider()
                        Text("Percentage Table")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        ForEach(percentages, id: \.pct) { entry in
                            ResultRow(
                                label: "\(Int(entry.pct * 100))% — \(entry.label)",
                                value: "\(Int(rm * entry.pct)) \(units == .imperial ? "lbs" : "kg")"
                            )
                        }
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("One Rep Max")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "1RM Formula", bodyText: """
            Averages two well-known formulas:

            Epley:   1RM = weight × (1 + 0.0333 × reps)
            Brzycki: 1RM = weight / (1.0278 − 0.0278 × reps)

            Averaging these two generally improves accuracy. Both become less reliable above 10 reps.

            The percentage table shows common strength training zones.
            """)
        }
    }
}

// MARK: - Calculator 4: Muscle Gain Potential

struct MuscleGainView: View {

    @State private var units: UnitSystem = .imperial
    @State private var sex: String = "Male"
    @State private var heightText: String = ""
    @State private var wristText: String = ""
    @State private var experience: String = "Beginner (0–1 yr)"
    @State private var showInfo: Bool = false

    private let experienceOptions = ["Beginner (0–1 yr)", "Intermediate (1–3 yrs)", "Advanced (3+ yrs)"]

    private var maxLeanMass: Double? {
        guard let h = Double(heightText), h > 0 else { return nil }
        let heightIn = units == .imperial ? h : h / 2.54
        let wristIn  = units == .imperial ? (Double(wristText) ?? 0) : ((Double(wristText) ?? 0) / 2.54)
        var maxLbs = (heightIn - 70) * 5 + 160
        if wristIn > 6.5 { maxLbs += maxLbs * 0.05 * (wristIn - 6.5) }
        if sex == "Female" { maxLbs *= 0.6 }
        return units == .imperial ? maxLbs : maxLbs * 0.453592
    }

    private var annualGainRange: (Double, Double) {
        switch experience {
        case "Beginner (0–1 yr)":      let v = units == .imperial ? (20.0, 25.0) : (9.0, 11.0); return v
        case "Intermediate (1–3 yrs)": let v = units == .imperial ? (10.0, 12.0) : (4.5, 5.5); return v
        default:                        let v = units == .imperial ? (4.0, 6.0)   : (1.8, 2.7); return v
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Sex", selection: $sex) {
                    Text("Male").tag("Male"); Text("Female").tag("Female")
                }
                .pickerStyle(.segmented)

                LabeledField(
                    label: units == .imperial ? "Height (inches)" : "Height (cm)",
                    placeholder: units == .imperial ? "70" : "178", text: $heightText)
                LabeledField(
                    label: units == .imperial ? "Wrist Circumference (inches)" : "Wrist Circumference (cm)",
                    placeholder: units == .imperial ? "6.5" : "16.5", text: $wristText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Training Experience")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Experience", selection: $experience) {
                        ForEach(experienceOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .background(DesignSystem.Colors.cardBackground.clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }

                if let maxMass = maxLeanMass {
                    let unitLabel = units == .imperial ? "lbs" : "kg"
                    let (annMin, annMax) = annualGainRange
                    ResultCard {
                        Text("Results").font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold)).foregroundColor(DesignSystem.Colors.textTertiary)
                        ResultRow(label: "Max Natural Lean Mass", value: String(format: "%.1f \(unitLabel)", maxMass), highlight: true)
                        ResultRow(label: "Annual Gain Potential", value: String(format: "%.1f–%.1f \(unitLabel)/year", annMin, annMax))
                        Divider()
                        Text("Genetic variability is significant. These are statistical averages, not guarantees.")
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Muscle Gain Potential")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "Muscle Potential Formula", bodyText: """
            Uses the Berkhan/Butt approximation:

            Male max lean mass (lbs) ≈ (height in inches − 70) × 5 + 160
            Female max lean mass ≈ 60% of the male estimate

            Wrist adjustment: +5% per inch of wrist above 6.5"

            Annual gain rates:
            • Beginner (0–1 yr): 20–25 lbs/year
            • Intermediate (1–3 yrs): 10–12 lbs/year
            • Advanced (3+ yrs): 4–6 lbs/year

            Individual genetics, training quality, nutrition, and recovery all influence results.
            """)
        }
    }
}

// MARK: - Calculator 5: Creatine

struct CreatineView: View {

    @State private var units: UnitSystem = .imperial
    @State private var weightText: String = ""
    @State private var useLoadingPhase: Bool = false
    @State private var showInfo: Bool = false

    private var maintenanceG: Double? {
        guard let w = Double(weightText), w > 0 else { return nil }
        let kg = units == .imperial ? w * 0.453592 : w
        return min(5.0, max(3.0, kg * 0.03))
    }

    private var loadingPerDoseG: Double? {
        guard let w = Double(weightText), w > 0 else { return nil }
        let kg = units == .imperial ? w * 0.453592 : w
        return kg * 0.3 / 4
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledField(label: units == .imperial ? "Weight (lbs)" : "Weight (kg)", placeholder: units == .imperial ? "175" : "80", text: $weightText)

                Toggle(isOn: $useLoadingPhase) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Loading Phase")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("Saturates muscles faster (5–7 days)")
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .tint(DesignSystem.Colors.primary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))

                if let maint = maintenanceG {
                    ResultCard {
                        Text("Results").font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold)).foregroundColor(DesignSystem.Colors.textTertiary)
                        ResultRow(label: "Maintenance Dose", value: String(format: "%.1fg/day", maint), highlight: true)
                        if useLoadingPhase, let perDose = loadingPerDoseG {
                            Divider()
                            ResultRow(label: "Loading Phase Duration", value: "5–7 days")
                            ResultRow(label: "Loading Dose (per dose)", value: String(format: "%.1fg × 4/day", perDose))
                            ResultRow(label: "Loading Total/Day", value: String(format: "%.1fg/day", perDose * 4))
                        }
                        Divider()
                        Text("Loading is optional. The maintenance dose achieves the same result in 3–4 weeks. Use creatine monohydrate.")
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Creatine Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "Creatine Dosing", bodyText: """
            Maintenance dose: bodyweight (kg) × 0.03g/day
            Minimum: 3g/day | Maximum: 5g/day

            Loading phase (optional):
            bodyweight (kg) × 0.3g/day, split into 4 doses, for 5–7 days.

            Loading saturates muscles faster but is not required. Skipping it and taking maintenance dose daily produces the same end result in ~3–4 weeks.

            Tip: Take creatine consistently. Timing is less important than daily compliance. Use creatine monohydrate — it's the most researched form.
            """)
        }
    }
}

// MARK: - Calculator 6: Strength Standards

struct StrengthStandardsView: View {

    @State private var units: UnitSystem = .imperial
    @State private var sex: String = "Male"
    @State private var bodyweightText: String = ""
    @State private var lift: String = "Bench Press"
    @State private var currentMaxText: String = ""
    @State private var showInfo: Bool = false

    private let lifts = ["Bench Press", "Squat", "Deadlift", "Overhead Press"]
    private let levels = ["Beginner", "Novice", "Intermediate", "Advanced", "Elite"]

    // multipliers[liftName][sexIndex 0=male 1=female][levelIndex 0–4]
    private let multipliers: [String: [[Double]]] = [
        "Bench Press":    [[0.5, 0.75, 1.0, 1.5, 2.0], [0.25, 0.5, 0.75, 1.0, 1.5]],
        "Squat":          [[0.75, 1.0, 1.5, 2.0, 2.5], [0.5, 0.75, 1.0, 1.5, 2.0]],
        "Deadlift":       [[1.0, 1.25, 1.75, 2.5, 3.0], [0.5, 0.75, 1.25, 1.75, 2.25]],
        "Overhead Press": [[0.35, 0.5, 0.75, 1.0, 1.35], [0.2, 0.35, 0.5, 0.75, 1.0]]
    ]

    private var currentLevelIndex: Int? {
        guard let bw = Double(bodyweightText), bw > 0,
              let maxVal = Double(currentMaxText), maxVal > 0,
              let mults = multipliers[lift] else { return nil }
        let row = sex == "Male" ? mults[0] : mults[1]
        for i in stride(from: row.count - 1, through: 0, by: -1) {
            if maxVal >= bw * row[i] { return i }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Sex", selection: $sex) {
                    Text("Male").tag("Male"); Text("Female").tag("Female")
                }
                .pickerStyle(.segmented)

                LabeledField(label: units == .imperial ? "Bodyweight (lbs)" : "Bodyweight (kg)", placeholder: units == .imperial ? "175" : "80", text: $bodyweightText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Lift").font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium)).foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Lift", selection: $lift) {
                        ForEach(lifts, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                LabeledField(label: "Current Max (\(units == .imperial ? "lbs" : "kg")) — Optional", placeholder: "Leave blank to see all targets", text: $currentMaxText)

                if let bw = Double(bodyweightText), bw > 0,
                   let mults = multipliers[lift] {
                    let row = sex == "Male" ? mults[0] : mults[1]
                    ResultCard {
                        Text("Standards for \(lift) (\(sex))")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        ForEach(levels.indices, id: \.self) { i in
                            let target = bw * row[i]
                            let isCurrent = currentLevelIndex == i
                            HStack {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    if isCurrent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DesignSystem.Colors.primary)
                                            .font(.system(size: 14))
                                    }
                                    Text(levels[i])
                                        .font(.system(size: DesignSystem.FontSizes.callout, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                                }
                                Spacer()
                                Text("\(Int(target)) \(units == .imperial ? "lbs" : "kg") (\(String(format: "%.2f", row[i]))×)")
                                    .font(.system(size: DesignSystem.FontSizes.callout, weight: isCurrent ? .bold : .regular))
                                    .foregroundColor(isCurrent ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
                            }
                        }
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Strength Standards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "Strength Standards", bodyText: """
            Standards are expressed as bodyweight multipliers and represent widely accepted milestones in competitive and recreational strength training.

            Levels:
            • Beginner — just starting out
            • Novice — a few months of consistent training
            • Intermediate — 1–2 years of structured training
            • Advanced — multiple years, serious numbers
            • Elite — competitive-level performance

            Individual anatomy, leverages, and training history all influence results.
            """)
        }
    }
}

// MARK: - Calculator 7: Sleep Toolkit

private struct BedtimeOption: Identifiable {
    let id = UUID()
    let cycles: Int
    let label: String
    let timeString: String
}

struct SleepToolkitView: View {

    @State private var ageText: String = ""
    @State private var wakeTime: Date = {
        var c = DateComponents(); c.hour = 7; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var showInfo: Bool = false

    private var recommendedHours: String {
        guard let age = Int(ageText) else { return "Enter your age above" }
        switch age {
        case 14...17: return "8–10 hours"
        case 18...64: return "7–9 hours"
        case 65...120: return "7–8 hours"
        default: return "Consult a healthcare professional"
        }
    }

    private var bedtimeOptions: [BedtimeOption] {
        let fmt = DateFormatter(); fmt.timeStyle = .short
        let fallAsleepSecs: TimeInterval = 15 * 60
        let cycleLength: TimeInterval = 90 * 60
        return [5, 6].map { cycles in
            let offset = Double(cycles) * cycleLength + fallAsleepSecs
            let bed = wakeTime.addingTimeInterval(-offset)
            return BedtimeOption(
                cycles: cycles,
                label: "\(cycles) cycles (\(cycles == 5 ? "7.5" : "9.0") hrs)",
                timeString: fmt.string(from: bed)
            )
        }
    }

    private let tips: [(icon: String, text: String)] = [
        ("clock.fill",         "Keep consistent sleep/wake times 7 days a week"),
        ("lightbulb.slash",    "Avoid bright/blue light 1–2 hours before bed"),
        ("thermometer.medium", "Keep bedroom cool: 65–68°F / 18–20°C"),
        ("cup.and.saucer",     "Avoid caffeine after 2 PM (half-life ~5–6 hours)"),
        ("wineglass",          "Avoid alcohol — fragments sleep, suppresses REM"),
        ("sun.max.fill",       "Get morning sunlight within 30–60 min of waking")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {

                // Sleep Duration Recommender
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Sleep Duration Recommender")
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    LabeledField(label: "Age (years)", placeholder: "30", text: $ageText, keyboard: .numberPad)
                    if !ageText.isEmpty {
                        ResultCard {
                            ResultRow(label: "Recommended Sleep", value: recommendedHours, highlight: true)
                        }
                    }
                }

                Divider().background(DesignSystem.Colors.border)

                // Bedtime Calculator
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Bedtime Calculator")
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Wake-up Time")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .padding(DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                    }

                    Text("Recommended bedtimes (includes 15 min to fall asleep):")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    ResultCard {
                        ForEach(bedtimeOptions) { option in
                            ResultRow(label: option.label, value: option.timeString, highlight: option.cycles == 6)
                        }
                    }
                }

                Divider().background(DesignSystem.Colors.border)

                // Sleep Tips
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Sleep Tips")
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    ForEach(tips, id: \.text) { tip in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            Image(systemName: tip.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(width: 24)
                            Text(tip.text)
                                .font(.system(size: DesignSystem.FontSizes.callout))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Sleep Toolkit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "About Sleep Toolkit", bodyText: """
            Sleep Duration Recommendations (National Sleep Foundation):
            • Teens (14–17): 8–10 hours
            • Adults (18–64): 7–9 hours
            • Older Adults (65+): 7–8 hours

            Bedtime Calculator:
            Sleep occurs in ~90-minute cycles. Waking at cycle end reduces grogginess. This tool adds 15 minutes for time to fall asleep, then shows bedtimes for 5 cycles (7.5 hrs) and 6 cycles (9 hrs).

            The sleep tips are based on well-established sleep hygiene practices.
            """)
        }
    }
}

// MARK: - Calculator 8: Macro Calculator

struct MacroView: View {

    let toolsViewModel: ToolsViewModel

    @State private var units: UnitSystem = .imperial
    @State private var tdeeText: String = ""
    @State private var bodyweightText: String = ""
    @State private var goal: String = "Maintenance"
    @State private var dietStyle: String = "Balanced"
    @State private var showInfo: Bool = false

    private let goals = ["Fat Loss", "Maintenance", "Muscle Gain"]
    private let dietStyles = ["Balanced", "High Protein", "Low Carb"]

    private var effectiveTDEE: Double? {
        if let t = Double(tdeeText), t > 0 { return t }
        return toolsViewModel.lastTDEE
    }

    private struct MacroResult {
        let targetCal: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        var proteinCal: Double { proteinG * 4 }
        var carbsCal: Double   { carbsG * 4 }
        var fatCal: Double     { fatG * 9 }
    }

    private var result: MacroResult? {
        guard let tdee = effectiveTDEE, tdee > 0,
              let bw = Double(bodyweightText), bw > 0 else { return nil }
        let lbs = units == .imperial ? bw : bw * 2.20462
        let targetCal: Double = {
            switch goal {
            case "Fat Loss":    return tdee - 500
            case "Muscle Gain": return tdee + 300
            default:            return tdee
            }
        }()
        let proteinG = lbs * 1.0
        let remaining = max(0, targetCal - proteinG * 4)
        let (carbsPct, fatPct): (Double, Double) = {
            switch dietStyle {
            case "High Protein": return (0.30, 0.20)
            case "Low Carb":     return (0.20, 0.50)
            default:             return (0.40, 0.30)
            }
        }()
        let totalRatio = carbsPct + fatPct
        let carbsG = max(0, remaining * (carbsPct / totalRatio) / 4)
        let fatG   = max(0, remaining * (fatPct  / totalRatio) / 9)
        return MacroResult(targetCal: targetCal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Picker("Units", selection: $units) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                // TDEE field — auto-fills from Calculator 1
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text("TDEE (cal/day)")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        if toolsViewModel.lastTDEE != nil && tdeeText.isEmpty {
                            Text("· Auto-filled")
                                .font(.system(size: DesignSystem.FontSizes.caption))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }
                    TextField(toolsViewModel.lastTDEE.map { "\(Int($0))" } ?? "e.g. 2200", text: $tdeeText)
                        .keyboardType(.numberPad)
                        .font(.system(size: DesignSystem.FontSizes.body))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }

                LabeledField(label: units == .imperial ? "Bodyweight (lbs)" : "Bodyweight (kg)", placeholder: units == .imperial ? "175" : "80", text: $bodyweightText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Goal").font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium)).foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Goal", selection: $goal) {
                        ForEach(goals, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Diet Style").font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium)).foregroundColor(DesignSystem.Colors.textSecondary)
                    Picker("Diet Style", selection: $dietStyle) {
                        ForEach(dietStyles, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let r = result {
                    ResultCard {
                        Text("Daily Macros").font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold)).foregroundColor(DesignSystem.Colors.textTertiary)
                        ResultRow(label: "Target Calories", value: "\(Int(r.targetCal)) cal")
                        Divider()
                        ResultRow(label: "Protein", value: "\(Int(r.proteinG))g (\(Int(r.proteinCal)) cal)", highlight: true)
                        ResultRow(label: "Carbs",   value: "\(Int(r.carbsG))g (\(Int(r.carbsCal)) cal)")
                        ResultRow(label: "Fat",     value: "\(Int(r.fatG))g (\(Int(r.fatCal)) cal)")
                        Divider()
                        // Visual macro bar
                        let total = r.proteinCal + r.carbsCal + r.fatCal
                        if total > 0 {
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(DesignSystem.Colors.primary)
                                        .frame(width: geo.size.width * CGFloat(r.proteinCal / total))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange)
                                        .frame(width: geo.size.width * CGFloat(r.carbsCal / total))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.purple)
                                        .frame(width: max(2, geo.size.width * CGFloat(r.fatCal / total)))
                                }
                            }
                            .frame(height: 12)
                        }
                        HStack(spacing: DesignSystem.Spacing.md) {
                            macroLegend(color: DesignSystem.Colors.primary, label: "Protein")
                            macroLegend(color: .orange,                     label: "Carbs")
                            macroLegend(color: .purple,                     label: "Fat")
                        }
                        .font(.system(size: DesignSystem.FontSizes.caption))
                    }
                }

                CalculatorDisclaimer()
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Macro Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle").foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(title: "Macro Calculation Method", bodyText: """
            Protein is set to 1g per pound of bodyweight — the gold standard for muscle preservation and growth.

            Calorie targets:
            • Fat Loss: TDEE − 500 cal/day
            • Maintenance: TDEE
            • Muscle Gain: TDEE + 300 cal/day

            Remaining calories (after protein) are split by diet style:
            • Balanced: 40% carbs, 30% fat
            • High Protein: 30% carbs, 20% fat
            • Low Carb: 20% carbs, 50% fat

            Energy: Protein = 4 cal/g · Carbs = 4 cal/g · Fat = 9 cal/g

            If you used the TDEE Calculator first, your TDEE is auto-filled here.
            """)
        }
    }

    private func macroLegend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}
