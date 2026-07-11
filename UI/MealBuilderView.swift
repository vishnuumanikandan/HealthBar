//
//  MealBuilderView.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import SwiftUI
import PhotosUI

/// Full-screen builder for creating and editing saved meal bundles.
///
/// A meal is a named list of food components at saved quantities.
/// Nutrition is always derived by summing component values — never stored
/// independently on the meal itself.
struct MealBuilderView: View {

    // MARK: - Properties

    let dbViewModel: FoodDatabaseViewModel
    let existingMeal: SavedMeal?
    let onSave: (SavedMeal, Bool) -> Void  // (meal, isNew)

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }
    @State private var mealName: String = ""
    @State private var components: [SavedMealComponent] = []
    @State private var showingFoodPicker: Bool = false
    @State private var isSaving: Bool = false
    @FocusState private var nameFieldFocused: Bool

    // Photo picker state
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var mealPhotoData: Data? = nil
    @State private var selectedPhoto: UIImage? = nil
    @State private var showingPhotoPicker: Bool = false

    // MARK: - Computed

    private var isNew: Bool { existingMeal == nil }

    private var isValid: Bool {
        !mealName.trimmingCharacters(in: .whitespaces).isEmpty && !components.isEmpty
    }

    private var totalCalories: Int { components.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { components.reduce(0.0) { $0 + $1.protein } }
    private var totalCarbs: Double { components.reduce(0.0) { $0 + $1.carbs } }
    private var totalFat: Double { components.reduce(0.0) { $0 + $1.fat } }

    /// Calorie-weighted average purity score across all components (0–100, lower = cleaner).
    private var mealPurityScore: Int {
        guard totalCalories > 0 else { return 0 }
        let weighted = components.reduce(0.0) { $0 + Double($1.calories) * Double($1.toxinScore) }
        return Int(weighted / Double(totalCalories))
    }

    private var purityColor: Color {
        mealPurityScore < 30 ? tc.primary
            : mealPurityScore < 60 ? tc.macroBarCarbs
            : DesignSystem.Colors.danger
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    photoSection
                    nameField
                    componentsList
                    addFoodButton
                    if !components.isEmpty { nutritionSummary }
                    Spacer(minLength: 40)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle(isNew ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(tc.primary)
                    } else {
                        Button("Save") { save() }
                            .font(AppFont.bold(16))
                            .foregroundColor(isValid ? tc.primary : tc.textTertiary)
                            .disabled(!isValid)
                    }
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                MiniFoodPickerView(dbViewModel: dbViewModel) { component in
                    components.append(component)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    if let item = newItem,
                       let data = try? await item.loadTransferable(type: Data.self) {
                        mealPhotoData = data
                        selectedPhoto = UIImage(data: data)
                    }
                }
            }
            .onAppear { prefill() }
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Button {
                showingPhotoPicker = true
            } label: {
                ZStack {
                    AdaptiveCardShapeStyle()
                        .fill(tc.cardBackground)
                        .frame(width: 80, height: 80)

                    if let image = selectedPhoto {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(AdaptiveCardShapeStyle())
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(AppFont.bold(22))
                                .foregroundColor(tc.textTertiary)
                            Text("Add Photo")
                                .font(AppFont.regular(10))
                                .foregroundColor(tc.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Meal Photo")
                    .font(AppFont.display(14))
                    .foregroundColor(tc.textSecondary)
                Text("Optional — shows as thumbnail in My Meals")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
                if selectedPhoto != nil {
                    Button("Remove") {
                        mealPhotoData = nil
                        selectedPhoto = nil
                        pickerItem = nil
                    }
                    .font(AppFont.regular(12))
                    .foregroundColor(DesignSystem.Colors.danger)
                }
            }

            Spacer()
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Meal Name")
                .font(AppFont.display(14))
                .foregroundColor(tc.textSecondary)

            TextField("e.g. Pre-Workout Snack", text: $mealName)
                .focused($nameFieldFocused)
                .font(AppFont.regular(DesignSystem.FontSizes.body))
                .foregroundColor(tc.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: tc.primary.opacity(0.15), fillColor: tc.cardBackground)
        }
    }

    // MARK: - Components List

    @ViewBuilder
    private var componentsList: some View {
        if !components.isEmpty {
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Foods")
                        .font(AppFont.display(14))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text("\(components.count) item\(components.count == 1 ? "" : "s")")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textTertiary)
                }

                ForEach(components.indices, id: \.self) { index in
                    componentRow(component: components[index], index: index)
                }
            }
        }
    }

    private func componentRow(component: SavedMealComponent, index: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "fork.knife")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(component.foodName)
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)

                let qtyStr = component.quantity.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(component.quantity))" : String(format: "%.1f", component.quantity)
                Text("\(qtyStr) \(component.servingUnit) · \(component.calories) cal")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button {
                var updated = components
                updated.remove(at: index)
                withAnimation(.spring(response: 0.3)) { components = updated }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(AppFont.regular(22))
                    .foregroundColor(DesignSystem.Colors.danger.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.15), fillColor: tc.cardBackground)
    }

    // MARK: - Add Food Button

    private var addFoodButton: some View {
        Button {
            showingFoodPicker = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "plus")
                    .font(AppFont.bold(15))
                Text("Add Food")
                    .font(AppFont.bold(16))
            }
            .foregroundColor(tc.primary)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primaryBackground, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Nutrition Summary

    private var nutritionSummary: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Meal Total")
                    .font(AppFont.display(14))
                    .foregroundColor(tc.textSecondary)
                Spacer()
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                macroChip(value: "\(totalCalories)", label: "cal", color: tc.macroBarCarbs)
                macroChip(value: String(format: "%.0fg", totalProtein), label: "Protein", color: tc.macroBarProtein)
                macroChip(value: String(format: "%.0fg", totalCarbs), label: "Carbs", color: tc.macroBarCarbs)
                macroChip(value: String(format: "%.0fg", totalFat), label: "Fat", color: tc.macroBarFat)
            }

            // Purity score row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meal Purity Score")
                        .font(AppFont.display(14))
                        .foregroundColor(tc.textSecondary)
                    Text("Calorie-weighted average")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textTertiary)
                }
                Spacer()
                Text("\(mealPurityScore)")
                    .font(AppFont.display(22))
                    .foregroundColor(purityColor)
                Text("/ 100")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.top, DesignSystem.Spacing.xs)
        }
    }

    private func macroChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppFont.display(16))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: color.opacity(0.2), fillColor: color.opacity(0.08))
    }

    // MARK: - Actions

    private func prefill() {
        guard let meal = existingMeal else { return }
        mealName = meal.name
        components = meal.components
        if let data = meal.photoData {
            mealPhotoData = data
            selectedPhoto = UIImage(data: data)
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true

        let meal = existingMeal ?? SavedMeal(name: mealName)
        meal.name = mealName.trimmingCharacters(in: .whitespaces)
        meal.components = components
        meal.photoData = mealPhotoData

        onSave(meal, isNew)
        isSaving = false
        dismiss()
    }
}
