//
//  EditMealView.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Sheet for editing an existing food entry
///
/// Features:
/// - Pre-filled form with existing values
/// - Shows existing photo if present
/// - All fields editable (name, calories, macros, photo, toxin score)
/// - Save Changes and Cancel buttons
struct EditMealView: View {

    // MARK: - Properties

    /// The entry being edited
    let entry: FoodEntry

    /// Callback when save is complete
    let onSave: (String, Int, Double, Double, Double, Int, Data?) -> Void

    /// Callback when cancelled
    let onCancel: () -> Void

    /// Dismiss action
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var foodName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var toxinScore: Double = 30.0

    // MARK: - Photo State

    @State private var selectedPhoto: UIImage?
    @State private var photoData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingPhotoSourceSheet = false
    @State private var showingCameraPicker = false
    @State private var showingPhotoPicker = false
    @State private var isProcessingPhoto = false

    // MARK: - UI State

    @State private var isSaving = false
    @State private var validationErrors: [String: String] = [:]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    headerSection

                    // Photo section
                    photoCaptureSection

                    // Food name input
                    inputSection(
                        title: "Food Name",
                        icon: "fork.knife",
                        placeholder: "e.g., Grilled Chicken Salad",
                        text: $foodName,
                        errorMessage: validationErrors["foodName"]
                    )

                    // Nutrition inputs
                    VStack(spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("Nutrition Info")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                        }

                        // Calories
                        numberInputField(
                            title: "Calories",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.energy,
                            placeholder: "0",
                            text: $calories,
                            unit: "cal",
                            errorMessage: validationErrors["calories"]
                        )

                        // Protein
                        numberInputField(
                            title: "Protein",
                            icon: "leaf.fill",
                            iconColor: DesignSystem.Colors.primary,
                            placeholder: "0",
                            text: $protein,
                            unit: "g",
                            errorMessage: validationErrors["protein"]
                        )

                        // Carbs
                        numberInputField(
                            title: "Carbs",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.warning,
                            placeholder: "0",
                            text: $carbs,
                            unit: "g",
                            errorMessage: validationErrors["carbs"]
                        )

                        // Fat
                        numberInputField(
                            title: "Fat",
                            icon: "drop.fill",
                            iconColor: DesignSystem.Colors.secondary,
                            placeholder: "0",
                            text: $fat,
                            unit: "g",
                            errorMessage: validationErrors["fat"]
                        )
                    }

                    // Toxin score slider
                    toxinScoreSection

                    // Helper text
                    helperText

                    // Action buttons
                    actionButtons
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Edit Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showingPhotoSourceSheet) {
                Button("Take Photo") {
                    showingCameraPicker = true
                }
                Button("Choose from Library") {
                    showingPhotoPicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingCameraPicker) {
                CameraPickerView { image in
                    Task {
                        await selectPhoto(image)
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { oldValue, newValue in
                Task {
                    if let item = newValue,
                       let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await selectPhoto(image)
                    }
                    photoPickerItem = nil
                }
            }
            .onAppear {
                loadEntryData()
            }
        }
    }

    // MARK: - Subviews

    /// Header section
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.secondary.opacity(0.15))
                    .frame(width: DesignSystem.Sizes.thumbnailLarge, height: DesignSystem.Sizes.thumbnailLarge)

                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.secondary)
            }

            Text("Edit Meal")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Update the details for this entry")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// Photo capture section
    private var photoCaptureSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Photo (Optional)")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Button {
                showingPhotoSourceSheet = true
            } label: {
                ZStack {
                    if let selectedPhoto = selectedPhoto {
                        // Show photo preview
                        Image(uiImage: selectedPhoto)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                    .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
                            )
                            .overlay(
                                // Remove button in top-right corner
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button {
                                            removePhoto()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 24, weight: .semibold))
                                                .foregroundColor(.white)
                                                .background(
                                                    Circle()
                                                        .fill(Color.black.opacity(0.5))
                                                        .frame(width: 32, height: 32)
                                                )
                                        }
                                        .padding(DesignSystem.Spacing.sm)
                                    }
                                    Spacer()
                                }
                            )
                    } else {
                        // Show placeholder with dashed border
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.textTertiary)

                            Text("Add Photo")
                                .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(DesignSystem.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                .strokeBorder(
                                    DesignSystem.Colors.border,
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                )
                        )
                    }

                    // Processing overlay
                    if isProcessingPhoto {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .fill(Color.black.opacity(0.5))
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            )
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPhoto != nil)
        }
    }

    /// Generic input section
    private func inputSection(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                if let errorMessage = errorMessage {
                    Text("• \(errorMessage)")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.danger)
                }
            }

            TextField(placeholder, text: text)
                .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(errorMessage != nil ? DesignSystem.Colors.danger : DesignSystem.Colors.border, lineWidth: 1)
                )
        }
    }

    /// Number input field
    private func numberInputField(
        title: String,
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        unit: String,
        errorMessage: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Title
                Text(title)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .frame(width: 80, alignment: .leading)

                Spacer()

                // Input field
                HStack(spacing: DesignSystem.Spacing.xs) {
                    TextField(placeholder, text: text)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)

                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .stroke(errorMessage != nil ? DesignSystem.Colors.danger : DesignSystem.Colors.border, lineWidth: 1)
                )
            }

            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
                    .padding(.leading, DesignSystem.Sizes.iconCircle + DesignSystem.Spacing.md)
            }
        }
    }

    /// Toxin score slider section
    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Toxin Score")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Lower is better (0-100)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Text("\(Int(toxinScore))")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(toxinScoreColor)
            }

            Slider(value: $toxinScore, in: 0...100, step: 1)
                .tint(toxinScoreColor)

            HStack {
                Text("Clean")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                Text("Processed")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
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

    /// Helper text
    private var helperText: some View {
        Text("Changing nutrition may affect favorites")
            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Action buttons
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            AppButton(
                title: "Save Changes",
                style: .primary,
                action: saveChanges,
                isLoading: isSaving,
                isDisabled: isSaving || !isFormValid,
                icon: "checkmark.circle.fill"
            )

            Button {
                onCancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.top, DesignSystem.Spacing.md)
    }

    // MARK: - Computed Properties

    /// Color for toxin score
    private var toxinScoreColor: Color {
        if toxinScore < 30 {
            return DesignSystem.Colors.primary
        } else if toxinScore < 60 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    /// Check if form is valid
    private var isFormValid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(calories) != nil &&
        Double(protein) != nil &&
        Double(carbs) != nil &&
        Double(fat) != nil
    }

    // MARK: - Methods

    /// Loads existing entry data into form
    private func loadEntryData() {
        foodName = entry.name
        calories = String(entry.calories)
        protein = String(format: "%.1f", entry.protein)
        carbs = String(format: "%.1f", entry.carbs)
        fat = String(format: "%.1f", entry.fat)
        toxinScore = Double(entry.toxinScore)

        // Load existing photo if present
        if let data = entry.photoData, let image = UIImage(data: data) {
            selectedPhoto = image
            photoData = data
        }
    }

    /// Saves changes
    private func saveChanges() {
        guard isFormValid else { return }

        isSaving = true

        onSave(
            foodName.trimmingCharacters(in: .whitespacesAndNewlines),
            Int(calories) ?? 0,
            Double(protein) ?? 0,
            Double(carbs) ?? 0,
            Double(fat) ?? 0,
            Int(toxinScore),
            photoData
        )

        dismiss()
    }

    /// Selects and processes a photo
    private func selectPhoto(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        guard var data = image.jpegData(compressionQuality: 0.7) else { return }

        let maxSize = 1_000_000
        var quality: CGFloat = 0.7

        while data.count > maxSize && quality > 0.1 {
            quality -= 0.1
            if let compressedData = image.jpegData(compressionQuality: quality) {
                data = compressedData
            } else {
                break
            }
        }

        if data.count <= maxSize {
            photoData = data
            selectedPhoto = image
        }
    }

    /// Removes the current photo
    private func removePhoto() {
        selectedPhoto = nil
        photoData = nil
    }
}

// MARK: - Preview

#Preview("Edit Meal") {
    let sampleEntry = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )

    return EditMealView(
        entry: sampleEntry,
        onSave: { name, cal, pro, carb, fat, toxin, photo in
            print("Saved: \(name)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
