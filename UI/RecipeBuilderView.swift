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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }
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

    // Custom ingredient inline form state
    @State private var showingCustomIngredientForm: Bool = false
    @State private var customName: String = ""
    @State private var customCalories: String = ""
    @State private var customProtein: String = ""
    @State private var customCarbs: String = ""
    @State private var customFat: String = ""
    @State private var customServingSize: String = ""
    @State private var saveToMyFoods: Bool = false
    @State private var customFormError: String? = nil

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

    /// Calorie-weighted average purity score across all ingredients (0–100, lower = cleaner).
    private var recipePurityScore: Int {
        guard totalCalories > 0 else { return 0 }
        let weighted = ingredients.reduce(0.0) { $0 + Double($1.calories) * Double($1.toxinScore) }
        return Int(weighted / Double(totalCalories))
    }

    private var purityColor: Color {
        recipePurityScore < 30 ? tc.primary
            : recipePurityScore < 60 ? tc.macroBarCarbs
            : DesignSystem.Colors.danger  // universal red — keep as-is
    }

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
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle(isNew ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(tc.primary)
                    } else {
                        Button("Save") { save() }
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(isValid ? tc.primary : tc.textTertiary)
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
                Text("Recipe Photo")
                    .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                    .foregroundColor(tc.textSecondary)
                Text("Optional — shows as thumbnail in My Recipes")
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(tc.textTertiary)
                if selectedPhoto != nil {
                    Button("Remove") {
                        recipePhotoData = nil
                        selectedPhoto = nil
                        pickerItem = nil
                    }
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
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
                    .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                    .foregroundColor(tc.textSecondary)
                TextField("e.g. Chicken Fried Rice", text: $recipeName)
                    .focused($nameFieldFocused)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                    .foregroundColor(tc.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }

            // Yield
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Servings this makes")
                        .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                        .foregroundColor(tc.textSecondary)
                    HStack {
                        Button {
                            let v = max(1, yieldValue - 1)
                            yieldText = "\(v)"
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(AppFont.regular(28))
                                .foregroundColor(yieldValue <= 1 ? tc.textTertiary : tc.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(yieldValue <= 1)

                        TextField("1", text: $yieldText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(tc.textPrimary)
                            .frame(width: 60)

                        Button {
                            yieldText = "\(yieldValue + 1)"
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(AppFont.regular(28))
                                .foregroundColor(tc.primary)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text("servings")
                            .font(AppFont.regular(DesignSystem.FontSizes.callout))
                            .foregroundColor(tc.textSecondary)

                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
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
                        .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text("\(ingredients.count)")
                        .font(AppFont.regular(DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textTertiary)
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
                AdaptivePillShapeStyle()
                    .fill(DesignSystem.Colors.adaptiveGradientFrom(tc.primaryDark))
                    .frame(width: 36, height: 36)
                    .overlay(AdaptivePillShapeStyle().stroke(tc.primaryDark.adjustedBrightness(-0.2), lineWidth: 2))
                Image(systemName: "leaf.fill")
                    .font(AppFont.bold(14))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.foodName)
                    .font(AppFont.bold(DesignSystem.FontSizes.callout))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)

                let qStr = ingredient.quantity.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(ingredient.quantity))" : String(format: "%.1f", ingredient.quantity)
                Text("\(qStr) \(ingredient.servingUnit) · \(ingredient.calories) cal · P:\(Int(ingredient.protein))g")
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button {
                var updated = ingredients
                updated.remove(at: index)
                withAnimation(.spring(response: 0.3)) { ingredients = updated }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(AppFont.regular(22))
                    .foregroundColor(DesignSystem.Colors.danger.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Add Ingredient Controls

    private var addIngredientButton: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Two-button row
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    withAnimation(.spring(response: 0.3)) { showingCustomIngredientForm = false }
                    showingFoodPicker = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(AppFont.bold(14))
                        Text("Search Foods")
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                    }
                    .foregroundColor(tc.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: tc.primary, fillColor: .clear)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingCustomIngredientForm.toggle()
                        if !showingCustomIngredientForm { resetCustomForm() }
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: showingCustomIngredientForm ? "xmark" : "plus.circle")
                            .font(AppFont.bold(14))
                        Text(showingCustomIngredientForm ? "Cancel" : "Create Custom")
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                    }
                    .foregroundColor(showingCustomIngredientForm ? tc.textSecondary : tc.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: showingCustomIngredientForm ? tc.primary.opacity(0.3) : tc.primary, fillColor: .clear)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Inline custom ingredient form
            if showingCustomIngredientForm {
                customIngredientForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var customIngredientForm: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("New Custom Ingredient")
                .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                .foregroundColor(tc.textSecondary)

            // Name field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Ingredient Name")
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(tc.textTertiary)
                TextField("e.g. Almond Milk", text: $customName)
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(tc.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }

            // Macro grid: 2×2
            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    customNumberField(label: "Calories", placeholder: "0", text: $customCalories)
                    customNumberField(label: "Protein (g)", placeholder: "0", text: $customProtein)
                }
                HStack(spacing: DesignSystem.Spacing.sm) {
                    customNumberField(label: "Carbs (g)", placeholder: "0", text: $customCarbs)
                    customNumberField(label: "Fat (g)", placeholder: "0", text: $customFat)
                }
            }

            // Serving size
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Serving Size")
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(tc.textTertiary)
                TextField("e.g. 1 cup, 100g, 1 scoop", text: $customServingSize)
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(tc.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }

            // Save to My Foods toggle
            Toggle(isOn: $saveToMyFoods) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save to My Foods too?")
                        .font(AppFont.regular(DesignSystem.FontSizes.callout))
                        .foregroundColor(tc.textPrimary)
                    Text("Adds it permanently to your food library")
                        .font(AppFont.regular(DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textSecondary)
                }
            }
            .tint(tc.primary)

            // Error
            if let error = customFormError {
                Text(error)
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.danger)
            }

            AppButton(title: "Add to Recipe", style: .primary) {
                addCustomIngredient()
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primaryDark.opacity(0.25), fillColor: tc.cardBackground)
    }

    private func customNumberField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(AppFont.regular(DesignSystem.FontSizes.caption))
                .foregroundColor(tc.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: DesignSystem.FontSizes.callout))
                .foregroundColor(tc.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
        .frame(maxWidth: .infinity)
    }

    private func addCustomIngredient() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            customFormError = "Ingredient name is required"
            return
        }
        guard let cal = Int(customCalories.replacingOccurrences(of: ",", with: ".")),
              cal >= 0 else {
            customFormError = "Enter a valid calorie value"
            return
        }
        customFormError = nil

        let protein = Double(customProtein.replacingOccurrences(of: ",", with: ".")) ?? 0
        let carbs = Double(customCarbs.replacingOccurrences(of: ",", with: ".")) ?? 0
        let fat = Double(customFat.replacingOccurrences(of: ",", with: ".")) ?? 0
        let servingLabel = customServingSize.trimmingCharacters(in: .whitespaces)

        let component = SavedMealComponent(
            foodName: name,
            quantity: 1,
            servingUnit: servingLabel.isEmpty ? "serving" : servingLabel,
            calories: cal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: 0
        )
        withAnimation(.spring(response: 0.3)) { ingredients.append(component) }

        if saveToMyFoods {
            let customFood = CustomFood(
                name: name,
                calories: cal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                servingSizeName: servingLabel.isEmpty ? "1 serving" : servingLabel,
                servingSizeAmount: 1.0,
                servingUnit: servingLabel.isEmpty ? "serving" : servingLabel
            )
            Task { await dbViewModel.saveCustomFood(customFood, isNew: true) }
        }

        withAnimation(.spring(response: 0.3)) {
            showingCustomIngredientForm = false
            resetCustomForm()
        }
    }

    private func resetCustomForm() {
        customName = ""; customCalories = ""; customProtein = ""
        customCarbs = ""; customFat = ""; customServingSize = ""
        saveToMyFoods = false; customFormError = nil
    }

    // MARK: - Nutrition Panel

    private var nutritionPanel: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Total
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("Whole Recipe")
                    .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                    .foregroundColor(tc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroCell(label: "Total cal", value: "\(totalCalories)", color: tc.macroBarCarbs)
                    macroCell(label: "Protein", value: "\(Int(totalProtein))g", color: tc.macroBarProtein)
                    macroCell(label: "Carbs", value: "\(Int(totalCarbs))g", color: tc.macroBarCarbs)
                    macroCell(label: "Fat", value: "\(Int(totalFat))g", color: tc.macroBarFat)
                }
            }

            Divider().background(tc.primary.opacity(0.3))

            // Per serving
            VStack(spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text("Per Serving")
                        .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text("÷ \(yieldValue) servings")
                        .font(AppFont.regular(DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textTertiary)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroCell(label: "Calories", value: "\(perServingCalories)", color: tc.macroBarCarbs)
                    macroCell(label: "Protein", value: "\(Int(perServingProtein))g", color: tc.macroBarProtein)
                    macroCell(label: "Carbs", value: "\(Int(perServingCarbs))g", color: tc.macroBarCarbs)
                    macroCell(label: "Fat", value: "\(Int(perServingFat))g", color: tc.macroBarFat)
                }
            }

            Divider().background(tc.primary.opacity(0.3))

            // Purity score
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe Purity Score")
                        .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                        .foregroundColor(tc.textSecondary)
                    Text("Calorie-weighted average across all ingredients")
                        .font(AppFont.regular(DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textTertiary)
                }
                Spacer()
                Text("\(recipePurityScore)")
                    .font(AppFont.bold(DesignSystem.FontSizes.title2))
                    .foregroundColor(purityColor)
                Text("/ 100")
                    .font(AppFont.regular(DesignSystem.FontSizes.caption))
                    .foregroundColor(tc.textTertiary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private func macroCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppFont.bold(DesignSystem.FontSizes.callout))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFont.regular(DesignSystem.FontSizes.caption))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .adaptiveCard(borderColor: color.opacity(0.15), fillColor: color.opacity(0.07))
    }

    // MARK: - Save as Food Button

    private var saveAsFoodButton: some View {
        Button {
            saveAsFood()
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: savedAsFood ? "checkmark.circle.fill" : "arrow.down.to.line.circle.fill")
                    .font(AppFont.regular(20))
                VStack(alignment: .leading, spacing: 1) {
                    Text(savedAsFood ? "Saved to My Foods" : "Save Recipe as Food")
                        .font(AppFont.bold(DesignSystem.FontSizes.callout))
                    if !savedAsFood {
                        Text("Adds \(recipeName.isEmpty ? "this recipe" : recipeName) to My Foods (\(perServingCalories) cal/serving)")
                            .font(AppFont.regular(DesignSystem.FontSizes.caption))
                            .opacity(0.8)
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(
                borderColor: savedAsFood ? tc.textTertiary : tc.buttonBorder,
                fillColor: savedAsFood ? tc.textTertiary : .clear,
                fillGradient: savedAsFood
                    ? nil
                    : DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)
            )
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
        recipe.purityScore = recipePurityScore

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
        recipe.purityScore = recipePurityScore

        onSaveAsFood(recipe)
        // Also persist the recipe itself
        onSave(recipe, isNew)
        dismiss()
    }
}
