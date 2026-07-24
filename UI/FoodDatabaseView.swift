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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

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
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Food Database")
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(AppFont.regular(DesignSystem.FontSizes.callout))
                        .foregroundColor(tc.primary)
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
                            // TUT-1b databaseLog detection (Decision 4/5) — after confirmLog's
                            // await returns. `confirmLog` swallows its own error (Void return), so
                            // the await returning is the only success signal available here without
                            // modifying FoodDatabaseViewModel (which the plan forbids).
                            if TutorialProgress.shared.shouldAttempt(TutorialCatalog.databaseLogId) {
                                Task { _ = try? await viewModel.coordinator.completeTutorialStep(TutorialCatalog.databaseLogId) }
                            }
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
                            .font(AppFont.bold(DesignSystem.FontSizes.footnote))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? DesignSystem.Erewhon.onAccent : tc.textSecondary)
                            .adaptivePill(
                                borderColor: isSelected ? tc.primary : DesignSystem.Erewhon.line,
                                fillColor: isSelected ? tc.primary : tc.cardBackground,
                                isSelected: isSelected
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .frame(height: 52)
        .background(tc.cardBackground)
    }

    // MARK: - Tab Description

    private var tabDescription: some View {
        Text(selectedTab.description)
            .font(AppFont.regular(DesignSystem.FontSizes.footnote))
            .foregroundColor(tc.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(tc.primaryBackground)
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
                    .font(AppFont.bold(DesignSystem.FontSizes.callout))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .adaptivePill(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

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
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Erewhon.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
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
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Erewhon.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
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
                        .listRowBackground(tc.cardBackground)
                        .listRowSeparatorTint(tc.primary.opacity(0.3))
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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

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
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Erewhon.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
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
                        .listRowBackground(tc.cardBackground)
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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        mealsContent
    }

    @ViewBuilder
    private var mealsContent: some View {
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
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Erewhon.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.savedMeals) { meal in
                        SavedMealRow(
                            meal: meal,
                            onLog: {
                                Task {
                                    await dbViewModel.logMeal(
                                        meal,
                                        date: logViewModel.selectedDate,
                                        mealType: logViewModel.pendingMealType
                                    )
                                    await logViewModel.loadTodaysData()
                                    onLogged()
                                }
                            },
                            onEdit: {
                                dbViewModel.editingMeal = meal
                                dbViewModel.showingMealBuilder = true
                            },
                            onDelete: {
                                Task { await dbViewModel.deleteSavedMeal(meal) }
                            }
                        )
                        .listRowBackground(tc.cardBackground)
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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

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
                .listRowBackground(tc.cardBackground)
                .listRowSeparatorTint(tc.primary.opacity(0.3))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - My Recipes Tab

private struct MyRecipesTab: View {

    @Bindable var dbViewModel: FoodDatabaseViewModel
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        recipesContent
    }

    @ViewBuilder
    private var recipesContent: some View {
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
                            .font(AppFont.bold(DesignSystem.FontSizes.callout))
                            .foregroundColor(DesignSystem.Erewhon.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                Section {
                    ForEach(dbViewModel.savedRecipes) { recipe in
                        SavedRecipeRow(
                            recipe: recipe,
                            onLog: {
                                // Log directly to the food log (opens serving size picker)
                                dbViewModel.beginLog(recipe: recipe)
                            },
                            onSaveAsFood: {
                                Task { await dbViewModel.saveRecipeAsFood(recipe) }
                            },
                            onEdit: {
                                dbViewModel.editingRecipe = recipe
                                dbViewModel.showingRecipeBuilder = true
                            },
                            onDelete: {
                                Task { await dbViewModel.deleteRecipe(recipe) }
                            }
                        )
                        .listRowBackground(tc.cardBackground)
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
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                Text("\(food.calories) cal · \(food.servingDescription)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.regular(28))
                    .foregroundColor(tc.primary)
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
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                Text("\(food.calories) cal · \(food.servingSizeName)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.regular(28))
                    .foregroundColor(tc.primary)
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
            .tint(tc.primary)
        }
    }
}

private struct SavedMealRow: View {

    let meal: SavedMeal
    let onLog: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail or icon
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.iconAmber.mid.opacity(0.15))
                    .frame(width: 40, height: 40)
                if let data = meal.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(AdaptiveCardShapeStyle())
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(AppFont.bold(15))
                        .foregroundColor(tc.iconAmber.mid)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textPrimary)
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
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.regular(28))
                    .foregroundColor(tc.primary)
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
            .tint(tc.primary)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct SavedFoodEntryRow: View {

    let entry: FoodEntry
    let onLog: () -> Void
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.primary.opacity(0.1))
                    .frame(width: 40, height: 40)

                if let photoData = entry.photoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(AdaptiveCardShapeStyle())
                } else {
                    Image(systemName: "star.fill")
                        .font(AppFont.bold(16))
                        .foregroundColor(.yellow)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                Text("\(entry.calories) cal  ·  P:\(Int(entry.protein))g  C:\(Int(entry.carbs))g  F:\(Int(entry.fat))g")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.regular(28))
                    .foregroundColor(tc.primary)
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
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail or icon
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(tc.iconGreen.mid.opacity(0.15))
                    .frame(width: 40, height: 40)
                if let data = recipe.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(AdaptiveCardShapeStyle())
                } else {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(AppFont.bold(14))
                        .foregroundColor(tc.iconGreen.mid)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                Text("\(recipe.perServingCalories) cal/serving · \(recipe.yield) serving\(recipe.yield == 1 ? "" : "s") · Purity \(recipe.purityScore)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Primary: log directly to food log
            Button(action: onLog) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.regular(28))
                    .foregroundColor(tc.primary)
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
            .tint(tc.primary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Save to My Foods via leading swipe
            Button(action: onSaveAsFood) {
                Label("Save to My Foods", systemImage: "arrow.down.to.line")
            }
            .tint(tc.primaryDark)
        }
        .contextMenu {
            Button(action: onSaveAsFood) {
                Label("Save to My Foods", systemImage: "arrow.down.to.line")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
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
