//
//  FoodLogViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import Foundation
import SwiftUI
import ImageIO

/// ViewModel for the Food Log feature
///
/// Manages today's food entries, daily goals, and progress calculations.
/// Uses @Observable macro (not @ObservableObject) for iOS 17+ compatibility.
@Observable
@MainActor
final class FoodLogViewModel {

    // MARK: - Properties

    /// Reference to the app coordinator for data operations.
    /// Internal so FoodDatabaseViewModel can share the same coordinator.
    let coordinator: AppCoordinator

    /// Barcode service for nutrition lookup
    private let barcodeService: BarcodeService

    /// AI food recognition service for natural-language meal logging
    private let aiService: AIFoodRecognitionService

    // MARK: - Data State

    /// Today's food entries
    var todaysEntries: [FoodEntry] = []

    /// Today's daily goal
    var currentGoal: DailyGoal?

    /// Today's complete summary data
    var todaysSummary: TodaySummary?

    /// Recent unique foods for quick-log (one per fingerprint)
    var recentFoods: [FoodEntry] = []

    /// Favorited foods for quick-log (one per fingerprint)
    var favoriteFoods: [FoodEntry] = []

    // MARK: - Water (WATER-1)

    /// Today's water count in cups. Refreshed at the `loadTodaysData()` chokepoint and set
    /// straight from the mutation's return value — never optimistically, so there is only
    /// ever one source for it.
    var waterCupCount: Int = 0

    /// Today's resolved water goal in cups: `waterGoalCups ?? defaultGoalCups`, display-clamped.
    var waterGoalCups: Int = WaterConstants.defaultGoalCups

    // MARK: - Toast State

    /// Toast message to display
    var toastMessage: String?

    /// Whether toast is currently visible
    var showToast: Bool = false

    // MARK: - Computed Totals (always reflects selected date via displayedEntries)

    /// Total calories for the currently viewed date
    var totalCalories: Int {
        displayedEntries.reduce(0) { $0 + $1.calories }
    }

    /// Total protein for the currently viewed date (in grams)
    var totalProtein: Double {
        displayedEntries.reduce(0.0) { $0 + $1.protein }
    }

    /// Total carbs for the currently viewed date (in grams)
    var totalCarbs: Double {
        displayedEntries.reduce(0.0) { $0 + $1.carbs }
    }

    /// Total fat for the currently viewed date (in grams)
    var totalFat: Double {
        displayedEntries.reduce(0.0) { $0 + $1.fat }
    }

    /// Toxin score for the currently viewed date: the calorie-weighted average of its
    /// entries (0–100). See NutritionManager.dailyToxinScore.
    var dailyToxinScore: Int {
        NutritionManager.dailyToxinScore(from: displayedEntries)
    }

    // MARK: - Progress Calculations

    /// Calculates calorie progress percentage
    var calorieProgress: Double {
        guard let goal = currentGoal, goal.calorieTarget > 0 else { return 0.0 }
        return Double(totalCalories) / Double(goal.calorieTarget)
    }

    /// Calculates protein progress percentage
    var proteinProgress: Double {
        guard let goal = currentGoal, goal.proteinTarget > 0 else { return 0.0 }
        return totalProtein / goal.proteinTarget
    }

    /// Calculates carbs progress percentage
    var carbProgress: Double {
        guard let goal = currentGoal, goal.carbTarget > 0 else { return 0.0 }
        return totalCarbs / goal.carbTarget
    }

    /// Calculates fat progress percentage
    var fatProgress: Double {
        guard let goal = currentGoal, goal.fatTarget > 0 else { return 0.0 }
        return totalFat / goal.fatTarget
    }

    /// Formatted calorie text for center of ring
    var calorieText: String {
        "\(totalCalories)"
    }

    // MARK: - Date Navigation State

    /// The date currently being viewed (start of day)
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Entries displayed for the currently viewed date
    var displayedEntries: [FoodEntry] = []

    /// Loading state for non-today date entries
    var isLoadingDateEntries: Bool = false

    // MARK: - Meal Section & Sheet Chain State

    /// The meal type context when opening the add food flow from a section
    var pendingMealType: MealType = .uncategorized

    /// Controls visibility of the 3-choice AddFoodChoiceSheet
    var showingAddFoodChoice: Bool = false

    /// Controls visibility of the Food Database full-screen sheet
    var showingFoodDatabase: Bool = false

    /// Bridge flag: when true, FoodLogView opens AddFoodFormView after a sheet dismiss animation
    var shouldOpenAddFoodForm: Bool = false

    // MARK: - Form Meal Type

    /// The meal type used when submitting the add food form
    var formMealType: MealType = .uncategorized

    // MARK: - UI State

    /// Loading state indicator
    var isLoading: Bool = false

    /// Controls visibility of add food sheet
    var showingAddFood: Bool = false

    /// When true, the next addFoodEntry call also persists the food to My Foods (CustomFood)
    var pendingSaveToMyFoods: Bool = false

    /// Error message to display
    var errorMessage: String?

    /// Success message after adding food
    var showSuccessMessage: Bool = false
    var lastAddedFoodName: String = ""
    var lastEarnedXP: Int = 0

    /// Track which entry is being deleted (for loading state)
    var deletingEntryId: UUID?

    // MARK: - Form State (for AddFoodFormView)

    /// Form field: Food name
    var formFoodName: String = ""

    /// Form field: Calories
    var formCalories: String = ""

    /// Form field: Protein (in grams)
    var formProtein: String = ""

    /// Form field: Carbs (in grams)
    var formCarbs: String = ""

    /// Form field: Fat (in grams)
    var formFat: String = ""

    /// Form field: Toxin score (0-100)
    var formToxinScore: Double = 30.0

    // MARK: - Advanced Nutrition Form State

    /// Whether the advanced nutrition section is expanded
    var isAdvancedNutritionExpanded: Bool = false

    /// Form field: Fiber (grams)
    var formFiber: String = ""

    /// Form field: Sugar (grams)
    var formSugar: String = ""

    /// Form field: Sodium (milligrams)
    var formSodium: String = ""

    /// Form field: Saturated Fat (grams)
    var formSaturatedFat: String = ""

    /// Form field: Cholesterol (milligrams)
    var formCholesterol: String = ""

    /// Form field: Potassium (milligrams)
    var formPotassium: String = ""

    /// Form submitting state
    var isSubmittingForm: Bool = false

    /// Form validation errors (real-time)
    var formValidationErrors: [String: String] = [:]

    // MARK: - Photo State

    /// Selected photo for preview (UIImage)
    var selectedPhoto: UIImage?

    /// Photo data ready for persistence (JPEG compressed)
    var photoData: Data?

    /// Photo processing state (compression, validation)
    var isProcessingPhoto: Bool = false

    /// Show camera picker sheet
    var showingCameraPicker: Bool = false

    /// Show photo library picker sheet
    var showingPhotoPicker: Bool = false

    // MARK: - Barcode State

    /// Show barcode scanner sheet
    var showingBarcodeScanner: Bool = false

    /// Show manual barcode entry sheet
    var showingManualBarcodeEntry: Bool = false

    /// Manual barcode input field
    var manualBarcodeInput: String = ""

    /// Scanned barcode UPC code
    var scannedBarcode: String?

    /// Loading state while fetching nutrition from barcode
    var isLoadingBarcodeNutrition: Bool = false

    /// Error message from barcode lookup
    var barcodeError: String?

    /// Serving size in grams (for barcode entries)
    var servingSize: String = "100"

    /// Whether serving size is being used (only for barcode entries)
    var useServingSize: Bool = false

    // MARK: - Delete with Undo State

    /// Recently deleted entry (for undo functionality)
    var recentlyDeleted: FoodEntry?

    /// Whether undo toast is currently showing
    var showUndoToast: Bool = false

    /// Message for undo toast
    var undoMessage: String = ""

    /// Task for deletion countdown (uses Task.sleep instead of Timer for better lifecycle handling)
    private var deletionTask: Task<Void, Never>?

    /// The undo window (seconds) before a delete is finalized (M9 — named per F3 decision 6).
    private static let undoWindowSeconds: Double = 5

    /// Tracks whether current undo is for a quick log (true) or delete (false)
    /// Quick log undo = delete the newly created entry
    /// Delete undo = restore the entry to UI
    private var isQuickLogUndo: Bool = false

    // MARK: - Edit State

    /// Entry currently being edited
    var editingEntry: FoodEntry?

    /// Show edit sheet
    var showingEditSheet: Bool = false

    // MARK: - AI Recognition State

    /// Controls visibility of the DescribeMealView sheet
    var showingDescribeMeal: Bool = false

    /// User's typed meal description (the "what" — field 1 of the describe sheet)
    var mealDescriptionInput: String = ""

    /// User-declared food category for the describe sheet (AILOG-1b). Single-select,
    /// defaults to `.meal`; drives the per-field labels/placeholders and is sent on every
    /// analyze. Reset alongside `mealDescriptionInput` in `openDescribeMeal()`.
    var describeCategory: FoodCategory = .meal

    /// Optional amount/size input (field 2). Sent trimmed-or-nil (AILOG-1b).
    var describeAmountInput: String = ""

    /// Optional extras input — seasonings/mix-ins/toppings (field 3). Sent trimmed-or-nil (AILOG-1b).
    var describeExtrasInput: String = ""

    /// Whether an AI recognition request is in flight
    var isRecognizing: Bool = false

    /// Error or clarification message from the last recognition attempt
    var recognitionError: String? = nil

    /// Items returned by the AI recognition service (source of truth before review)
    var recognizedItems: [RecognizedFoodItem] = []

    /// Controls visibility of the RecognizedFoodsReviewView sheet
    var showingRecognitionReview: Bool = false

    /// In-flight recognition task (for cancellation)
    private var recognitionTask: Task<Void, Never>? = nil

    /// Timestamp of the last recognition request start (for rate limiting)
    private var lastRecognitionStart: Date? = nil

    // MARK: - Destination Strip State (AILOG-1b)

    /// Fingerprints of the entries logged in this recognition session, captured by
    /// `logRecognizedItems`. A non-empty set doubles as the did-log-this-session flag that
    /// gates the review strip's Favorite chip. Reset in `openDescribeMeal()`.
    var loggedFingerprints: [FoodFingerprint] = []

    // MARK: - Describe Meal Photo State (isolated from manual AddFoodForm photo)

    /// Finalized JPEG data for the describe-meal photo (ready for API + persistence)
    var describeMealPhotoData: Data? = nil

    /// Whether photo is being processed (downsample + compress)
    var isAttachingDescribeMealPhoto: Bool = false

    /// Controls camera picker for describe-meal flow
    var showingDescribeMealCameraPicker: Bool = false

    /// Controls photo library picker for describe-meal flow
    var showingDescribeMealPhotoPicker: Bool = false

    // MARK: - Initialization

    /// Initializes the view model with an app coordinator
    /// - Parameters:
    ///   - coordinator: The app coordinator for business logic
    ///   - barcodeService: Service for barcode nutrition lookup (defaults to new instance)
    ///   - aiService: AI food recognition service (defaults to new instance)
    init(
        coordinator: AppCoordinator,
        barcodeService: BarcodeService = BarcodeService(),
        aiService: AIFoodRecognitionService = AIFoodRecognitionService()
    ) {
        self.coordinator = coordinator
        self.barcodeService = barcodeService
        self.aiService = aiService
    }

    // MARK: - Data Loading

    /// Loads today's data (entries, goals, summary)
    func loadTodaysData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch complete summary from coordinator
            let summary = try await coordinator.getTodaysSummary()

            // Update state
            todaysSummary = summary
            todaysEntries = summary.entries
            currentGoal = summary.goal

            // Keep displayedEntries in sync when viewing today
            if isViewingToday {
                displayedEntries = todaysEntries
            }

            // WATER-1: water refreshes HERE and nowhere else. This is the existing
            // today-refresh chokepoint (`.task` on appear, pull-to-refresh, and every
            // mutation path), so a midnight crossing corrects itself on the next refresh —
            // no timer, no scene-phase observer, no midnight observer (D16).
            waterCupCount = coordinator.getTodaysWaterCount()
            waterGoalCups = WaterConstants.resolvedGoal(summary.goal.waterGoalCups)

            // M9: a reload re-fetches from the DB, where a pending (not-yet-finalized) delete still
            // exists — it would resurrect into the lists mid-undo-window. Strip the current pending
            // delete by id (a reload yields fresh instances, so identity comparison would miss it).
            // Quick-log pendings genuinely exist in the DB and must stay (guard on !isQuickLogUndo).
            // This single chokepoint covers every reload trigger, incl. permanentlyDelete of a
            // superseded entry.
            if let pending = recentlyDeleted, !isQuickLogUndo {
                todaysEntries.removeAll { $0.id == pending.id }
                displayedEntries.removeAll { $0.id == pending.id }
            }

            isLoading = false
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Refreshes all data (for pull-to-refresh)
    func refreshData() async {
        await loadTodaysData()
    }

    // MARK: - Food Entry Operations

    /// Adds a new food entry
    /// - Parameters:
    ///   - name: Food name
    ///   - calories: Total calories
    ///   - protein: Protein in grams
    ///   - carbs: Carbs in grams
    ///   - fat: Fat in grams
    ///   - toxinScore: Toxin score (0-100, lower is better)
    ///   - photoData: Optional photo data (JPEG compressed)
    ///   - barcodeUPC: Optional barcode UPC string
    ///   - fiber: Optional fiber in grams
    ///   - sugar: Optional sugar in grams
    ///   - sodium: Optional sodium in milligrams
    ///   - saturatedFat: Optional saturated fat in grams
    ///   - cholesterol: Optional cholesterol in milligrams
    ///   - potassium: Optional potassium in milligrams
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        photoData: Data? = nil,
        barcodeUPC: String? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil
    ) async {
        errorMessage = nil

        do {
            let result = try await coordinator.addFoodEntry(
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                toxinScore: toxinScore,
                date: selectedDate,
                photoData: photoData,
                barcodeUPC: barcodeUPC,
                mealType: formMealType,
                fiber: fiber,
                sugar: sugar,
                sodium: sodium,
                saturatedFat: saturatedFat,
                cholesterol: cholesterol,
                potassium: potassium
            )

            // Store success info
            lastAddedFoodName = name
            lastEarnedXP = result.xpEarned

            // Persist to My Foods when coming from MyFoods "Add New Food" button
            if pendingSaveToMyFoods {
                pendingSaveToMyFoods = false
                let customFood = CustomFood(
                    name: name,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    toxinScore: toxinScore,
                    fiber: fiber,
                    sugar: sugar,
                    sodium: sodium
                )
                try? await coordinator.addCustomFood(customFood)
            }

            // Persist barcode-scanned foods to My Foods automatically
            if let _ = barcodeUPC {
                let customFood = CustomFood(
                    name: name,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    toxinScore: toxinScore,
                    fiber: fiber,
                    sugar: sugar,
                    sodium: sodium
                )
                try? await coordinator.addCustomFood(customFood)
            }

            // Reload data — always refresh today's summary; if viewing another date also reload those entries
            await loadTodaysData()
            if !isViewingToday {
                await loadEntriesForSelectedDate()
            }

            // Show success message
            showSuccessMessage = true

        } catch {
            errorMessage = "Failed to add food: \(error.localizedDescription)"
        }
    }

    /// Deletes a food entry
    /// - Parameter entry: The food entry to delete
    func deleteEntry(_ entry: FoodEntry) async {
        errorMessage = nil
        deletingEntryId = entry.id

        do {
            try await coordinator.deleteFoodEntry(entry)

            // Reload data to get updated summary
            await loadTodaysData()

        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }

        deletingEntryId = nil
    }

    /// Returns true if the given entry is currently being deleted
    func isDeleting(_ entry: FoodEntry) -> Bool {
        deletingEntryId == entry.id
    }

    // MARK: - Delete with Undo

    /// Deletes an entry with 5-second undo window
    /// - Parameter entry: The food entry to delete
    ///
    /// Entry is immediately removed from UI list.
    /// User has 5 seconds to tap "Undo" before permanent deletion.
    /// New delete immediately finalizes any pending undo.
    func deleteWithUndo(_ entry: FoodEntry) {
        // M9: a rapid double-tap on the SAME entry would fire permanentlyDelete twice (an
        // immediate finalize + a second scheduled task) → a double coordinator.deleteFoodEntry.
        // It already owns the pending slot; its expiry task is running. No-op.
        guard recentlyDeleted?.id != entry.id else { return }

        // New delete immediately finalizes any pending undo
        if let pending = recentlyDeleted {
            deletionTask?.cancel()
            if isQuickLogUndo {
                // Previous was quick log - entry stays, just clear state
            } else {
                // Previous was delete - permanently delete it
                Task {
                    await permanentlyDelete(pending)
                }
            }
        }

        // Remove from UI lists immediately
        todaysEntries.removeAll { $0.id == entry.id }
        displayedEntries.removeAll { $0.id == entry.id }

        // Store for potential undo
        recentlyDeleted = entry
        isQuickLogUndo = false  // This is a delete operation

        // Show undo toast
        undoMessage = "\(entry.name) deleted"
        showUndoToast = true

        // Light haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif

        // Start 5-second countdown using Task.sleep (safer than Timer)
        deletionTask = Task {
            do {
                try await Task.sleep(for: .seconds(Self.undoWindowSeconds))

                // Check if task was cancelled
                if !Task.isCancelled {
                    await permanentlyDelete(entry)
                }
            } catch {
                // Task was cancelled (undo was pressed)
            }
        }
    }

    /// Undoes the most recent action (delete or quick log)
    func undoDelete() {
        guard let entry = recentlyDeleted else { return }

        // Cancel pending task
        deletionTask?.cancel()

        if isQuickLogUndo {
            // Undo quick log = DELETE the newly created entry from database
            Task {
                do {
                    try await coordinator.deleteFoodEntry(entry)

                    // Reload data to reflect the deletion
                    await loadTodaysData()

                    // Success feedback
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif

                    showToastMessage("\(entry.name) removed")

                } catch {
                    print("Undo quick log error: \(error)")

                    // Error feedback
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif

                    showToastMessage("Couldn't undo — try again")
                }
            }
        } else {
            // Undo delete = RESTORE the entry to UI (it's not in database yet)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                todaysEntries.append(entry)
                todaysEntries.sort { $0.date > $1.date }
                displayedEntries.append(entry)
                displayedEntries.sort { $0.date > $1.date }
            }

            // Success feedback
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            showToastMessage("\(entry.name) restored")
        }

        // Hide toast and clear state
        showUndoToast = false
        recentlyDeleted = nil
        deletionTask = nil
        isQuickLogUndo = false
    }

    /// Permanently deletes an entry from the database
    /// - Parameter entry: The food entry to permanently delete
    private func permanentlyDelete(_ entry: FoodEntry) async {
        do {
            // Actually remove from database
            try await coordinator.deleteFoodEntry(entry)

            // Reload data to recalculate everything (de-resurrection happens in loadTodaysData)
            await loadTodaysData()

            // M9: clear the undo slot ONLY when THIS entry owns it. Finalizing a SUPERSEDED entry
            // (a newer delete opened its own window) must not wipe the newer entry's toast/state.
            if recentlyDeleted?.id == entry.id {
                showUndoToast = false
                recentlyDeleted = nil
                deletionTask = nil
            }

        } catch {
            print("Delete error: \(error)")
            // M9: delete failed — restore to BOTH lists (was: todaysEntries only), duplicate-safe:
            // an intervening reload may already have restored it (it still exists in the DB).
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if !todaysEntries.contains(where: { $0.id == entry.id }) {
                    todaysEntries.append(entry)
                    todaysEntries.sort { $0.date > $1.date }
                }
                if !displayedEntries.contains(where: { $0.id == entry.id }) {
                    displayedEntries.append(entry)
                    displayedEntries.sort { $0.date > $1.date }
                }
            }

            // Error haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            showToastMessage("Delete failed - restored")

            // Its own undo window is over and the entry is back in the lists — clear the slot, but
            // only if this entry still owns it (a newer delete may have superseded it).
            if recentlyDeleted?.id == entry.id {
                showUndoToast = false
                recentlyDeleted = nil
                deletionTask = nil
            }
        }
    }

    /// Finalizes any pending undo operations (called on view disappear or app background)
    ///
    /// This prevents users from backgrounding app, returning later, and undoing
    /// something they shouldn't.
    func finalizeAnyPendingDeletes() async {
        guard recentlyDeleted != nil else { return }

        deletionTask?.cancel()

        if isQuickLogUndo {
            // Quick log - entry stays in database, just clear state
            showUndoToast = false
            recentlyDeleted = nil
            deletionTask = nil
            isQuickLogUndo = false
        } else {
            // Delete - permanently remove from database
            if let pending = recentlyDeleted {
                await permanentlyDelete(pending)
            }
            showUndoToast = false
            // M9: force-clear the slot even if permanentlyDelete's failure path intentionally left
            // it set (the view is disappearing; there is no undo affordance to preserve).
            recentlyDeleted = nil
            deletionTask = nil
            isQuickLogUndo = false
        }
    }

    // MARK: - Edit Meal

    /// Starts editing a meal
    /// - Parameter entry: The food entry to edit
    func startEditing(_ entry: FoodEntry) {
        editingEntry = entry
        showingEditSheet = true
    }

    /// Updates an existing meal
    /// - Parameters:
    ///   - entry: The food entry to update
    ///   - name: Updated name
    ///   - calories: Updated calories
    ///   - protein: Updated protein
    ///   - carbs: Updated carbs
    ///   - fat: Updated fat
    ///   - toxinScore: Updated toxin score
    ///   - photoData: Updated photo data (optional)
    func updateMeal(
        _ entry: FoodEntry,
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        photoData: Data?
    ) async {
        entry.name = name
        entry.calories = calories
        entry.protein = protein
        entry.carbs = carbs
        entry.fat = fat
        entry.toxinScore = toxinScore
        entry.photoData = photoData

        do {
            try await coordinator.updateFoodEntry(entry)
            await loadTodaysData()

            // Success haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            showToastMessage("\(name) updated")

        } catch {
            print("Update error: \(error)")

            // Error haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            showToastMessage("Update failed")
        }

        editingEntry = nil
        showingEditSheet = false
    }

    /// Cancels editing
    func cancelEditing() {
        editingEntry = nil
        showingEditSheet = false
    }

    // MARK: - UI Helpers

    /// Dismisses the success message
    func dismissSuccessMessage() {
        showSuccessMessage = false
        lastAddedFoodName = ""
        lastEarnedXP = 0
    }

    /// Returns true if there are no entries logged today
    var hasNoEntries: Bool {
        todaysEntries.isEmpty
    }

    // MARK: - Date Navigation Computed Properties

    /// Whether the selected date is today
    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Whether the selected date is in the future
    var isViewingFuture: Bool {
        selectedDate > Calendar.current.startOfDay(for: Date())
    }

    /// Whether the user can navigate back (limit: 7 days)
    var canNavigateBack: Bool {
        let limit = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))!
        return selectedDate > limit
    }

    /// Whether the user can navigate forward (limit: 4 days ahead)
    var canNavigateForward: Bool {
        let limit = Calendar.current.date(byAdding: .day, value: 4, to: Calendar.current.startOfDay(for: Date()))!
        return selectedDate < limit
    }

    /// Display label for the date navigator: "Today", "Yesterday", or "Mon, Feb 10"
    var selectedDateDisplayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    /// Entries for a specific MealType within the currently displayed date
    func entries(for mealType: MealType) -> [FoodEntry] {
        displayedEntries.filter { $0.mealType == mealType }
    }

    /// Unique manually-entered foods (no barcode) for the Food Database My Foods tab
    var myFoods: [FoodEntry] {
        recentFoods.filter { $0.barcodeUPC == nil || $0.barcodeUPC!.isEmpty }
    }

    // MARK: - Date Navigation Methods

    /// Navigates to the previous day (up to 7 days back)
    func navigateToPreviousDay() {
        guard canNavigateBack else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
        Task { await loadEntriesForSelectedDate() }
    }

    /// Navigates to the next day (up to 4 days ahead)
    func navigateToNextDay() {
        guard canNavigateForward else { return }
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
        Task { await loadEntriesForSelectedDate() }
    }

    /// Loads entries for the currently selected date.
    /// If today: syncs from todaysEntries. Otherwise fetches from coordinator.
    func loadEntriesForSelectedDate() async {
        if isViewingToday {
            displayedEntries = todaysEntries
            return
        }
        if isViewingFuture {
            displayedEntries = []
            return
        }
        isLoadingDateEntries = true
        displayedEntries = (try? await coordinator.getEntriesForDate(selectedDate)) ?? []
        isLoadingDateEntries = false
    }

    /// Opens the 3-choice AddFood sheet pre-configured for a meal section
    func openAddFoodChoice(for mealType: MealType) {
        pendingMealType = mealType
        formMealType = mealType
        showingAddFoodChoice = true
    }

    /// Opens AddFoodFormView after a 400ms delay (allows sheet dismiss animation to complete)
    func openAddFoodFormAfterDelay() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            shouldOpenAddFoodForm = true
        }
    }

    // MARK: - Form Management

    /// Resets all form fields to their default values
    func resetForm() {
        formFoodName = ""
        formCalories = ""
        formProtein = ""
        formCarbs = ""
        formFat = ""
        formToxinScore = 30.0
        formMealType = .uncategorized
        formValidationErrors = [:]
        isSubmittingForm = false

        // Reset advanced nutrition fields
        isAdvancedNutritionExpanded = false
        formFiber = ""
        formSugar = ""
        formSodium = ""
        formSaturatedFat = ""
        formCholesterol = ""
        formPotassium = ""

        // Reset photo state
        selectedPhoto = nil
        photoData = nil
        isProcessingPhoto = false

        // Reset barcode state
        scannedBarcode = nil
        barcodeError = nil
        isLoadingBarcodeNutrition = false
        manualBarcodeInput = ""
        servingSize = "100"
        useServingSize = false
    }

    /// Validates a specific form field in real-time
    /// - Parameter field: The field name to validate
    func validateField(_ field: String) {
        switch field {
        case "foodName":
            if formFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                formValidationErrors["foodName"] = "Food name is required"
            } else {
                formValidationErrors.removeValue(forKey: "foodName")
            }

        case "calories":
            if let caloriesInt = Int(formCalories), caloriesInt >= 0 {
                formValidationErrors.removeValue(forKey: "calories")
            } else if !formCalories.isEmpty {
                formValidationErrors["calories"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "calories")
            }

        case "protein":
            if let proteinDouble = Double(formProtein), proteinDouble >= 0 {
                formValidationErrors.removeValue(forKey: "protein")
            } else if !formProtein.isEmpty {
                formValidationErrors["protein"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "protein")
            }

        case "carbs":
            if let carbsDouble = Double(formCarbs), carbsDouble >= 0 {
                formValidationErrors.removeValue(forKey: "carbs")
            } else if !formCarbs.isEmpty {
                formValidationErrors["carbs"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "carbs")
            }

        case "fat":
            if let fatDouble = Double(formFat), fatDouble >= 0 {
                formValidationErrors.removeValue(forKey: "fat")
            } else if !formFat.isEmpty {
                formValidationErrors["fat"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "fat")
            }

        default:
            break
        }
    }

    /// Validates all form fields
    /// - Returns: True if form is valid, false otherwise
    func validateAllFields() -> Bool {
        // Validate food name
        if formFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formValidationErrors["foodName"] = "Food name is required"
            return false
        }

        // Validate calories
        guard let caloriesInt = Int(formCalories), caloriesInt >= 0 else {
            formValidationErrors["calories"] = "Enter a valid calorie count"
            return false
        }

        // Validate protein
        guard let proteinDouble = Double(formProtein), proteinDouble >= 0 else {
            formValidationErrors["protein"] = "Enter a valid protein amount"
            return false
        }

        // Validate carbs
        guard let carbsDouble = Double(formCarbs), carbsDouble >= 0 else {
            formValidationErrors["carbs"] = "Enter a valid carb amount"
            return false
        }

        // Validate fat
        guard let fatDouble = Double(formFat), fatDouble >= 0 else {
            formValidationErrors["fat"] = "Enter a valid fat amount"
            return false
        }

        // Clear all validation errors if everything is valid
        formValidationErrors = [:]
        return true
    }

    /// Submits the form with current field values
    func submitForm() async {
        guard validateAllFields() else { return }

        isSubmittingForm = true
        errorMessage = nil

        // Parse advanced nutrition (only if values are entered)
        let fiber = formFiber.isEmpty ? nil : Double(formFiber)
        let sugar = formSugar.isEmpty ? nil : Double(formSugar)
        let sodium = formSodium.isEmpty ? nil : Double(formSodium)
        let saturatedFat = formSaturatedFat.isEmpty ? nil : Double(formSaturatedFat)
        let cholesterol = formCholesterol.isEmpty ? nil : Double(formCholesterol)
        let potassium = formPotassium.isEmpty ? nil : Double(formPotassium)

        await addFoodEntry(
            name: formFoodName.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(formCalories) ?? 0,
            protein: Double(formProtein) ?? 0.0,
            carbs: Double(formCarbs) ?? 0.0,
            fat: Double(formFat) ?? 0.0,
            toxinScore: Int(formToxinScore),
            photoData: photoData,
            barcodeUPC: scannedBarcode,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            saturatedFat: saturatedFat,
            cholesterol: cholesterol,
            potassium: potassium
        )

        isSubmittingForm = false

        // Reset form on success
        if errorMessage == nil {
            resetForm()
        }
    }

    // MARK: - Photo Handling

    /// Selects and processes a photo from UIImage
    /// - Parameter image: The UIImage to process
    ///
    /// Caps the stored dimensions (PHOTOPERF-1), converts the image to JPEG data with
    /// compression, validates size (< 1MB), and stores it for saving. Runs
    /// asynchronously to prevent UI blocking.
    func selectPhoto(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        // PHOTOPERF-1: cap the stored long edge before compressing. Returns the original
        // untouched when it is already within the cap, so small photos keep the exact
        // compression-only path they had before.
        let storedImage = Self.downsampleForStorage(image)

        // Convert to JPEG with 0.7 quality
        guard var data = storedImage.jpegData(compressionQuality: 0.7) else {
            errorMessage = "Failed to process photo"
            return
        }

        // Validate and compress if needed (< 1MB = 1,000,000 bytes)
        let maxSize = 1_000_000
        var quality: CGFloat = 0.7

        // Iteratively reduce quality if over 1MB
        while data.count > maxSize && quality > 0.1 {
            quality -= 0.1
            if let compressedData = storedImage.jpegData(compressionQuality: quality) {
                data = compressedData
            } else {
                break
            }
        }

        // Final check - if still too large, reject
        if data.count > maxSize {
            errorMessage = "Photo is too large. Please choose a smaller photo."
            return
        }

        print("[PHOTOPERF-1] Stored photo \(Self.pixelDescription(image)) → \(Self.pixelDescription(storedImage)), \(data.count) bytes")

        // Success - store photo
        photoData = data
        selectedPhoto = storedImage

        // Provide haptic feedback for successful selection
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// Removes the currently selected photo
    func removePhoto() {
        selectedPhoto = nil
        photoData = nil

        // Provide haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// PHOTOPERF-1: caps a manually attached photo's long edge before it is compressed
    /// into SwiftData. Manual attachments were dimensionally uncapped (only quality-
    /// iterated under 1MB), so a 4032px camera shot was stored — and later decoded — at
    /// full resolution.
    ///
    /// Deliberately SEPARATE from `processImageForRecognition` (the 1568px AI-upload
    /// pipeline) and NOT refactored to share code with it: that path is risk-isolated
    /// after AIPROXY-1b and carries a different cap for a different consumer.
    ///
    /// Returns the original image untouched when it is already within the cap — there is
    /// no upscaling path — and also on any ImageIO failure, which degrades to exactly the
    /// pre-PHOTOPERF-1 behavior rather than losing the photo.
    private static nonisolated func downsampleForStorage(_ image: UIImage) -> UIImage {
        let maxStoredPhotoDimension: CGFloat = 1200

        guard longEdgeInPixels(image) > maxStoredPhotoDimension else { return image }

        // Round-trip through JPEG data so ImageIO downsamples during decode rather than
        // holding the full-resolution bitmap (same technique as the AI pipeline).
        guard let sourceData = image.jpegData(compressionQuality: 1.0),
              let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            return image
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // normalizes orientation
            kCGImageSourceThumbnailMaxPixelSize: maxStoredPhotoDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image
        }

        // Pixels are physically rotated upright by the transform option above.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    /// Long edge in PIXELS (`size` is in points; `scale` converts).
    private static nonisolated func longEdgeInPixels(_ image: UIImage) -> CGFloat {
        max(image.size.width, image.size.height) * image.scale
    }

    /// `WIDTHxHEIGHT` in pixels, for the PHOTOPERF-1 storage log.
    private static nonisolated func pixelDescription(_ image: UIImage) -> String {
        "\(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale))"
    }

    /// Shows the camera picker
    func showCamera() {
        showingCameraPicker = true
    }

    /// Shows the photo library picker
    func showPhotoLibrary() {
        showingPhotoPicker = true
    }

    // MARK: - Barcode Scanning

    /// Shows the barcode scanner
    func showBarcodeScanner() {
        showingBarcodeScanner = true
    }

    /// Handles a scanned barcode
    /// - Parameter barcode: The scanned barcode UPC string
    ///
    /// Fetches nutrition data from Open Food Facts API and auto-fills the form.
    /// The barcode is stored separately from photo data.
    func handleBarcodeScanned(_ barcode: String) async {
        scannedBarcode = barcode
        isLoadingBarcodeNutrition = true
        barcodeError = nil
        defer { isLoadingBarcodeNutrition = false }

        do {
            // Fetch nutrition from barcode service
            let nutrition = try await barcodeService.fetchNutrition(barcode: barcode)

            // Auto-fill form fields (per 100g values)
            formFoodName = nutrition.name
            formCalories = String(nutrition.calories)
            formProtein = String(format: "%.1f", nutrition.protein)
            formCarbs = String(format: "%.1f", nutrition.carbs)
            formFat = String(format: "%.1f", nutrition.fat)
            formToxinScore = Double(nutrition.toxinScore)

            // Auto-fill advanced nutrition fields if available
            if let fiber = nutrition.fiber {
                formFiber = String(format: "%.1f", fiber)
            }
            if let sugar = nutrition.sugar {
                formSugar = String(format: "%.1f", sugar)
            }
            if let sodium = nutrition.sodium {
                formSodium = String(format: "%.0f", sodium)
            }
            if let saturatedFat = nutrition.saturatedFat {
                formSaturatedFat = String(format: "%.1f", saturatedFat)
            }
            if let cholesterol = nutrition.cholesterol {
                formCholesterol = String(format: "%.0f", cholesterol)
            }
            if let potassium = nutrition.potassium {
                formPotassium = String(format: "%.0f", potassium)
            }

            // Auto-expand advanced nutrition section if we have data
            let hasAdvancedNutrition = nutrition.fiber != nil || nutrition.sugar != nil ||
                                       nutrition.sodium != nil || nutrition.saturatedFat != nil ||
                                       nutrition.cholesterol != nil || nutrition.potassium != nil
            if hasAdvancedNutrition && SettingsManager.shared.trackAdvancedNutrition {
                isAdvancedNutritionExpanded = true
            }

            // Set product image if available
            if let imageData = nutrition.photoData,
               let image = UIImage(data: imageData) {
                selectedPhoto = image
                photoData = imageData
            }

            // Reset serving size to 100g
            servingSize = "100"
            useServingSize = true

            // Clear any validation errors
            formValidationErrors = [:]

            // Provide haptic feedback for success
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

        } catch let error as BarcodeError {
            // Handle specific barcode errors
            barcodeError = error.localizedDescription

            // Provide haptic feedback for error
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

        } catch {
            // Handle unexpected errors
            barcodeError = "Failed to fetch product data. Please try again."

            // Provide haptic feedback for error
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif
        }
    }

    /// Clears barcode data and error
    func clearBarcodeData() {
        scannedBarcode = nil
        barcodeError = nil
        isLoadingBarcodeNutrition = false
        manualBarcodeInput = ""
        servingSize = "100"
        useServingSize = false
    }

    /// Applies serving size calculation to adjust nutrition values
    /// Only works when a barcode has been scanned (per 100g values)
    func applyServingSize() {
        guard useServingSize,
              scannedBarcode != nil,
              let grams = Double(servingSize),
              grams > 0 else { return }

        // Calculate multiplier (grams / 100)
        let multiplier = grams / 100.0

        // Apply to main nutrition fields
        if let calories = Int(formCalories) {
            formCalories = String(Int(Double(calories) * multiplier))
        }

        if let protein = Double(formProtein) {
            formProtein = String(format: "%.1f", protein * multiplier)
        }

        if let carbs = Double(formCarbs) {
            formCarbs = String(format: "%.1f", carbs * multiplier)
        }

        if let fat = Double(formFat) {
            formFat = String(format: "%.1f", fat * multiplier)
        }

        // Apply to advanced nutrition fields
        if let fiber = Double(formFiber) {
            formFiber = String(format: "%.1f", fiber * multiplier)
        }

        if let sugar = Double(formSugar) {
            formSugar = String(format: "%.1f", sugar * multiplier)
        }

        if let sodium = Double(formSodium) {
            formSodium = String(format: "%.0f", sodium * multiplier)
        }

        if let saturatedFat = Double(formSaturatedFat) {
            formSaturatedFat = String(format: "%.1f", saturatedFat * multiplier)
        }

        if let cholesterol = Double(formCholesterol) {
            formCholesterol = String(format: "%.0f", cholesterol * multiplier)
        }

        if let potassium = Double(formPotassium) {
            formPotassium = String(format: "%.0f", potassium * multiplier)
        }
    }

    /// Shows the manual barcode entry sheet
    func showManualBarcodeEntry() {
        showingManualBarcodeEntry = true
    }

    /// Submits the manually entered barcode
    func submitManualBarcode() async {
        let barcode = manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else {
            barcodeError = "Please enter a barcode"
            return
        }

        // Close the manual entry sheet
        showingManualBarcodeEntry = false

        // Process the barcode the same way as scanned barcodes
        await handleBarcodeScanned(barcode)
    }

    // MARK: - Recent Foods & Favorites

    /// Loads recent unique foods for quick-log
    func loadRecentFoods() async {
        do {
            recentFoods = try await coordinator.getRecentUniqueFoods()
        } catch {
            print("Failed to load recent foods: \(error)")
            recentFoods = []
        }
    }

    /// Loads favorited foods for quick-log
    func loadFavorites() async {
        do {
            favoriteFoods = try await coordinator.getFavoriteFoods()
        } catch {
            print("Failed to load favorites: \(error)")
            favoriteFoods = []
        }
    }

    /// Quick-logs a food entry (1-tap re-log) with undo support
    ///
    /// Creates a new entry with the same nutrition data but today's date.
    /// Shows undo toast allowing user to remove the entry within 5 seconds.
    ///
    /// - Parameter entry: The food entry to re-log
    func quickLog(_ entry: FoodEntry) async {
        // If there's a pending undo from a previous action, finalize it first
        if let pending = recentlyDeleted {
            deletionTask?.cancel()
            if isQuickLogUndo {
                // Previous was quick log - entry stays, just clear state
            } else {
                // Previous was delete - permanently delete it
                await permanentlyDelete(pending)
            }
            recentlyDeleted = nil
            deletionTask = nil
        }

        do {
            let result = try await coordinator.quickLogFood(entry, date: selectedDate, mealType: .uncategorized)

            // Haptic feedback
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            // Store the newly created entry for potential undo
            recentlyDeleted = result.entry
            isQuickLogUndo = true  // This is a quick log operation

            // Show undo toast instead of regular toast
            undoMessage = "\(entry.name) logged"
            showUndoToast = true

            // Reload data to update progress
            await loadTodaysData()
            if !isViewingToday {
                await loadEntriesForSelectedDate()
            }

            // Store XP earned for potential display
            if result.xpEarned > 0 {
                lastEarnedXP = result.xpEarned
            }

            // Start 5-second countdown for auto-dismiss of undo toast
            deletionTask = Task {
                do {
                    try await Task.sleep(for: .seconds(5))

                    // Check if task was cancelled (undo was pressed)
                    if !Task.isCancelled {
                        // Just hide the toast, entry stays in database
                        await MainActor.run {
                            showUndoToast = false
                            recentlyDeleted = nil
                            deletionTask = nil
                            isQuickLogUndo = false
                        }
                    }
                } catch {
                    // Task was cancelled (undo was pressed)
                }
            }

        } catch {
            print("Quick log error: \(error)")

            // Error haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            showToastMessage("Couldn't log — try again")
        }
    }

    /// Quick-logs a food entry to a specific date and meal type (used by Food Database)
    func quickLog(_ entry: FoodEntry, date: Date, mealType: MealType) async {
        // Finalize any pending undo first
        if let pending = recentlyDeleted {
            deletionTask?.cancel()
            if !isQuickLogUndo {
                await permanentlyDelete(pending)
            }
            recentlyDeleted = nil
            deletionTask = nil
        }

        do {
            let result = try await coordinator.quickLogFood(entry, date: date, mealType: mealType)

            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            recentlyDeleted = result.entry
            isQuickLogUndo = true
            undoMessage = "\(entry.name) logged"
            showUndoToast = true

            // Reload to reflect the new entry
            await loadTodaysData()
            if !isViewingToday {
                await loadEntriesForSelectedDate()
            }

            if result.xpEarned > 0 { lastEarnedXP = result.xpEarned }

            deletionTask = Task {
                do {
                    try await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled {
                        await MainActor.run {
                            showUndoToast = false
                            recentlyDeleted = nil
                            deletionTask = nil
                            isQuickLogUndo = false
                        }
                    }
                } catch {}
            }
        } catch {
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif
            showToastMessage("Couldn't log — try again")
        }
    }

    /// Toggles favorite status for a food
    ///
    /// Applies to ALL entries with matching fingerprint.
    ///
    /// - Parameter entry: The food entry to toggle favorite
    func toggleFavorite(_ entry: FoodEntry) async {
        do {
            try await coordinator.toggleFavorite(entry)

            // Light haptic feedback
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif

            // Reload favorites and recent foods (favorite status may affect display)
            await loadFavorites()
            await loadRecentFoods()

            // Also reload today's entries if the entry is from today
            await loadTodaysData()

        } catch {
            print("Favorite toggle error: \(error)")
        }
    }

    /// Returns true if an entry is favorited
    func isFavorited(_ entry: FoodEntry) -> Bool {
        entry.isFavorite
    }

    // MARK: - Bundle Operations

    /// Deletes all food entries belonging to the given bundle.
    func deleteBundle(bundleId: String) async {
        let bundleEntries = displayedEntries.filter { $0.mealBundleId == bundleId }
        for entry in bundleEntries {
            try? await coordinator.deleteFoodEntry(entry)
        }
        await loadTodaysData()
        if !isViewingToday {
            await loadEntriesForSelectedDate()
        }
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    // MARK: - Water (WATER-1)

    /// Adds one cup. The published count is set from the method's RETURN value — no
    /// optimistic bump, so the view never renders a number the store does not hold.
    /// Failure leaves the count exactly where it was.
    func incrementWater() async {
        guard let newCount = try? await coordinator.incrementWater() else { return }
        waterCupCount = newCount
    }

    /// Removes one cup (floored at 0). A no-op at 0, including when today has no row.
    func decrementWater() async {
        guard let newCount = try? await coordinator.decrementWater() else { return }
        waterCupCount = newCount
    }

    // MARK: - Drag and Drop

    /// Reassigns a food entry to a new meal type (used for drag-and-drop).
    func updateMealType(of entry: FoodEntry, to mealType: MealType) async {
        do {
            try await coordinator.updateMealType(of: entry, to: mealType)
            await loadTodaysData()
            if !isViewingToday {
                await loadEntriesForSelectedDate()
            }
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        } catch {
            showToastMessage("Couldn't move item")
        }
    }

    // MARK: - AI Meal Recognition

    /// Opens the DescribeMealView sheet, pre-configured with the pending meal type.
    func openDescribeMeal() {
        formMealType = pendingMealType
        mealDescriptionInput = ""
        describeCategory = .meal
        describeAmountInput = ""
        describeExtrasInput = ""
        recognitionError = nil
        recognizedItems = []
        loggedFingerprints = []
        isRecognizing = false
        recognitionTask?.cancel()
        recognitionTask = nil
        describeMealPhotoData = nil
        isAttachingDescribeMealPhoto = false
        showingDescribeMeal = true
    }

    /// Sends the meal description (and optional photo) to the AI recognition service.
    ///
    /// Request lifecycle rules:
    /// - Only one request active at a time (cancels prior).
    /// - Minimum 1s between request starts (rate gate).
    /// - Results are discarded if the task is cancelled or the sheet closed.
    func recognizeMeal() async {
        // AIPROXY-1b: defense in depth. DescribeMealView shows the guest card instead of
        // the input UI, so a guest has no way to reach this — but the proxy requires an
        // authenticated caller, and a guest request could only fail. Unreachable by design.
        guard !coordinator.isGuest else {
            print("[AIFoodRecognition] Guest reached recognizeMeal — blocked (view-layer gate should have prevented this)")
            return
        }

        let trimmed = mealDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        let hasImage = describeMealPhotoData != nil
        guard hasText || hasImage else { return }

        // Rate gate: ignore if less than 1s since last start
        if let lastStart = lastRecognitionStart, Date().timeIntervalSince(lastStart) < 1.0 {
            return
        }

        // Cancel any prior in-flight request
        recognitionTask?.cancel()

        lastRecognitionStart = Date()
        isRecognizing = true
        recognitionError = nil

        // Capture photo data and structured inputs before entering the task (avoid cross-actor access)
        let imageData = describeMealPhotoData
        let category = describeCategory
        let trimmedAmount = describeAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExtras = describeExtrasInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = Task {
            defer {
                if !Task.isCancelled {
                    isRecognizing = false
                }
                recognitionTask = nil
            }

            do {
                let result = try await aiService.recognize(
                    description: hasText ? trimmed : nil,
                    imageData: imageData,
                    category: category,
                    amount: trimmedAmount.isEmpty ? nil : trimmedAmount,
                    extras: trimmedExtras.isEmpty ? nil : trimmedExtras
                )

                // Guard: only apply results if not cancelled and sheet still open
                guard !Task.isCancelled, showingDescribeMeal else { return }

                recognizedItems = result.items

                // Close input sheet, then open review after animation
                showingDescribeMeal = false
                try await Task.sleep(for: .milliseconds(400))

                guard !Task.isCancelled else { return }
                showingRecognitionReview = true

            } catch is CancellationError {
                print("[AIFoodRecognition] Request cancelled")
            } catch AIFoodRecognitionError.needsClarification(let question) {
                guard !Task.isCancelled, showingDescribeMeal else { return }
                // Too vague to estimate anything: surface the model's clarifying question.
                recognitionError = question
            } catch let error as AIFoodRecognitionError {
                guard !Task.isCancelled, showingDescribeMeal else { return }
                recognitionError = error.userMessage
            } catch {
                guard !Task.isCancelled, showingDescribeMeal else { return }
                recognitionError = "Something went wrong. Try again or add food manually."
            }
        }

        recognitionTask = task
    }

    /// Cancels any in-flight AI recognition request and resets loading state.
    ///
    /// AILOG-1c: deliberately does NOT clear `describeMealPhotoData`. The only caller is the
    /// describe sheet's `onDisappear`, which also fires on the SUCCESS path — `recognizeMeal()`
    /// sets `showingDescribeMeal = false` before presenting the review sheet — so clearing here
    /// destroyed the meal photo in transit and `logRecognizedItems` always stamped nil.
    /// The photo's lifetime is bounded by `openDescribeMeal()` (session-start reset) and
    /// `clearDescribeMealPhoto()` (the user's explicit X); neither is timing-dependent.
    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecognizing = false
    }

    // MARK: - Describe Meal Photo Handling

    /// Processes an image for the describe-meal flow using an off-MainActor pipeline:
    /// 1. Downsample during decode (longest edge ≤ 1568px) — never fully decodes original.
    /// 2. Normalize orientation (physically rotate pixels upright).
    /// 3. Iteratively compress to JPEG < 1MB.
    ///
    /// Only the final JPEG `Data` is published to `describeMealPhotoData` on MainActor.
    func attachDescribeMealPhoto(_ image: UIImage) async {
        isAttachingDescribeMealPhoto = true

        do {
            let jpegData = try await Self.processImageForRecognition(image)
            describeMealPhotoData = jpegData
            print("[AIFoodRecognition] Photo attached — \(jpegData.count) bytes")

            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        } catch {
            print("[AIFoodRecognition] Photo processing failed: \(error)")
            recognitionError = "Couldn't process the photo. You can still analyze with text."
            describeMealPhotoData = nil
        }

        isAttachingDescribeMealPhoto = false
    }

    /// Clears the describe-meal photo.
    func clearDescribeMealPhoto() {
        describeMealPhotoData = nil

        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// Off-MainActor image processing pipeline.
    /// Downsample → normalize orientation → JPEG compress to < 1MB.
    private static nonisolated func processImageForRecognition(_ image: UIImage) throws -> Data {
        let maxDimension: CGFloat = 1568
        let maxBytes = 1_000_000

        // Step 1: Get JPEG data from the UIImage to create a CGImageSource for downsampling.
        // This avoids holding the full-resolution decoded bitmap.
        guard let sourceData = image.jpegData(compressionQuality: 1.0) else {
            throw ImageProcessingError.encodingFailed
        }

        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw ImageProcessingError.encodingFailed
        }

        // Determine if downsampling is needed
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // normalizes orientation
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessingError.encodingFailed
        }

        // Step 2: The thumbnail is already orientation-normalized via kCGImageSourceCreateThumbnailWithTransform.
        // Create a UIImage from the CGImage (orientation .up since pixels are physically rotated).
        let normalizedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

        // Step 3: Iterative JPEG compression to < 1MB
        var quality: CGFloat = 0.7
        guard var data = normalizedImage.jpegData(compressionQuality: quality) else {
            throw ImageProcessingError.encodingFailed
        }

        while data.count > maxBytes && quality > 0.1 {
            quality -= 0.1
            if let compressed = normalizedImage.jpegData(compressionQuality: quality) {
                data = compressed
            } else {
                break
            }
        }

        guard data.count <= maxBytes else {
            throw ImageProcessingError.tooLarge
        }

        return data
    }

    private enum ImageProcessingError: Error {
        case encodingFailed
        case tooLarge
    }

    /// Logs the reviewed/edited recognized items through the existing addFoodEntry path.
    ///
    /// Each included item becomes one `FoodEntry`. `toxinScore` is the AI's per-item
    /// estimate (service-normalized, fallback 30), and the advanced micros
    /// (fiber/sugar/sodium/saturatedFat/cholesterol/potassium) pass through when present
    /// (`nil` stored as `nil`). `mealType` comes from `formMealType`.
    ///
    /// MEALPHOTO-1: 2+ items log as ONE meal bundle and the describe-meal photo goes on the
    /// first successfully logged entry only (the bundle row renders it); a single item logs
    /// as a solo entry with the photo attached, exactly as before.
    ///
    /// AILOG-1b: captures each logged entry's exact fingerprint into `loggedFingerprints`
    /// (the review strip's Favorite gate) and leaves the review sheet OPEN so the destination
    /// strip — including the now-enabled Favorite chip — stays usable; the user dismisses it
    /// with Cancel. A non-empty `loggedFingerprints` also makes re-invocation a no-op, so a
    /// second Log tap can't double-log.
    /// - Parameter items: The reviewed items to log.
    func logRecognizedItems(_ items: [RecognizedFoodItem]) async {
        guard !isSubmittingForm, loggedFingerprints.isEmpty else { return }
        isSubmittingForm = true

        // The session photo in effect AT LOG TIME, read before anything can clear it
        // (nil when the user attached none → entries stay photo-less).
        //
        // MEALPHOTO-1: a recognition of 2+ items logs as ONE meal bundle (the same
        // `mealBundleId` mechanism the saved-meal flow uses) instead of N sibling solo
        // entries. The BUNDLE ROW carries the photo and the items inside are photo-less:
        // the photo is stamped on the FIRST item that logs successfully, so `bundleRow`'s
        // `compactMap(\.photoData).first` finds it. A single-item recognition is unchanged
        // — a solo entry with the photo attached (nil bundle id/name = today's path).
        // Deletion edge: if the user deletes the photo-holding item out of the bundle, the
        // bundle simply renders photo-less. Accepted — the photo is not re-homed.
        let mealPhoto = describeMealPhotoData

        // Bundle identity for a multi-item recognition; both nil for a single item.
        // Name precedence: the typed meal description, else the Dish destination's
        // derivation over the item names (`RecognizedFoodsReviewView.truncateDishName`,
        // the one and only dish-name helper — never a second implementation).
        let isBundle = items.count >= 2
        let bundleId: String? = isBundle ? UUID().uuidString : nil
        let bundleName: String? = {
            guard isBundle else { return nil }
            let trimmedDish = mealDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedDish.isEmpty
                ? RecognizedFoodsReviewView.truncateDishName(items.map(\.name).joined(separator: " + "))
                : trimmedDish
        }()

        var totalXP = 0
        var loggedCount = 0
        var fingerprints: [FoodFingerprint] = []
        // Set once the photo has been stamped onto a SUCCESSFULLY logged entry — so a
        // throwing first item hands the photo to the first item that actually lands.
        var photoAssigned = false

        for item in items {
            let itemPhoto = photoAssigned ? nil : mealPhoto
            do {
                let result = try await coordinator.addFoodEntry(
                    name: item.name,
                    calories: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    toxinScore: item.toxinScore,
                    date: selectedDate,
                    photoData: itemPhoto,
                    mealType: formMealType,
                    fiber: item.fiber,
                    sugar: item.sugar,
                    sodium: item.sodium,
                    saturatedFat: item.saturatedFat,
                    cholesterol: item.cholesterol,
                    potassium: item.potassium,
                    mealBundleId: bundleId,
                    mealBundleName: bundleName
                )
                if itemPhoto != nil { photoAssigned = true }
                totalXP += result.xpEarned
                loggedCount += 1
                // The exact fingerprint the logged entry carries (never recomputed).
                fingerprints.append(FoodFingerprint(from: result.entry))
            } catch {
                print("[AIFoodRecognition] Failed to log '\(item.name)': \(error)")
            }
        }

        isSubmittingForm = false
        loggedFingerprints = fingerprints

        // Refresh data
        await loadTodaysData()
        if !isViewingToday {
            await loadEntriesForSelectedDate()
        }

        // Show success toast
        if loggedCount > 0 {
            let xpText = totalXP > 0 ? " (+\(totalXP) XP)" : ""
            showToastMessage("\(loggedCount) item\(loggedCount == 1 ? "" : "s") logged\(xpText)")
            // TUT-2 aiLog detection (Decision 2) — the describe path's log-success. The SOLE
            // aiLog site as of TUTFIX-1 (the step was retargeted off the barcode-only Home
            // Quick Scan); the membership guard in completeTutorialStep dedups if any future
            // flow ever hits both.
            if TutorialProgress.shared.shouldAttempt(TutorialCatalog.aiLogId) {
                Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.aiLogId) }
            }
        }
    }

    // MARK: - Toast Management

    /// Shows a toast message that auto-dismisses after 1.5 seconds
    /// - Parameter message: The message to display
    func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true

        // Auto-dismiss after 1.5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showToast = false
                }
            }
        }
    }

    /// Dismisses the toast immediately
    func dismissToast() {
        showToast = false
        toastMessage = nil
    }

    // MARK: - Helper Methods

    /// Formats a relative time string (e.g., "2 days ago", "Yesterday")
    func relativeTimeString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days < 7 {
                return "\(days) days ago"
            } else if days < 14 {
                return "1 week ago"
            } else {
                let weeks = days / 7
                return "\(weeks) weeks ago"
            }
        }
    }
}

// MARK: - Mock Data for Previews

extension FoodEntry {
    /// Mock recent foods for SwiftUI previews
    static var mockRecentFoods: [FoodEntry] {
        [
            FoodEntry(
                name: "Grilled Chicken Salad",
                date: Date().addingTimeInterval(-86400),
                calories: 450,
                protein: 42.0,
                carbs: 25.0,
                fat: 18.0,
                toxinScore: 15,
                isFavorite: true
            ),
            FoodEntry(
                name: "Protein Shake",
                date: Date().addingTimeInterval(-172800),
                calories: 320,
                protein: 30.0,
                carbs: 15.0,
                fat: 8.0,
                toxinScore: 25,
                isFavorite: false
            ),
            FoodEntry(
                name: "Greek Yogurt with Berries",
                date: Date().addingTimeInterval(-259200),
                calories: 180,
                protein: 15.0,
                carbs: 22.0,
                fat: 5.0,
                toxinScore: 10,
                isFavorite: true
            ),
            FoodEntry(
                name: "Avocado Toast",
                date: Date().addingTimeInterval(-345600),
                calories: 380,
                protein: 12.0,
                carbs: 35.0,
                fat: 22.0,
                toxinScore: 20,
                isFavorite: false
            ),
            FoodEntry(
                name: "Salmon with Vegetables",
                date: Date().addingTimeInterval(-432000),
                calories: 520,
                protein: 38.0,
                carbs: 20.0,
                fat: 28.0,
                toxinScore: 12,
                isFavorite: true
            )
        ]
    }
}
