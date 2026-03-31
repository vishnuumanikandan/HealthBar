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
        mealPurityScore < 30 ? DesignSystem.Colors.primary
            : mealPurityScore < 60 ? DesignSystem.Colors.energy
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
            .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle(isNew ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(DesignSystem.Colors.primary)
                    } else {
                        Button("Save") { save() }
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(isValid ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
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
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.cardBackground)
                        .frame(width: 80, height: 80)

                    if let image = selectedPhoto {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("Add Photo")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Meal Photo")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("Optional — shows as thumbnail in My Meals")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                if selectedPhoto != nil {
                    Button("Remove") {
                        mealPhotoData = nil
                        selectedPhoto = nil
                        pickerItem = nil
                    }
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
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
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            TextField("e.g. Pre-Workout Snack", text: $mealName)
                .focused($nameFieldFocused)
                .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    // MARK: - Components List

    @ViewBuilder
    private var componentsList: some View {
        if !components.isEmpty {
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Foods")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text("\(components.count) item\(components.count == 1 ? "" : "s")")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
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
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(component.foodName)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                let qtyStr = component.quantity.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(component.quantity))" : String(format: "%.1f", component.quantity)
                Text("\(qtyStr) \(component.servingUnit) · \(component.calories) cal")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                var updated = components
                updated.remove(at: index)
                withAnimation(.spring(response: 0.3)) { components = updated }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(DesignSystem.Colors.danger.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    // MARK: - Add Food Button

    private var addFoodButton: some View {
        Button {
            showingFoodPicker = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add Food")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
            }
            .foregroundColor(DesignSystem.Colors.primary)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.primary, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Nutrition Summary

    private var nutritionSummary: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Meal Total")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                macroChip(value: "\(totalCalories)", label: "cal", color: DesignSystem.Colors.energy)
                macroChip(value: String(format: "%.0fg", totalProtein), label: "Protein", color: DesignSystem.Colors.primary)
                macroChip(value: String(format: "%.0fg", totalCarbs), label: "Carbs", color: .orange)
                macroChip(value: String(format: "%.0fg", totalFat), label: "Fat", color: .purple)
            }

            // Purity score row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meal Purity Score")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("Calorie-weighted average")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer()
                Text("\(mealPurityScore)")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                    .foregroundColor(purityColor)
                Text("/ 100")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(.top, DesignSystem.Spacing.xs)
        }
    }

    private func macroChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
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
