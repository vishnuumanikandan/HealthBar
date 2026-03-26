//
//  RecipeBuilderView.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import SwiftUI
import PhotosUI

/// Full-screen builder for creating and editing saved recipes.
///
/// A recipe combines ingredients with a yield (number of servings).
/// The per-serving nutrition is shown live. Pressing "Save Recipe as Food"
/// creates a new entry in My Foods with the per-serving values.
struct RecipeBuilderView: View {

    // MARK: - Properties

    let dbViewModel: FoodDatabaseViewModel
    let existingRecipe: SavedRecipe?
    let onSave: (SavedRecipe, Bool) -> Void  // (recipe, isNew)
    let onSaveAsFood: (SavedRecipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipeName: String = ""
    @State private var yieldText: String = "1"
    @State private var ingredients: [SavedMealComponent] = []
    @State private var showingFoodPicker: Bool = false
    @State private var isSaving: Bool = false
    @State private var savedAsFood: Bool = false   // Fix #3: prevent double-press
    @FocusState private var nameFieldFocused: Bool

    // Photo picker state
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var recipePhotoData: Data? = nil
    @State private var selectedPhoto: UIImage? = nil
    @State private var showingPhotoPicker: Bool = false

    // MARK: - Computed

    private var isNew: Bool { existingRecipe == nil }

    private var yieldValue: Int { Int(yieldText) ?? 1 }

    private var isValid: Bool {
        !recipeName.trimmingCharacters(in: .whitespaces).isEmpty
            && !ingredients.isEmpty
            && yieldValue >= 1
    }

    private var totalCalories: Int { ingredients.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Double { ingredients.reduce(0.0) { $0 + $1.protein } }
    private var totalCarbs: Double { ingredients.reduce(0.0) { $0 + $1.carbs } }
    private var totalFat: Double { ingredients.reduce(0.0) { $0 + $1.fat } }

    private var perServingCalories: Int { yieldValue > 0 ? Int(Double(totalCalories) / Double(yieldValue)) : 0 }
    private var perServingProtein: Double { yieldValue > 0 ? totalProtein / Double(yieldValue) : 0 }
    private var perServingCarbs: Double { yieldValue > 0 ? totalCarbs / Double(yieldValue) : 0 }
    private var perServingFat: Double { yieldValue > 0 ? totalFat / Double(yieldValue) : 0 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    recipePhotoSection
                    nameAndYieldSection
                    ingredientsList
                    addIngredientButton
                    if !ingredients.isEmpty {
                        nutritionPanel
                        saveAsFoodButton
                    }
                    Spacer(minLength: 40)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle(isNew ? "New Recipe" : "Edit Recipe")
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
                    ingredients.append(component)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    if let item = newItem,
                       let data = try? await item.loadTransferable(type: Data.self) {
                        recipePhotoData = data
                        selectedPhoto = UIImage(data: data)
                    }
                }
            }
            .onAppear { prefill(); savedAsFood = false }
        }
    }

    // MARK: - Recipe Photo Section

    private var recipePhotoSection: some View {
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
                Text("Recipe Photo")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text("Optional — shows as thumbnail in My Recipes")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                if selectedPhoto != nil {
                    Button("Remove") {
                        recipePhotoData = nil
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

    // MARK: - Name + Yield

    private var nameAndYieldSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Name
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Recipe Name")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                TextField("e.g. Chicken Fried Rice", text: $recipeName)
                    .focused($nameFieldFocused)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            }

            // Yield
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Servings this makes")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    HStack {
                        Button {
                            let v = max(1, yieldValue - 1)
                            yieldText = "\(v)"
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(yieldValue <= 1 ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(yieldValue <= 1)

                        TextField("1", text: $yieldText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(width: 60)

                        Button {
                            yieldText = "\(yieldValue + 1)"
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("servings")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }
            }
        }
    }

    // MARK: - Ingredients List

    @ViewBuilder
    private var ingredientsList: some View {
        if !ingredients.isEmpty {
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Ingredients")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text("\(ingredients.count)")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }

                ForEach(ingredients.indices, id: \.self) { index in
                    ingredientRow(ingredient: ingredients[index], index: index)
                }
            }
        }
    }

    private func ingredientRow(ingredient: SavedMealComponent, index: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.growth.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.growth)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.foodName)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                let qStr = ingredient.quantity.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(ingredient.quantity))" : String(format: "%.1f", ingredient.quantity)
                Text("\(qStr) \(ingredient.servingUnit) · \(ingredient.calories) cal · P:\(Int(ingredient.protein))g")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                var updated = ingredients
                updated.remove(at: index)
                withAnimation(.spring(response: 0.3)) { ingredients = updated }
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

    // MARK: - Add Ingredient Button

    private var addIngredientButton: some View {
        Button {
            showingFoodPicker = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add Ingredient")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
            }
            .foregroundColor(DesignSystem.Colors.growth)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.growth, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Nutrition Panel

    private var nutritionPanel: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Total
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Whole Recipe")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroCell(label: "Total cal", value: "\(totalCalories)", color: DesignSystem.Colors.energy)
                    macroCell(label: "Protein", value: "\(Int(totalProtein))g", color: DesignSystem.Colors.primary)
                    macroCell(label: "Carbs", value: "\(Int(totalCarbs))g", color: .orange)
                    macroCell(label: "Fat", value: "\(Int(totalFat))g", color: .purple)
                }
            }

            Divider().background(DesignSystem.Colors.border)

            // Per serving
            VStack(spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text("Per Serving")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text("÷ \(yieldValue) servings")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroCell(label: "Calories", value: "\(perServingCalories)", color: DesignSystem.Colors.energy)
                    macroCell(label: "Protein", value: "\(Int(perServingProtein))g", color: DesignSystem.Colors.primary)
                    macroCell(label: "Carbs", value: "\(Int(perServingCarbs))g", color: .orange)
                    macroCell(label: "Fat", value: "\(Int(perServingFat))g", color: .purple)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    private func macroCell(label: String, value: String, color: Color) -> some View {
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
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
    }

    // MARK: - Save as Food Button

    private var saveAsFoodButton: some View {
        Button {
            saveAsFood()
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: savedAsFood ? "checkmark.circle.fill" : "arrow.down.to.line.circle.fill")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text(savedAsFood ? "Saved to My Foods ✓" : "Save Recipe as Food")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    if !savedAsFood {
                        Text("Adds \(recipeName.isEmpty ? "this recipe" : recipeName) to My Foods (\(perServingCalories) cal/serving)")
                            .font(.system(size: DesignSystem.FontSizes.caption))
                            .opacity(0.8)
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .background(
                savedAsFood
                    ? AnyShapeStyle(Color(.systemGray3))
                    : AnyShapeStyle(LinearGradient(
                        colors: [DesignSystem.Colors.primary, DesignSystem.Colors.growth],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isValid || savedAsFood)   // Fix #3: disable after first press
    }

    // MARK: - Actions

    private func prefill() {
        guard let recipe = existingRecipe else { return }
        recipeName = recipe.name
        yieldText = "\(recipe.yield)"
        ingredients = recipe.ingredients
        if let data = recipe.photoData {
            recipePhotoData = data
            selectedPhoto = UIImage(data: data)
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true

        let recipe = existingRecipe ?? SavedRecipe(name: recipeName)
        recipe.name = recipeName.trimmingCharacters(in: .whitespaces)
        recipe.yield = max(1, yieldValue)
        recipe.ingredients = ingredients
        recipe.photoData = recipePhotoData

        onSave(recipe, isNew)
        isSaving = false
        dismiss()
    }

    private func saveAsFood() {
        guard isValid, !savedAsFood else { return }
        savedAsFood = true   // Fix #3: lock button immediately

        let recipe = existingRecipe ?? SavedRecipe(name: recipeName)
        recipe.name = recipeName.trimmingCharacters(in: .whitespaces)
        recipe.yield = max(1, yieldValue)
        recipe.ingredients = ingredients
        recipe.photoData = recipePhotoData

        onSaveAsFood(recipe)
        // Also persist the recipe itself
        onSave(recipe, isNew)
        dismiss()
    }
}
