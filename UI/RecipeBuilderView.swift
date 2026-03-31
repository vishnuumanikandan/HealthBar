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
        recipePurityScore < 30 ? DesignSystem.Colors.primary
            : recipePurityScore < 60 ? DesignSystem.Colors.energy
            : DesignSystem.Colors.danger
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
                            .font(.system(size: 14, weight: .semibold))
                        Text("Search Foods")
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

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingCustomIngredientForm.toggle()
                        if !showingCustomIngredientForm { resetCustomForm() }
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: showingCustomIngredientForm ? "xmark" : "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(showingCustomIngredientForm ? "Cancel" : "Create Custom")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    }
                    .foregroundColor(showingCustomIngredientForm ? DesignSystem.Colors.textSecondary : Color(.systemIndigo))
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(showingCustomIngredientForm ? DesignSystem.Colors.border : Color(.systemIndigo), lineWidth: 1.5)
                    )
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
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Name field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Ingredient Name")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                TextField("e.g. Almond Milk", text: $customName)
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
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
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                TextField("e.g. 1 cup, 100g, 1 scoop", text: $customServingSize)
                    .font(.system(size: DesignSystem.FontSizes.callout))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
            }

            // Save to My Foods toggle
            Toggle(isOn: $saveToMyFoods) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save to My Foods too?")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("Adds it permanently to your food library")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .tint(DesignSystem.Colors.primary)

            // Error
            if let error = customFormError {
                Text(error)
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.danger)
            }

            AppButton(title: "Add to Recipe", style: .primary) {
                addCustomIngredient()
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(Color(.systemIndigo).opacity(0.25), lineWidth: 1)
        )
    }

    private func customNumberField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .font(.system(size: DesignSystem.FontSizes.callout))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
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

            Divider().background(DesignSystem.Colors.border)

            // Purity score
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe Purity Score")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("Calorie-weighted average across all ingredients")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                Spacer()
                Text("\(recipePurityScore)")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                    .foregroundColor(purityColor)
                Text("/ 100")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
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
