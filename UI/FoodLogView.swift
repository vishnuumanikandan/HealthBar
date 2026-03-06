//
//  FoodLogView.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData

/// Main Food Log view showing today's nutrition progress and meal entries
///
/// Features:
/// - Progress rings for calories and macros
/// - List of today's food entries
/// - Swipe-to-delete with 5-second undo
/// - Swipe-to-edit functionality
/// - Floating action button to add food
/// - Empty state when no entries exist
struct FoodLogView: View {

    // MARK: - Properties

    /// The view model managing this view's state
    @State private var viewModel: FoodLogViewModel

    /// Scene phase for handling app background/foreground
    @Environment(\.scenePhase) private var scenePhase

    /// Settings manager for advanced nutrition toggle
    @State private var settings = SettingsManager.shared

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: FoodLogViewModel(coordinator: coordinator))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background color
                DesignSystem.Colors.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.hasNoEntries {
                    emptyStateView
                } else {
                    contentView
                }

                // Floating action button (fixed to bottom right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addFoodButton
                            .padding(.trailing, DesignSystem.Spacing.lg)
                            .padding(.bottom, DesignSystem.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Food Log")
            .sheet(isPresented: $viewModel.showingAddFood) {
                AddFoodFormView(viewModel: viewModel)
            }
            .alert("Food Added!", isPresented: $viewModel.showSuccessMessage) {
                Button("OK") {
                    viewModel.dismissSuccessMessage()
                }
            } message: {
                if viewModel.lastEarnedXP > 0 {
                    Text("\(viewModel.lastAddedFoodName) logged successfully! You earned +\(viewModel.lastEarnedXP) XP!")
                } else {
                    Text("\(viewModel.lastAddedFoodName) logged successfully!")
                }
            }
            .onChange(of: viewModel.showSuccessMessage) { oldValue, newValue in
                if newValue {
                    // Provide haptic feedback when food is added successfully
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .task {
                // Load all data when view appears
                await viewModel.loadTodaysData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
            }
            .refreshable {
                await viewModel.refreshData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
            }
            .overlay {
                // Toast overlay for quick-log success
                if viewModel.showToast, let message = viewModel.toastMessage {
                    toastOverlay(message: message)
                }
            }
            .overlay(alignment: .bottom) {
                // Undo toast at bottom (never overlaps XP toasts which are in upper half)
                if viewModel.showUndoToast {
                    UndoToast(
                        message: viewModel.undoMessage,
                        onUndo: {
                            viewModel.undoDelete()
                        }
                    )
                    .padding(.bottom, 100) // Above tab bar and FAB
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showUndoToast)
                }
            }
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
            .onDisappear {
                // Finalize any pending deletes when leaving the view
                Task {
                    await viewModel.finalizeAnyPendingDeletes()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Finalize any pending deletes when app goes to background
                if newPhase == .background {
                    Task {
                        await viewModel.finalizeAnyPendingDeletes()
                    }
                }
            }
        }
    }

    // MARK: - Toast Overlay

    /// Toast notification that appears briefly after quick-log
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
            .padding(.bottom, 100) // Above FAB
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showToast)
    }

    // MARK: - Subviews

    /// Loading indicator
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your meals...")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// Empty state when no food entries exist for today
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Show quick log sections even in empty state
                if !viewModel.favoriteFoods.isEmpty {
                    favoritesSection
                }

                if !viewModel.recentFoods.isEmpty {
                    recentFoodsSection
                }

                // Empty state for today's meals
                EmptyStateView(
                    icon: "fork.knife",
                    title: "No meals logged today!",
                    message: viewModel.recentFoods.isEmpty
                        ? "Start tracking your meals to see your progress and earn XP."
                        : "Tap a recent food above to quick-log, or add a new meal.",
                    actionTitle: "Log First Meal",
                    action: {
                        viewModel.showingAddFood = true
                    }
                )
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    /// Main content with progress and food entries
    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Progress section
                progressSection

                // Favorites section (horizontal scroll)
                if !viewModel.favoriteFoods.isEmpty {
                    favoritesSection
                }

                // Recent Foods section (horizontal scroll)
                if !viewModel.recentFoods.isEmpty {
                    recentFoodsSection
                }

                // Food entries list
                foodEntriesSection
            }
            .padding(DesignSystem.Spacing.lg)
            .padding(.bottom, 80) // Space for floating button
        }
    }

    // MARK: - Favorites Section

    /// Horizontal scrolling favorites section for quick re-logging
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.energy)

                Text("Favorites")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(viewModel.favoriteFoods, id: \.id) { entry in
                        quickLogCard(entry: entry, showFavoriteButton: false)
                    }
                }
                .padding(.horizontal, 2) // Prevent shadow clipping
            }
        }
    }

    // MARK: - Recent Foods Section

    /// Horizontal scrolling recent foods section for quick re-logging
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
                .padding(.horizontal, 2) // Prevent shadow clipping
            }
        }
    }

    /// Quick log card for horizontal scroll sections
    private func quickLogCard(entry: FoodEntry, showFavoriteButton: Bool) -> some View {
        Button {
            Task {
                await viewModel.quickLog(entry)
            }
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // Photo or placeholder
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

                    // Favorite star button (only in Recent Foods section)
                    if showFavoriteButton {
                        Button {
                            Task {
                                await viewModel.toggleFavorite(entry)
                            }
                        } label: {
                            Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(entry.isFavorite ? DesignSystem.Colors.energy : .white)
                                .padding(6)
                                .background(
                                    Circle()
                                        .fill(entry.isFavorite ? DesignSystem.Colors.energy.opacity(0.2) : Color.black.opacity(0.4))
                                )
                        }
                        .offset(x: 4, y: -4)
                    }
                }

                // Food name (truncated)
                Text(entry.name)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)

                // Calories
                Text("\(entry.calories) cal")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                // Relative time
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

    /// Progress section showing calorie and macro rings
    private var progressSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Today's Progress")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Calorie progress ring (large) - centered properly
            VStack(spacing: DesignSystem.Spacing.sm) {
                ProgressRing(
                    progress: viewModel.calorieProgress,
                    lineWidth: 16,
                    size: 180,
                    showPercentage: false,
                    centerText: viewModel.calorieText
                )
                .frame(width: 180, height: 180) // Explicit frame for proper centering

                Text("Calories")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center) // Explicit center alignment
            .padding(.vertical, DesignSystem.Spacing.md)

            // Macro cards (protein, carbs, fat)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                // Protein
                macroCard(
                    icon: "leaf.fill",
                    title: "Protein",
                    current: Int(viewModel.totalProtein),
                    target: Int(viewModel.currentGoal?.proteinTarget ?? 1),
                    unit: "g",
                    color: DesignSystem.Colors.primary,
                    progress: viewModel.proteinProgress
                )

                // Carbs
                macroCard(
                    icon: "flame.fill",
                    title: "Carbs",
                    current: Int(viewModel.totalCarbs),
                    target: Int(viewModel.currentGoal?.carbTarget ?? 1),
                    unit: "g",
                    color: DesignSystem.Colors.energy,
                    progress: viewModel.carbProgress
                )

                // Fat
                macroCard(
                    icon: "drop.fill",
                    title: "Fat",
                    current: Int(viewModel.totalFat),
                    target: Int(viewModel.currentGoal?.fatTarget ?? 1),
                    unit: "g",
                    color: DesignSystem.Colors.warning,
                    progress: viewModel.fatProgress
                )
            }

            // Advanced Nutrients Grid (only when toggle is enabled)
            if settings.trackAdvancedNutrition {
                AdvancedNutrientsGrid(entries: viewModel.todaysEntries, goal: viewModel.currentGoal)
            }
        }
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

    /// Food entries section
    private var foodEntriesSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Today's Meals")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.todaysEntries, id: \.id) { entry in
                foodEntryCard(entry)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    /// Individual food entry card
    private func foodEntryCard(_ entry: FoodEntry) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail (if exists)
            if let photoData = entry.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: DesignSystem.Sizes.thumbnail, height: DesignSystem.Sizes.thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
            } else {
                // Placeholder icon
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .fill(DesignSystem.Colors.primary.opacity(0.1))
                        .frame(width: DesignSystem.Sizes.thumbnail, height: DesignSystem.Sizes.thumbnail)

                    Image(systemName: "fork.knife")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }

            // Food info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // Name and meal type pill
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(entry.name)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    MealTypePill(mealType: entry.mealType)
                }

                Text("\(entry.calories) cal")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("P: \(Int(entry.protein))g • C: \(Int(entry.carbs))g • F: \(Int(entry.fat))g")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Spacer()

            // Time
            Text(timeString(from: entry.date))
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            // Three-dot menu button
            Menu {
                // Favorite toggle
                Button {
                    Task {
                        await viewModel.toggleFavorite(entry)
                    }
                } label: {
                    Label(
                        entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: entry.isFavorite ? "star.slash" : "star"
                    )
                }

                // Edit button
                Button {
                    viewModel.startEditing(entry)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Divider()

                // Delete button
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.deleteWithUndo(entry)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    /// Macro card component
    private func macroCard(
        icon: String,
        title: String,
        current: Int,
        target: Int,
        unit: String,
        color: Color,
        progress: Double
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

            // Mini progress bar
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

    /// Floating action button to add food
    private var addFoodButton: some View {
        Button {
            viewModel.showingAddFood = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: DesignSystem.Sizes.thumbnail, height: DesignSystem.Sizes.thumbnail)
                .background(DesignSystem.Colors.primaryGradient)
                .clipShape(Circle())
                .shadow(
                    color: DesignSystem.Shadows.accentGlow.color,
                    radius: DesignSystem.Shadows.accentGlow.radius,
                    x: DesignSystem.Shadows.accentGlow.x,
                    y: DesignSystem.Shadows.accentGlow.y
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    /// Formats a date into a time string
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Food Log - With Data") {
    // Create mock coordinator with sample data
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    // Add sample food entries
    let sampleEntry1 = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )

    let sampleEntry2 = FoodEntry(
        name: "Protein Smoothie",
        date: Date().addingTimeInterval(-3600),
        calories: 320,
        protein: 28.0,
        carbs: 35.0,
        fat: 8.0,
        toxinScore: 20
    )

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

    // Add only goal and progress (no entries)
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
