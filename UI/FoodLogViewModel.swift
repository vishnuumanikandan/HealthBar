//
//  FoodLogViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Food Log feature
///
/// Manages today's food entries, daily goals, and progress calculations.
/// Uses @Observable macro (not @ObservableObject) for iOS 17+ compatibility.
@Observable
@MainActor
final class FoodLogViewModel {

    // MARK: - Properties

    /// Reference to the app coordinator for data operations
    private let coordinator: AppCoordinator

    /// Barcode service for nutrition lookup
    private let barcodeService: BarcodeService

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

    // MARK: - Toast State

    /// Toast message to display
    var toastMessage: String?

    /// Whether toast is currently visible
    var showToast: Bool = false

    // MARK: - Computed Totals (Raw Data Only)

    /// Total calories consumed today
    var totalCalories: Int {
        todaysSummary?.totalCalories ?? 0
    }

    /// Total protein consumed today (in grams)
    var totalProtein: Double {
        todaysSummary?.totalProtein ?? 0.0
    }

    /// Total carbs consumed today (in grams)
    var totalCarbs: Double {
        todaysSummary?.totalCarbs ?? 0.0
    }

    /// Total fat consumed today (in grams)
    var totalFat: Double {
        todaysSummary?.totalFat ?? 0.0
    }

    /// Total toxin score for today
    var totalToxinScore: Int {
        todaysSummary?.totalToxinScore ?? 0
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
        guard let goal = currentGoal else {
            return "\(totalCalories)"
        }
        return "\(totalCalories)\n/ \(goal.calorieTarget)"
    }

    // MARK: - UI State

    /// Loading state indicator
    var isLoading: Bool = false

    /// Controls visibility of add food sheet
    var showingAddFood: Bool = false

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

    /// Tracks whether current undo is for a quick log (true) or delete (false)
    /// Quick log undo = delete the newly created entry
    /// Delete undo = restore the entry to UI
    private var isQuickLogUndo: Bool = false

    // MARK: - Edit State

    /// Entry currently being edited
    var editingEntry: FoodEntry?

    /// Show edit sheet
    var showingEditSheet: Bool = false

    // MARK: - Initialization

    /// Initializes the view model with an app coordinator
    /// - Parameters:
    ///   - coordinator: The app coordinator for business logic
    ///   - barcodeService: Service for barcode nutrition lookup (defaults to new instance)
    init(coordinator: AppCoordinator, barcodeService: BarcodeService = BarcodeService()) {
        self.coordinator = coordinator
        self.barcodeService = barcodeService
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
                photoData: photoData,
                barcodeUPC: barcodeUPC,
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

            // Reload data to get updated summary
            await loadTodaysData()

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

        // Remove from UI list immediately
        todaysEntries.removeAll { $0.id == entry.id }

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
                try await Task.sleep(for: .seconds(5))

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

            // Reload data to recalculate everything
            await loadTodaysData()

            // Hide undo toast
            showUndoToast = false
            recentlyDeleted = nil
            deletionTask = nil

        } catch {
            print("Delete error: \(error)")
            // If permanent delete fails, restore to UI
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                todaysEntries.append(entry)
                todaysEntries.sort { $0.date > $1.date }
            }

            // Error haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            showToastMessage("Delete failed - restored")
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

    // MARK: - Form Management

    /// Resets all form fields to their default values
    func resetForm() {
        formFoodName = ""
        formCalories = ""
        formProtein = ""
        formCarbs = ""
        formFat = ""
        formToxinScore = 30.0
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
    /// Converts the image to JPEG data with compression, validates size (< 1MB),
    /// and stores it for saving. Runs asynchronously to prevent UI blocking.
    func selectPhoto(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        // Convert to JPEG with 0.7 quality
        guard var data = image.jpegData(compressionQuality: 0.7) else {
            errorMessage = "Failed to process photo"
            return
        }

        // Validate and compress if needed (< 1MB = 1,000,000 bytes)
        let maxSize = 1_000_000
        var quality: CGFloat = 0.7

        // Iteratively reduce quality if over 1MB
        while data.count > maxSize && quality > 0.1 {
            quality -= 0.1
            if let compressedData = image.jpegData(compressionQuality: quality) {
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

        // Success - store photo
        photoData = data
        selectedPhoto = image

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
            recentFoods = try await coordinator.getRecentUniqueFoods(limit: 15, daysBack: 30)
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
            let result = try await coordinator.quickLogFood(entry)

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

            // Reload today's data to update progress
            await loadTodaysData()

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

    // MARK: - Toast Management

    /// Shows a toast message that auto-dismisses after 1.5 seconds
    /// - Parameter message: The message to display
    private func showToastMessage(_ message: String) {
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
