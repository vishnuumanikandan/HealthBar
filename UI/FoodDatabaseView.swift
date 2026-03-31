//
//  FoodDatabaseView.swift
//  HealthBar
//
//  Created by Claude on 3/27/26.
//

import SwiftUI

/// Full-screen food database with 5 functional tabs.
///
/// Tabs:
/// - All Foods: searchable ~150 built-in ingredient library
/// - My Foods: user-created custom food entries
/// - My Meals: reusable meal bundles (log all at once)
/// - Saved Foods: favorited FoodEntries for quick re-log
/// - My Recipes: recipes with yield-based per-serving nutrition
struct FoodDatabaseView: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: FoodDatabaseTab = .allFoods
    @State private var dbViewModel: FoodDatabaseViewModel

    init(viewModel: FoodLogViewModel) {
        self._viewModel = Bindable(viewModel)
        self._dbViewModel = State(initialValue: FoodDatabaseViewModel(coordinator: viewModel.coordinator))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                tabDescription
                tabContent
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Food Database")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .sheet(isPresented: $dbViewModel.showingServingSizePicker) {
                if let food = dbViewModel.pendingLogFood {
                    ServingSizePickerSheet(
                        food: food,
                        mealType: viewModel.pendingMealType,
                        date: viewModel.selectedDate
                    ) { loggedFood, quantity in
                        Task {
                            await dbViewModel.confirmLog(
                                food: loggedFood,
                                quantity: quantity,
                                date: viewModel.selectedDate,
                                mealType: viewModel.pendingMealType
                            )
                            await viewModel.loadTodaysData()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $dbViewModel.showingAddCustomFood) {
                AddCustomFoodView(existingFood: dbViewModel.editingCustomFood) { food in
                    Task { await dbViewModel.saveCustomFood(food, isNew: dbViewModel.editingCustomFood == nil) }
                }
                .onDisappear { dbViewModel.editingCustomFood = nil }
            }
            .sheet(isPresented: $dbViewModel.showingMealBuilder) {
                MealBuilderView(
                    dbViewModel: dbViewModel,
                    existingMeal: dbViewModel.editingMeal
                ) { meal, isNew in
                    Task { await dbViewModel.saveMeal(meal, isNew: isNew) }
                }
                .onDisappear { dbViewModel.editingMeal = nil }
            }
            .sheet(isPresented: $dbViewModel.showingRecipeBuilder) {
                RecipeBuilderView(
                    dbViewModel: dbViewModel,
                    existingRecipe: dbViewModel.editingRecipe,
                    onSave: { recipe, isNew in
                        Task { await dbViewModel.saveRecipe(recipe, isNew: isNew) }
                    },
                    onSaveAsFood: { recipe in
                        Task { await dbViewModel.saveRecipeAsFood(recipe) }
                    }
                )
                .onDisappear { dbViewModel.editingRecipe = nil }
            }
            .overlay(toastOverlay)
            .task { await dbViewModel.loadAll() }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(FoodDatabaseTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? DesignSystem.Colors.primary : Color(.systemGray5))
                            .foregroundStyle(isSelected ? Color.white : DesignSystem.Colors.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .frame(height: 52)
        .background(DesignSystem.Colors.cardBackground)
    }

    // MARK: - Tab Description

    private var tabDescription: some View {
        Text(selectedTab.description)
            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.primaryBackground)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .allFoods:
            AllFoodsTab(dbViewModel: dbViewModel)
                .transition(.opacity)
        case .myFoods:
            MyFoodsTab(dbViewModel: dbViewModel, logViewModel: viewModel, onDismiss: { dismiss() })
                .transition(.opacity)
        case .myMeals:
            MyMealsTab(dbViewModel: dbViewModel, logViewModel: viewModel) { dismiss() }
                .transition(.opacity)
        case .savedFoods:
            SavedFoodsTab(dbViewModel: dbViewModel, logViewModel: viewModel)
                .transition(.opacity)
        case .myRecipes:
            MyRecipesTab(dbViewModel: dbViewModel)
                .transition(.opacity)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if dbViewModel.showToast, let message = dbViewModel.toastMessage {
            VStack {
                Spacer()
                Text(message)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.primary)
                    .clipShape(Capsule())
                    .padding(.bottom, DesignSystem.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.4), value: dbViewModel.showToast)
        }
    }
}

// MARK: - All Foods Tab

private struct AllFoodsTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel

    var body: some View {
        if dbViewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if dbViewModel.filteredBuiltInFoods.isEmpty && !dbViewModel.allFoodsSearchText.isEmpty {
            // No results but searching — show hint
            VStack {
                Spacer()
                VStack(spacing: DesignSystem.Spacing.md) {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No foods found",
                        message: "Try a different search term.",
                        actionTitle: nil,
                        action: nil
                    )
                    Button {
                        dbViewModel.editingCustomFood = nil
                        dbViewModel.showingAddCustomFood = true
                    } label: {
                        Label("Add \"\(dbViewModel.allFoodsSearchText)\" as Custom Food", systemImage: "plus")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.primary, DesignSystem.Colors.growth],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
                Spacer()
            }
        } else {
            List {
                // Fix #3: "Can't find it?" CTA at the top of All Foods
                Section {
                    Button {
                        dbViewModel.editingCustomFood = nil
                        dbViewModel.showingAddCustomFood = true
                    } label: {
                        Label("Can't find it? Add your own", systemImage: "plus.circle.fill")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.primary, DesignSystem.Colors.growth],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.filteredBuiltInFoods) { food in
                        BuiltInFoodRow(food: food) {
                            dbViewModel.beginLog(builtIn: food)
                        }
                        .listRowBackground(DesignSystem.Colors.cardBackground)
                        .listRowSeparatorTint(DesignSystem.Colors.border)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $dbViewModel.allFoodsSearchText, prompt: "Search ingredients…")
        }
    }
}

// MARK: - My Foods Tab

private struct MyFoodsTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel
    let logViewModel: FoodLogViewModel
    let onDismiss: () -> Void

    var body: some View {
        if dbViewModel.filteredCustomFoods.isEmpty && dbViewModel.myFoodsSearchText.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(
                    icon: "fork.knife",
                    title: "No custom foods yet",
                    message: "Add foods you eat regularly that aren't in the built-in database.",
                    actionTitle: "Add Food",
                    action: { openAddFoodForm() }
                )
                .padding(DesignSystem.Spacing.lg)
                Spacer()
            }
        } else {
            List {
                Section {
                    Button {
                        openAddFoodForm()
                    } label: {
                        Label("Add New Food", systemImage: "plus")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.primary, DesignSystem.Colors.growth],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.filteredCustomFoods) { food in
                        CustomFoodRow(food: food) {
                            dbViewModel.beginLog(custom: food)
                        } onEdit: {
                            dbViewModel.editingCustomFood = food
                            dbViewModel.showingAddCustomFood = true
                        } onDelete: {
                            Task { await dbViewModel.deleteCustomFood(food) }
                        }
                        .listRowBackground(DesignSystem.Colors.cardBackground)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $dbViewModel.myFoodsSearchText, prompt: "Search my foods…")
        }
    }

    private func openAddFoodForm() {
        logViewModel.pendingSaveToMyFoods = true
        logViewModel.openAddFoodFormAfterDelay()
        onDismiss()
    }
}

// MARK: - My Meals Tab

private struct MyMealsTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel
    let logViewModel: FoodLogViewModel
    let onLogged: () -> Void

    var body: some View {
        if dbViewModel.savedMeals.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(
                    icon: "rectangle.stack.fill",
                    title: "No saved meals yet",
                    message: "Save groups of foods as a meal template to log them together quickly.",
                    actionTitle: "Create Meal",
                    action: { dbViewModel.showingMealBuilder = true }
                )
                .padding(DesignSystem.Spacing.lg)
                Spacer()
            }
        } else {
            List {
                Section {
                    Button {
                        dbViewModel.editingMeal = nil
                        dbViewModel.showingMealBuilder = true
                    } label: {
                        Label("New Meal Bundle", systemImage: "plus")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, DesignSystem.Colors.energy],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.savedMeals) { meal in
                        SavedMealRow(meal: meal) {
                            Task {
                                await dbViewModel.logMeal(
                                    meal,
                                    date: logViewModel.selectedDate,
                                    mealType: logViewModel.pendingMealType
                                )
                                await logViewModel.loadTodaysData()
                                onLogged()
                            }
                        } onEdit: {
                            dbViewModel.editingMeal = meal
                            dbViewModel.showingMealBuilder = true
                        } onDelete: {
                            Task { await dbViewModel.deleteSavedMeal(meal) }
                        }
                        .listRowBackground(DesignSystem.Colors.cardBackground)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Saved Foods Tab

private struct SavedFoodsTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel
    let logViewModel: FoodLogViewModel

    var body: some View {
        if logViewModel.favoriteFoods.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(
                    icon: "star",
                    title: "No saved foods yet",
                    message: "Tap the star on any food entry to save it here for quick access.",
                    actionTitle: nil,
                    action: nil
                )
                .padding(DesignSystem.Spacing.lg)
                Spacer()
            }
        } else {
            List(logViewModel.favoriteFoods, id: \.id) { entry in
                SavedFoodEntryRow(entry: entry) {
                    dbViewModel.beginLog(entry: entry)
                }
                .listRowBackground(DesignSystem.Colors.cardBackground)
                .listRowSeparatorTint(DesignSystem.Colors.border)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - My Recipes Tab

private struct MyRecipesTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel

    var body: some View {
        if dbViewModel.savedRecipes.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(
                    icon: "list.bullet.rectangle.fill",
                    title: "No recipes yet",
                    message: "Build recipes with ingredients, set the yield, and save per-serving nutrition to My Foods.",
                    actionTitle: "Create Recipe",
                    action: { dbViewModel.showingRecipeBuilder = true }
                )
                .padding(DesignSystem.Spacing.lg)
                Spacer()
            }
        } else {
            List {
                Section {
                    Button {
                        dbViewModel.editingRecipe = nil
                        dbViewModel.showingRecipeBuilder = true
                    } label: {
                        Label("New Recipe", systemImage: "plus")
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [Color.teal, DesignSystem.Colors.growth],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.savedRecipes) { recipe in
                        SavedRecipeRow(recipe: recipe) {
                            // Log directly to the food log (opens serving size picker)
                            dbViewModel.beginLog(recipe: recipe)
                        } onSaveAsFood: {
                            Task { await dbViewModel.saveRecipeAsFood(recipe) }
                        } onEdit: {
                            dbViewModel.editingRecipe = recipe
                            dbViewModel.showingRecipeBuilder = true
                        } onDelete: {
                            Task { await dbViewModel.deleteRecipe(recipe) }
                        }
                        .listRowBackground(DesignSystem.Colors.cardBackground)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Row Views

private struct BuiltInFoodRow: View {

    let food: BuiltInFood
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(DesignSystem.Colors.growth.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.growth)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(food.calories) cal · \(food.servingDescription)")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

private struct CustomFoodRow: View {

    let food: CustomFood
    let onLog: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(Color(.systemIndigo).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(.systemIndigo))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(food.calories) cal · \(food.servingSizeName)")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

private struct SavedMealRow: View {

    let meal: SavedMeal
    let onLog: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail or icon
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                if let data = meal.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.orange)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text({
                    let count = meal.components.count
                    let totalCal = meal.totalCalories
                    let purity: Int = {
                        guard totalCal > 0 else { return 0 }
                        let w = meal.components.reduce(0.0) { $0 + Double($1.calories) * Double($1.toxinScore) }
                        return Int(w / Double(totalCal))
                    }()
                    return "\(totalCal) cal · \(count) item\(count == 1 ? "" : "s") · Purity \(purity)"
                }())
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

private struct SavedFoodEntryRow: View {

    let entry: FoodEntry
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 40, height: 40)

                if let photoData = entry.photoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                } else {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.yellow)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(entry.calories) cal  ·  P:\(Int(entry.protein))g  C:\(Int(entry.carbs))g  F:\(Int(entry.fat))g")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

private struct SavedRecipeRow: View {

    let recipe: SavedRecipe
    let onLog: () -> Void          // Log directly to the food log
    let onSaveAsFood: () -> Void   // Save per-serving as a My Foods entry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail or icon
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 40, height: 40)
                if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                } else {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.teal)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(recipe.perServingCalories) cal/serving · \(recipe.yield) serving\(recipe.yield == 1 ? "" : "s") · Purity \(recipe.purityScore)")
                    .font(.system(size: DesignSystem.FontSizes.caption))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Primary: log directly to food log
            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Save to My Foods via leading swipe
            Button(action: onSaveAsFood) {
                Label("Save to My Foods", systemImage: "arrow.down.to.line")
            }
            .tint(DesignSystem.Colors.growth)
        }
    }
}

// MARK: - Tab Enum

enum FoodDatabaseTab: String, CaseIterable {
    case allFoods = "All Foods"
    case myFoods = "My Foods"
    case myMeals = "My Meals"
    case savedFoods = "Saved Foods"
    case myRecipes = "My Recipes"

    var description: String {
        switch self {
        case .allFoods:   return "Search our built-in ingredient library"
        case .myFoods:    return "Foods you've created or scanned"
        case .myMeals:    return "Saved bundles to log in one tap"
        case .savedFoods: return "Starred entries for quick re-logging"
        case .myRecipes:  return "Recipes with per-serving nutrition"
        }
    }
}
