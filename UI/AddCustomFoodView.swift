//
//  AddCustomFoodView.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import SwiftUI

/// Form for creating or editing a custom food entry in My Foods.
///
/// Users fill in the food name, nutrition per serving, and serving size details.
/// Saved foods appear in My Foods and are searchable across all database tabs.
struct AddCustomFoodView: View {

    // MARK: - Properties

    let existingFood: CustomFood?
    let onSave: (CustomFood) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    private var tc: ThemeColors { settings.activeTheme.colors }

    // MARK: - Form State

    @State private var name: String = ""
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var servingSizeName: String = "1 serving"
    @State private var servingSizeAmountText: String = "1"
    @State private var servingUnit: String = "serving"
    @State private var fiberText: String = ""
    @State private var sugarText: String = ""
    @State private var sodiumText: String = ""
    @State private var showAdvanced: Bool = false
    @State private var isSaving: Bool = false
    @State private var validationError: String? = nil

    // MARK: - Init

    init(existingFood: CustomFood? = nil, onSave: @escaping (CustomFood) -> Void) {
        self.existingFood = existingFood
        self.onSave = onSave
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(caloriesText) != nil
            && Double(proteinText) != nil
            && Double(carbsText) != nil
            && Double(fatText) != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                nutritionSection
                servingSizeSection
                if showAdvanced { advancedSection }
                advancedToggleSection
            }
            .scrollContentBackground(.hidden)
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle(existingFood == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PixelFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(tc.primary)
                    } else {
                        Button("Save") { save() }
                            .font(PixelFont.bold(16))
                            .foregroundColor(isValid ? tc.primary : tc.textTertiary)
                            .disabled(!isValid)
                    }
                }
            }
            .onAppear { prefill() }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("e.g. Mom's Pasta, Protein Smoothie", text: $name)
        } header: {
            Text("Food Name")
                .font(PixelFont.bold(14))
        }
    }

    private var nutritionSection: some View {
        Section {
            LabeledContent("Calories") {
                TextField("kcal", text: $caloriesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Protein (g)") {
                TextField("0", text: $proteinText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Carbs (g)") {
                TextField("0", text: $carbsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Fat (g)") {
                TextField("0", text: $fatText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Nutrition Per Serving")
                .font(PixelFont.bold(14))
        }
    }

    private var servingSizeSection: some View {
        Section {
            LabeledContent("Label") {
                TextField("e.g. 1 cup, 100g, 1 plate", text: $servingSizeName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Amount") {
                TextField("1", text: $servingSizeAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Unit") {
                TextField("e.g. g, cup, oz, serving", text: $servingUnit)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Serving Size")
                .font(PixelFont.bold(14))
        } footer: {
            Text("The label describes one serving. The amount and unit are used to scale nutrition when you log different quantities.")
                .font(PixelFont.regular(12))
        }
    }

    private var advancedSection: some View {
        Section {
            LabeledContent("Fiber (g)") {
                TextField("—", text: $fiberText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Sugar (g)") {
                TextField("—", text: $sugarText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Sodium (mg)") {
                TextField("—", text: $sodiumText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Advanced (Optional)")
                .font(PixelFont.bold(14))
        }
    }

    private var advancedToggleSection: some View {
        Section {
            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(PixelFont.bold(13))
                        .foregroundColor(tc.primary)
                    Text(showAdvanced ? "Hide Advanced Fields" : "Add Fiber, Sugar, Sodium")
                        .font(PixelFont.regular(16))
                        .foregroundColor(tc.primary)
                }
            }
        }
    }

    // MARK: - Actions

    private func prefill() {
        guard let food = existingFood else { return }
        name = food.name
        caloriesText = "\(food.calories)"
        proteinText = formatDecimal(food.protein)
        carbsText = formatDecimal(food.carbs)
        fatText = formatDecimal(food.fat)
        servingSizeName = food.servingSizeName
        servingSizeAmountText = formatDecimal(food.servingSizeAmount)
        servingUnit = food.servingUnit
        if let fiber = food.fiber { fiberText = formatDecimal(fiber); showAdvanced = true }
        if let sugar = food.sugar { sugarText = formatDecimal(sugar); showAdvanced = true }
        if let sodium = food.sodium { sodiumText = formatDecimal(sodium); showAdvanced = true }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true

        let food = existingFood ?? CustomFood(
            name: name.trimmingCharacters(in: .whitespaces),
            calories: Int(caloriesText) ?? 0,
            protein: Double(proteinText) ?? 0,
            carbs: Double(carbsText) ?? 0,
            fat: Double(fatText) ?? 0
        )

        food.name = name.trimmingCharacters(in: .whitespaces)
        food.calories = Int(caloriesText) ?? 0
        food.protein = Double(proteinText) ?? 0
        food.carbs = Double(carbsText) ?? 0
        food.fat = Double(fatText) ?? 0
        food.servingSizeName = servingSizeName.isEmpty ? "1 serving" : servingSizeName
        food.servingSizeAmount = Double(servingSizeAmountText) ?? 1.0
        food.servingUnit = servingUnit.isEmpty ? "serving" : servingUnit
        food.fiber = Double(fiberText)
        food.sugar = Double(sugarText)
        food.sodium = Double(sodiumText)

        onSave(food)
        isSaving = false
        dismiss()
    }

    private func formatDecimal(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
