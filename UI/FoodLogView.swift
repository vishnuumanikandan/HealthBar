//
//  FoodLogView.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData

/// Main Food Log view showing nutrition progress and meal entries organised by category.
///
/// Features:
/// - Date navigator (browse up to 7 days back, 4 days forward)
/// - Today's Progress ring + macro cards (always reflects today)
/// - 5 meal category sections (Breakfast, Lunch, Dinner, Snack, Uncategorized)
///   - Each section is collapsible (Fix #8)
///   - Logged meals appear as bundle rows with expand/collapse (Fix #2)
///   - Individual entries support swipe-left (edit/delete) and swipe-right (favorite) (Fix #5)
/// - Recent Foods section above Breakfast (Fix #6)
/// - Undo-delete with 5-second Task.sleep window
struct FoodLogView: View {

    // MARK: - Properties

    @State private var viewModel: FoodLogViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = SettingsManager.shared
    @State private var draggingOver: MealType? = nil

    // Fix #8: track which sections are collapsed
    @State private var collapsedSections: Set<MealType> = []

    // Fix #2 UI: track which meal bundles are expanded
    @State private var expandedBundles: Set<String> = []

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: FoodLogViewModel(coordinator: coordinator))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.displayedEntries.isEmpty && viewModel.isViewingToday {
                    loadingView
                } else {
                    contentView
                }
            }
            .navigationTitle("Food Log")
            // Add Food 3-choice sheet
            .sheet(isPresented: $viewModel.showingAddFoodChoice) {
                AddFoodChoiceSheet(viewModel: viewModel)
            }
            // Food Database full-screen sheet
            .sheet(isPresented: $viewModel.showingFoodDatabase) {
                FoodDatabaseView(viewModel: viewModel)
            }
            // Add food entry form
            .sheet(isPresented: $viewModel.showingAddFood) {
                AddFoodFormView(viewModel: viewModel)
            }
            // Edit meal form
            .sheet(isPresented: $viewModel.showingEditSheet) {
                if let entry = viewModel.editingEntry {
                    EditMealView(
                        entry: entry,
                        onSave: { name, calories, protein, carbs, fat, toxinScore, photoData in
                            Task {
                                await viewModel.updateMeal(
                                    entry,
                                    name: name,
                                    calories: calories,
                                    protein: protein,
                                    carbs: carbs,
                                    fat: fat,
                                    toxinScore: toxinScore,
                                    photoData: photoData
                                )
                            }
                        },
                        onCancel: {
                            viewModel.cancelEditing()
                        }
                    )
                }
            }
            // Bridge: barcode scan → open add food form after sheet dismiss animation
            .onChange(of: viewModel.shouldOpenAddFoodForm) { _, newValue in
                if newValue {
                    viewModel.showingAddFood = true
                    viewModel.shouldOpenAddFoodForm = false
                }
            }
            .alert("Food Added!", isPresented: $viewModel.showSuccessMessage) {
                Button("OK") { viewModel.dismissSuccessMessage() }
            } message: {
                if viewModel.lastEarnedXP > 0 {
                    Text("\(viewModel.lastAddedFoodName) logged successfully! You earned +\(viewModel.lastEarnedXP) XP!")
                } else {
                    Text("\(viewModel.lastAddedFoodName) logged successfully!")
                }
            }
            .onChange(of: viewModel.showSuccessMessage) { _, newValue in
                if newValue {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage { Text(error) }
            }
            .task {
                await viewModel.loadTodaysData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
                viewModel.displayedEntries = viewModel.todaysEntries
            }
            .refreshable {
                await viewModel.refreshData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
            }
            .overlay {
                if viewModel.showToast, let message = viewModel.toastMessage {
                    toastOverlay(message: message)
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.showUndoToast {
                    UndoToast(
                        message: viewModel.undoMessage,
                        onUndo: { viewModel.undoDelete() }
                    )
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showUndoToast)
                }
            }
            .onDisappear {
                Task { await viewModel.finalizeAnyPendingDeletes() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    Task { await viewModel.finalizeAnyPendingDeletes() }
                }
                if newPhase == .active {
                    Task { await viewModel.loadRecentFoods() }
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView().scaleEffect(1.5)
            Text("Loading your meals...")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Future Date Empty State

    private var futureDateEmptyView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                dateNavigator
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.lg)
                EmptyStateView(
                    icon: "calendar",
                    title: "No meals yet",
                    message: "You haven't logged any meals for this date.",
                    actionTitle: nil,
                    action: nil
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - Main Content

    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Date Navigator
                dateNavigator

                // Today's Progress
                progressSection

                // Fix #6: Recent Foods above meal sections
                if !viewModel.recentFoods.isEmpty {
                    recentFoodsSection
                }

                // 5 Meal Category Sections
                ForEach(MealType.allCases, id: \.self) { mealType in
                    mealSection(for: mealType)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Date Navigator

    private var dateNavigator: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                viewModel.navigateToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(
                        viewModel.canNavigateBack
                            ? DesignSystem.Colors.primary
                            : DesignSystem.Colors.textTertiary
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canNavigateBack)
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text(viewModel.selectedDateDisplayLabel)
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .animation(nil, value: viewModel.selectedDateDisplayLabel)

            Spacer()

            Button {
                viewModel.navigateToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(
                        viewModel.canNavigateForward
                            ? DesignSystem.Colors.primary
                            : DesignSystem.Colors.textTertiary
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canNavigateForward)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius / 2,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Meal Category Section

    private func mealSection(for mealType: MealType) -> some View {
        let allEntries = viewModel.entries(for: mealType)
        let isCollapsed = collapsedSections.contains(mealType)

        // Group entries: solo vs bundle
        let soloEntries = allEntries.filter { $0.mealBundleId == nil }
        let bundleDict = Dictionary(
            grouping: allEntries.filter { $0.mealBundleId != nil },
            by: { $0.mealBundleId! }
        )
        // Sort bundle IDs by the earliest entry date in each bundle
        let sortedBundleIds = bundleDict.keys.sorted {
            let d1 = bundleDict[$0]?.first?.date ?? Date.distantPast
            let d2 = bundleDict[$1]?.first?.date ?? Date.distantPast
            return d1 < d2
        }

        let sectionCalTotal = allEntries.reduce(0) { $0 + $1.calories }

        return VStack(spacing: 0) {
            // Section header
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: mealType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(mealType.color)

                Text(mealType.displayName)
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if !allEntries.isEmpty {
                    Text("\(allEntries.count)")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .semibold))
                        .foregroundColor(mealType.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(mealType.color.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Fix #8: show total cal when collapsed
                if isCollapsed && !allEntries.isEmpty {
                    Text("\(sectionCalTotal) cal")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                // Fix #8: collapse toggle (only when there are entries)
                if !allEntries.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if isCollapsed {
                                collapsedSections.remove(mealType)
                            } else {
                                collapsedSections.insert(mealType)
                            }
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // + button
                Button {
                    viewModel.openAddFoodChoice(for: mealType)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(mealType.color)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, (allEntries.isEmpty || isCollapsed) ? 0 : DesignSystem.Spacing.sm)

            // Content (hidden when collapsed)
            if !isCollapsed {
                if allEntries.isEmpty {
                    // Tappable empty state row
                    Button {
                        viewModel.openAddFoodChoice(for: mealType)
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(mealType.color)
                            Text("Add \(mealType.displayName)")
                                .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Spacer()
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(mealType.color.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                .stroke(
                                    mealType.color.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.md)
                } else {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        // Solo entries with swipe actions (Fix #5)
                        ForEach(soloEntries, id: \.id) { entry in
                            SwipeableEntryCard(
                                entry: entry,
                                onFavorite: { Task { await viewModel.toggleFavorite(entry) } },
                                onEdit: { viewModel.startEditing(entry) },
                                onDelete: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        viewModel.deleteWithUndo(entry)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        // Bundle rows (Fix #2 UI)
                        ForEach(sortedBundleIds, id: \.self) { bundleId in
                            if let components = bundleDict[bundleId] {
                                bundleRow(bundleId: bundleId, components: components)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.md)
                }
            } else {
                // Collapsed spacer
                Color.clear.frame(height: DesignSystem.Spacing.sm)
            }
        }
        .background(
            draggingOver == mealType
                ? mealType.color.opacity(0.08)
                : DesignSystem.Colors.cardBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(mealType.color.opacity(draggingOver == mealType ? 0.5 : 0), lineWidth: 2)
        )
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }

            // Bundle drag: prefix "bundle:<bundleId>"
            if item.hasPrefix("bundle:") {
                let bid = String(item.dropFirst(7))
                let bundleEntries = viewModel.displayedEntries.filter { $0.mealBundleId == bid }
                guard !bundleEntries.isEmpty,
                      bundleEntries.first?.mealType != mealType else { return false }
                Task {
                    for entry in bundleEntries {
                        await viewModel.updateMealType(of: entry, to: mealType)
                    }
                }
                return true
            }

            // Solo entry drag: item is the UUID string
            guard let uuid = UUID(uuidString: item),
                  let entry = viewModel.displayedEntries.first(where: { $0.id == uuid }),
                  entry.mealType != mealType else { return false }
            Task { await viewModel.updateMealType(of: entry, to: mealType) }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                draggingOver = targeted ? mealType : nil
            }
        }
    }

    // MARK: - Bundle Row

    private func bundleRow(bundleId: String, components: [FoodEntry]) -> some View {
        let bundleName = components.first?.mealBundleName ?? "Meal Bundle"
        let totalCal = components.reduce(0) { $0 + $1.calories }
        let isExpanded = expandedBundles.contains(bundleId)

        return VStack(spacing: 4) {
            // Bundle header row
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.orange)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(bundleName)
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(totalCal) cal · \(components.count) item\(components.count == 1 ? "" : "s")")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                // Collapse/expand toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isExpanded {
                            expandedBundles.remove(bundleId)
                        } else {
                            expandedBundles.insert(bundleId)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Three-dot menu: delete entire bundle
                Menu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteBundle(bundleId: bundleId) }
                    } label: {
                        Label("Delete Meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            // Drag entire bundle to a new section
            .draggable("bundle:\(bundleId)")

            // Expanded component rows
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(components, id: \.id) { component in
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundColor(DesignSystem.Colors.textTertiary)

                            Text(component.name)
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(component.calories) cal")
                                .font(.system(size: DesignSystem.FontSizes.caption))
                                .foregroundColor(DesignSystem.Colors.textSecondary)

                            // Per-component delete button
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.deleteWithUndo(component)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.secondaryBackground.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                    }
                }
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        let progressTitle = viewModel.isViewingToday
            ? "Today's Progress"
            : "\(viewModel.selectedDateDisplayLabel)'s Progress"

        return VStack(spacing: DesignSystem.Spacing.md) {
            Text(progressTitle)
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Paged carousel: Page 1 = calories+macros, Page 2 = extra nutrients
            TabView {
                // Page 1: Calorie ring + macro cards
                VStack(spacing: DesignSystem.Spacing.md) {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ProgressRing(
                            progress: viewModel.calorieProgress,
                            lineWidth: 16,
                            size: 160,
                            showPercentage: false,
                            centerText: viewModel.calorieText
                        )
                        .frame(width: 160, height: 160)

                        Text("Calories")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DesignSystem.Spacing.sm)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.md) {
                        macroCard(
                            icon: "leaf.fill", title: "Protein",
                            current: Int(viewModel.totalProtein),
                            target: Int(viewModel.currentGoal?.proteinTarget ?? 1),
                            unit: "g", color: DesignSystem.Colors.primary,
                            progress: viewModel.proteinProgress
                        )
                        macroCard(
                            icon: "flame.fill", title: "Carbs",
                            current: Int(viewModel.totalCarbs),
                            target: Int(viewModel.currentGoal?.carbTarget ?? 1),
                            unit: "g", color: DesignSystem.Colors.energy,
                            progress: viewModel.carbProgress
                        )
                        macroCard(
                            icon: "drop.fill", title: "Fat",
                            current: Int(viewModel.totalFat),
                            target: Int(viewModel.currentGoal?.fatTarget ?? 1),
                            unit: "g", color: DesignSystem.Colors.warning,
                            progress: viewModel.fatProgress
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, DesignSystem.Spacing.lg) // space for page dots

                // Page 2: Additional nutrients detail
                nutrientsDetailPage
                    .padding(.bottom, DesignSystem.Spacing.lg)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 340)

            if settings.trackAdvancedNutrition {
                AdvancedNutrientsGrid(entries: viewModel.displayedEntries, goal: viewModel.currentGoal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Nutrients Detail Page (Page 2 of progress)

    private var nutrientsDetailPage: some View {
        let entries = viewModel.displayedEntries

        let totalSugar = entries.compactMap(\.sugar).reduce(0, +)
        let totalFiber = entries.compactMap(\.fiber).reduce(0, +)
        let totalSodium = entries.compactMap(\.sodium).reduce(0, +)
        let totalSatFat = entries.compactMap(\.saturatedFat).reduce(0, +)
        let totalCholesterol = entries.compactMap(\.cholesterol).reduce(0, +)
        let totalPotassium = entries.compactMap(\.potassium).reduce(0, +)

        return VStack(spacing: DesignSystem.Spacing.md) {
            Text("Nutrition Details")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignSystem.Spacing.sm)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: DesignSystem.Spacing.md) {
                nutrientChip(label: "Sugar", value: String(format: "%.1f", totalSugar), unit: "g",
                             icon: "cube.fill", color: .pink)
                nutrientChip(label: "Fiber", value: String(format: "%.1f", totalFiber), unit: "g",
                             icon: "leaf", color: .green)
                nutrientChip(label: "Sodium", value: String(format: "%.0f", totalSodium), unit: "mg",
                             icon: "drop.halffull", color: .blue)
                nutrientChip(label: "Sat. Fat", value: String(format: "%.1f", totalSatFat), unit: "g",
                             icon: "drop.fill", color: .orange)
                nutrientChip(label: "Cholesterol", value: String(format: "%.0f", totalCholesterol), unit: "mg",
                             icon: "heart.fill", color: .red)
                nutrientChip(label: "Potassium", value: String(format: "%.0f", totalPotassium), unit: "mg",
                             icon: "bolt.fill", color: .purple)
            }

            Text("Logged values only — missing if food not entered")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func nutrientChip(label: String, value: String, unit: String,
                               icon: String, color: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
    }

    // MARK: - Recent Foods Section

    private var recentFoodsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Recent Foods")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(viewModel.recentFoods, id: \.id) { entry in
                        quickLogCard(entry: entry, showFavoriteButton: true)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Quick Log Card

    private func quickLogCard(entry: FoodEntry, showFavoriteButton: Bool) -> some View {
        Button {
            Task { await viewModel.quickLog(entry) }
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    if let photoData = entry.photoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                                .frame(width: 80, height: 80)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                    }

                    if showFavoriteButton {
                        Button {
                            Task { await viewModel.toggleFavorite(entry) }
                        } label: {
                            Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(entry.isFavorite ? DesignSystem.Colors.energy : .white)
                                .padding(6)
                                .background(
                                    Circle()
                                        .fill(entry.isFavorite
                                              ? DesignSystem.Colors.energy.opacity(0.2)
                                              : Color.black.opacity(0.4))
                                )
                        }
                        .offset(x: 4, y: -4)
                    }
                }

                Text(entry.name)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)

                Text("\(entry.calories) cal")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text(viewModel.relativeTimeString(from: entry.date))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .shadow(
                color: DesignSystem.Shadows.card.color,
                radius: DesignSystem.Shadows.card.radius / 2,
                x: DesignSystem.Shadows.card.x,
                y: DesignSystem.Shadows.card.y
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Macro Card

    private func macroCard(
        icon: String, title: String,
        current: Int, target: Int, unit: String,
        color: Color, progress: Double
    ) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: DesignSystem.Sizes.iconCircleSmall, height: DesignSystem.Sizes.iconCircleSmall)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text("\(current)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("/ \(target)\(unit)")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 4)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius / 2,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Toast Overlay

    private func toastOverlay(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showToast)
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - SwipeableEntryCard

/// Food entry card with swipe-left (edit + delete) and swipe-right (favorite) gestures.
/// Card is intentionally thin for a compact log view.
private struct SwipeableEntryCard: View {

    let entry: FoodEntry
    let onFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    /// Offset captured at gesture start — used for context-aware snapping
    @State private var dragStartOffset: CGFloat = 0
    /// Direction lock: true=horizontal, false=vertical, nil=undecided
    @State private var isHorizontalDrag: Bool? = nil

    private let trailWidth: CGFloat = 128  // edit(64) + delete(64)
    private let leadWidth: CGFloat = 64    // favorite(64)

    var body: some View {
        ZStack(alignment: .center) {
            // Trailing actions: edit + delete (full-width HStack, buttons at trailing edge)
            if offset < -8 {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 64)
                            .frame(maxHeight: .infinity)
                            .background(Color.blue)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 64)
                            .frame(maxHeight: .infinity)
                            .background(Color.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            }

            // Leading action: favorite (full-width HStack, button at leading edge)
            if offset > 8 {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onFavorite()
                    } label: {
                        Image(systemName: entry.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: leadWidth)
                            .frame(maxHeight: .infinity)
                            .background(Color.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            // Card content (thin layout)
            thinCard
                .offset(x: offset)
                .onTapGesture {
                    guard offset != 0 else { return }
                    withAnimation(.spring(response: 0.25)) { offset = 0 }
                }
        }
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height

                    // Determine and lock drag direction on first significant movement
                    if isHorizontalDrag == nil {
                        let ratio = abs(dx) / max(abs(dy), 0.001)
                        if ratio > 1.5 {
                            isHorizontalDrag = true
                            dragStartOffset = offset
                        } else if ratio < 0.67 {
                            isHorizontalDrag = false
                        }
                        // If ratio is between 0.67–1.5 (ambiguous), wait for more movement
                        return
                    }

                    guard isHorizontalDrag == true else { return }

                    withAnimation(.interactiveSpring(response: 0.3)) {
                        let proposed = dragStartOffset + dx
                        offset = max(-trailWidth, min(leadWidth, proposed))
                    }
                }
                .onEnded { value in
                    defer { isHorizontalDrag = nil }
                    guard isHorizontalDrag == true else { return }

                    let dx = value.translation.width
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if dragStartOffset < -trailWidth / 2 {
                            // Was on delete side: any rightward swipe (20px) closes, else stays open
                            offset = dx > 20 ? 0 : -trailWidth
                        } else if dragStartOffset > leadWidth / 2 {
                            // Was on favorite side: any leftward swipe (20px) closes, else stays open
                            offset = dx < -20 ? 0 : leadWidth
                        } else {
                            // Near center: threshold-based snap
                            if dx < -40 { offset = -trailWidth }
                            else if dx > 40 { offset = leadWidth }
                            else { offset = 0 }
                        }
                    }
                }
        )
        .draggable(entry.id.uuidString)
    }

    // Fix #7: Thin card layout
    private var thinCard: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Photo thumbnail — only show if actual photo exists (no placeholder for thin cards)
            if let photoData = entry.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
            }

            // Food info: name + cal + time on two lines
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(entry.calories) cal")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text("·")
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Text(timeString(from: entry.date))
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(DesignSystem.Colors.energy)
                    }
                }
            }

            Spacer()

            // Three-dot menu
            Menu {
                Button {
                    onFavorite()
                } label: {
                    Label(
                        entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: entry.isFavorite ? "star.slash" : "star"
                    )
                }

                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Food Log - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let sampleEntry1 = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )
    sampleEntry1.mealType = .lunch

    let sampleEntry2 = FoodEntry(
        name: "Protein Smoothie",
        date: Date().addingTimeInterval(-3600),
        calories: 320,
        protein: 28.0,
        carbs: 35.0,
        fat: 8.0,
        toxinScore: 20
    )
    sampleEntry2.mealType = .breakfast

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 0,
        currentStreak: 0,
        longestStreak: 0,
        lastActiveDate: Date(),
        rank: Rank.iron.rawValue
    )

    context.insert(sampleEntry1)
    context.insert(sampleEntry2)
    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)
    return FoodLogView(coordinator: coordinator)
}

#Preview("Food Log - Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 0,
        currentStreak: 0,
        longestStreak: 0,
        lastActiveDate: Date(),
        rank: Rank.iron.rawValue
    )

    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)
    return FoodLogView(coordinator: coordinator)
}
