//
//  ServingSizePickerSheet.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import SwiftUI

/// Sheet for adjusting quantity before logging a food.
///
/// Every path that results in logging a food must pass through here.
/// Shows the food's base nutrition and a live-scaling preview as the
/// user adjusts the quantity.
struct ServingSizePickerSheet: View {

    // MARK: - Properties

    let food: LoggableFood
    let mealType: MealType
    let date: Date
    let onConfirm: (LoggableFood, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared

    @State private var quantityText: String
    @State private var quantity: Double

    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Init

    init(food: LoggableFood, mealType: MealType, date: Date, onConfirm: @escaping (LoggableFood, Double) -> Void) {
        self.food = food
        self.mealType = mealType
        self.date = date
        self.onConfirm = onConfirm
        let defaultQ = food.baseAmount
        self._quantity = State(initialValue: defaultQ)
        self._quantityText = State(initialValue: ServingSizePickerSheet.formatQuantity(defaultQ))
    }

    // MARK: - Computed

    private var scaled: (calories: Int, protein: Double, carbs: Double, fat: Double) {
        food.scaled(to: quantity)
    }

    private var isValid: Bool { quantity > 0 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    foodHeader
                    servingControl
                    nutritionPreview
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle("Serving Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm(food, quantity)
                        dismiss()
                    }
                    .font(AppFont.bold(16))
                    .foregroundColor(isValid ? tc.primary : tc.textTertiary)
                    .disabled(!isValid)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Food Header

    private var foodHeader: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "fork.knife")
                    .font(AppFont.regular(24))
                    .foregroundColor(tc.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(AppFont.bold(17))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(2)

                Text("Base: \(food.servingDescription) = \(food.caloriesPerBase) cal")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }

    // MARK: - Serving Control

    private var servingControl: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("Quantity")
                .font(AppFont.display(14))
                .foregroundColor(tc.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignSystem.Spacing.md) {
                // Decrement
                Button {
                    let step = stepSize
                    let newVal = max(step, quantity - step)
                    quantity = newVal
                    quantityText = Self.formatQuantity(newVal)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(AppFont.regular(32))
                        .foregroundColor(quantity <= 0.01 ? tc.textTertiary : tc.primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(quantity <= 0.01)

                // Quantity field
                VStack(spacing: 2) {
                    TextField("Qty", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(AppFont.display(28))
                        .foregroundColor(tc.textPrimary)
                        .frame(width: 100)
                        .onChange(of: quantityText) { _, newValue in
                            if let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")), parsed > 0 {
                                quantity = parsed
                            }
                        }

                    Text(food.unit)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                // Increment
                Button {
                    let step = stepSize
                    let newVal = quantity + step
                    quantity = newVal
                    quantityText = Self.formatQuantity(newVal)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.regular(32))
                        .foregroundColor(tc.primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
        }
    }

    // MARK: - Nutrition Preview

    private var nutritionPreview: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Nutrition Preview")
                    .font(AppFont.display(14))
                    .foregroundColor(tc.textSecondary)
                Spacer()
                Text(quantityText.isEmpty ? "—" : "\(quantityText) \(food.unit)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                nutritionCell(label: "Calories", value: "\(scaled.calories)", unit: "kcal", color: tc.macroBarCarbs)
                nutritionCell(label: "Protein", value: String(format: "%.1f", scaled.protein), unit: "g", color: tc.primary)
                nutritionCell(label: "Carbs", value: String(format: "%.1f", scaled.carbs), unit: "g", color: tc.macroBarCarbs)
                nutritionCell(label: "Fat", value: String(format: "%.1f", scaled.fat), unit: "g", color: tc.macroBarFat)
            }
        }
    }

    private func nutritionCell(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppFont.display(20))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(AppFont.regular(10))
                .foregroundColor(color.opacity(0.8))
            Text(label)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: color.opacity(0.2), fillColor: color.opacity(0.08))
    }

    // MARK: - Helpers

    /// The step size for +/- buttons (1 for whole-unit foods, 10 for gram-based)
    private var stepSize: Double {
        if food.unit == "g" || food.unit == "ml" {
            return 10.0
        }
        return 1.0
    }

    private static func formatQuantity(_ val: Double) -> String {
        if val.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(val))
        }
        return String(format: "%.1f", val)
    }
}
