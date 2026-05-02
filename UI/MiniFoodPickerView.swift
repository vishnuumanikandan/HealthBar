//
//  MiniFoodPickerView.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import SwiftUI

/// A searchable food picker used inside meal and recipe builders.
///
/// Two tabs:
/// - Ingredients: built-in food library (~150 foods)
/// - My Foods: user-created custom foods, with an "Add Custom Ingredient +" button
///
/// On selection, presents a brief quantity picker, then returns
/// a SavedMealComponent to the caller.
struct MiniFoodPickerView: View {

    // MARK: - Properties

    let dbViewModel: FoodDatabaseViewModel
    let onAdd: (SavedMealComponent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    @State private var pickerTab: PickerTab = .ingredients
    @State private var searchText: String = ""
    @State private var pickerFood: LoggableFood? = nil
    @State private var showingQuantityPicker: Bool = false
    @State private var showingAddCustomIngredient: Bool = false

    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Tab Enum

    private enum PickerTab {
        case ingredients, myFoods
    }

    // MARK: - Computed

    private var results: [LoggableFood] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        switch pickerTab {
        case .ingredients:
            let foods = q.isEmpty ? BuiltInFoods.all : BuiltInFoods.all.filter { $0.name.lowercased().contains(q) }
            return foods.map { LoggableFood(from: $0) }
        case .myFoods:
            let foods = q.isEmpty ? dbViewModel.customFoods : dbViewModel.customFoods.filter { $0.name.lowercased().contains(q) }
            return foods.map { LoggableFood(from: $0) }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pickerTabBar
                Group {
                    if results.isEmpty && pickerTab == .ingredients {
                        emptyState(message: searchText.isEmpty ? "No ingredients" : "No results for \"\(searchText)\"")
                    } else if results.isEmpty && pickerTab == .myFoods {
                        myFoodsEmptyState
                    } else {
                        foodList
                    }
                }
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: pickerTab == .ingredients ? "Search ingredients…" : "Search my foods…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.regular(17))
                        .foregroundColor(tc.textSecondary)
                }
            }
            .sheet(isPresented: $showingQuantityPicker) {
                if let food = pickerFood {
                    IngredientQuantitySheet(food: food) { component in
                        onAdd(component)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddCustomIngredient) {
                AddCustomFoodView(existingFood: nil) { food in
                    Task { await dbViewModel.saveCustomFood(food, isNew: true) }
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var pickerTabBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            tabPill(label: "Ingredients", tab: .ingredients)
            tabPill(label: "My Foods", tab: .myFoods)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(tc.cardBackground)
    }

    private func tabPill(label: String, tab: PickerTab) -> some View {
        let isSelected = pickerTab == tab
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pickerTab = tab }
        } label: {
            Text(label)
                .font(AppFont.bold(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : tc.textPrimary)
                .adaptivePill(
                    borderColor: isSelected ? tc.primary : tc.textTertiary.opacity(0.4),
                    fillColor: isSelected ? tc.primary : tc.cardBackground
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Food List

    private var foodList: some View {
        List {
            if pickerTab == .myFoods {
                // Fix #5: add custom ingredient button at the top of My Foods
                Section {
                    Button {
                        showingAddCustomIngredient = true
                    } label: {
                        HStack {
                            Label("Add Custom Ingredient", systemImage: "plus.circle.fill")
                                .font(AppFont.bold(16))
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .adaptiveCard(
                            borderColor: tc.buttonBorder,
                            fillColor: .clear,
                            fillGradient: DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)
                        )
                    }
                    .listRowBackground(tc.cardBackground)
                }
            }
            Section {
                ForEach(results) { food in
                    Button {
                        pickerFood = food
                        showingQuantityPicker = true
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.md) {
                            ZStack {
                                AdaptiveCardShapeStyle()
                                    .fill(iconColor(for: pickerTab).opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Image(systemName: iconName(for: pickerTab))
                                    .font(AppFont.regular(15))
                                    .foregroundColor(iconColor(for: pickerTab))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name)
                                    .font(AppFont.bold(16))
                                    .foregroundColor(tc.textPrimary)
                                Text("\(food.caloriesPerBase) cal · \(food.servingDescription)")
                                    .font(AppFont.regular(12))
                                    .foregroundColor(tc.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "plus")
                                .font(AppFont.bold(14))
                                .foregroundColor(tc.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(tc.cardBackground)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func iconName(for tab: PickerTab) -> String {
        tab == .ingredients ? "leaf.fill" : "person.fill"
    }

    private func iconColor(for tab: PickerTab) -> Color {
        tab == .ingredients ? tc.primaryDark : tc.primary
    }

    // MARK: - Empty States

    private func emptyState(message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text(message)
                .font(AppFont.regular(16))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var myFoodsEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "person.badge.plus")
                .font(AppFont.regular(44))
                .foregroundColor(tc.primary.opacity(0.6))
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(searchText.isEmpty ? "No custom foods yet" : "No results for \"\(searchText)\"")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
                if searchText.isEmpty {
                    Text("Add your own ingredients below")
                        .font(AppFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                }
            }
            if searchText.isEmpty {
                Button {
                    showingAddCustomIngredient = true
                } label: {
                    Label("Add Custom Ingredient", systemImage: "plus")
                        .font(AppFont.bold(16))
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .adaptivePill(
                            borderColor: tc.buttonBorder,
                            fillColor: .clear,
                            fillGradient: DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
}

// MARK: - IngredientQuantitySheet

/// Lightweight quantity entry shown inside MiniFoodPickerView.
/// Similar to ServingSizePickerSheet but returns a SavedMealComponent.
private struct IngredientQuantitySheet: View {

    let food: LoggableFood
    let onConfirm: (SavedMealComponent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String
    @State private var quantity: Double

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    init(food: LoggableFood, onConfirm: @escaping (SavedMealComponent) -> Void) {
        self.food = food
        self.onConfirm = onConfirm
        let q = food.baseAmount
        self._quantity = State(initialValue: q)
        self._quantityText = State(initialValue: IngredientQuantitySheet.fmt(q))
    }

    private var scaled: (calories: Int, protein: Double, carbs: Double, fat: Double) {
        food.scaled(to: quantity)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Food name
                Text(food.name)
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignSystem.Spacing.md)

                // Quantity control
                HStack(spacing: DesignSystem.Spacing.lg) {
                    Button {
                        let step = stepSize
                        let v = max(step, quantity - step)
                        quantity = v; quantityText = Self.fmt(v)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(AppFont.regular(36))
                            .foregroundColor(tc.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(quantity <= 0.01)

                    VStack(spacing: 2) {
                        TextField("Qty", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(tc.textPrimary)
                            .frame(width: 110)
                            .onChange(of: quantityText) { _, v in
                                if let p = Double(v.replacingOccurrences(of: ",", with: ".")), p > 0 { quantity = p }
                            }
                        Text(food.unit)
                            .font(AppFont.regular(14))
                            .foregroundColor(tc.textSecondary)
                    }

                    Button {
                        let step = stepSize
                        let v = quantity + step
                        quantity = v; quantityText = Self.fmt(v)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.regular(36))
                            .foregroundColor(tc.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, DesignSystem.Spacing.md)

                // Nutrition preview
                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroChip(value: "\(scaled.calories)", label: "cal", color: tc.macroBarCarbs)
                    macroChip(value: String(format: "%.0f", scaled.protein), label: "P", color: tc.primary)
                    macroChip(value: String(format: "%.0f", scaled.carbs), label: "C", color: tc.macroBarCarbs)
                    macroChip(value: String(format: "%.0f", scaled.fat), label: "F", color: tc.macroBarFat)
                }

                AppButton(title: "Add Ingredient", style: .primary) {
                    let s = food.scaled(to: quantity)
                    let component = SavedMealComponent(
                        foodName: food.name,
                        quantity: quantity,
                        servingUnit: food.unit,
                        calories: s.calories,
                        protein: s.protein,
                        carbs: s.carbs,
                        fat: s.fat,
                        toxinScore: food.toxinScore
                    )
                    onConfirm(component)
                    dismiss()
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)

                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle("Quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                        .font(AppFont.regular(17))
                        .foregroundColor(tc.textSecondary)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func macroChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.bold(17))
                .foregroundColor(color)
            Text(label)
                .font(AppFont.regular(10))
                .foregroundColor(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: color.opacity(0.3), fillColor: color.opacity(0.1))
    }

    private var stepSize: Double {
        food.unit == "g" || food.unit == "ml" ? 10.0 : 1.0
    }

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}
