//
//  AddFoodFormView.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Modal form for adding a new food entry
///
/// Features:
/// - Text field for food name
/// - Number inputs for calories and macros
/// - Toxin score slider (0-100)
/// - Form validation
/// - Save and Cancel buttons
struct AddFoodFormView: View {

    // MARK: - Properties

    /// Reference to the FoodLogViewModel
    @Bindable var viewModel: FoodLogViewModel

    /// Dismiss action for the sheet
    @Environment(\.dismiss) private var dismiss

    /// Settings manager for advanced nutrition toggle
    @State private var settings = SettingsManager.shared

    /// PhotosPicker selection for photo library
    @State private var photoPickerItem: PhotosPickerItem?

    /// Show action sheet for photo source selection
    @State private var showingPhotoSourceSheet = false

    /// Show purity score info sheet
    @State private var showingPurityScoreInfo = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    headerSection

                    // Photo capture section
                    photoCaptureSection

                    // Barcode scan section
                    barcodeScanSection

                    // Food name input
                    inputSection(
                        title: "Food Name",
                        icon: "fork.knife",
                        placeholder: "e.g., Grilled Chicken Salad",
                        text: $viewModel.formFoodName,
                        errorMessage: viewModel.formValidationErrors["foodName"]
                    )

                    // Nutrition inputs
                    VStack(spacing: DesignSystem.Spacing.md) {
                        HStack {
                            Text("Nutrition Info")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            // Show "per 100g" label if barcode was scanned
                            if viewModel.scannedBarcode != nil {
                                Text("(per 100g from barcode)")
                                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.warning)
                                    .padding(.horizontal, DesignSystem.Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.warning.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            Spacer()
                        }

                        // Serving size adjuster (only shown if barcode was scanned)
                        if viewModel.useServingSize && viewModel.scannedBarcode != nil {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    // Serving size input
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                        Text("Serving Size (grams)")
                                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.textSecondary)

                                        TextField("100", text: $viewModel.servingSize)
                                            .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.plain)
                                            .padding(DesignSystem.Spacing.md)
                                            .background(DesignSystem.Colors.cardBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                                            )
                                    }
                                    .frame(maxWidth: .infinity)

                                    // Calculate button
                                    VStack(spacing: DesignSystem.Spacing.xs) {
                                        Text(" ")
                                            .font(.system(size: DesignSystem.FontSizes.footnote))

                                        Button {
                                            viewModel.applyServingSize()
                                        } label: {
                                            Text("Calculate")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, DesignSystem.Spacing.md)
                                                .padding(.vertical, DesignSystem.Spacing.md)
                                                .background(DesignSystem.Colors.secondary)
                                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                        }
                                    }
                                }

                                Text("Enter grams consumed, then tap Calculate to adjust nutrition values")
                                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        }

                        // Calories
                        numberInputField(
                            title: "Calories",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.energy,
                            placeholder: "0",
                            text: $viewModel.formCalories,
                            unit: "cal",
                            errorMessage: viewModel.formValidationErrors["calories"]
                        )

                        // Protein
                        numberInputField(
                            title: "Protein",
                            icon: "leaf.fill",
                            iconColor: DesignSystem.Colors.primary,
                            placeholder: "0",
                            text: $viewModel.formProtein,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["protein"]
                        )

                        // Carbs
                        numberInputField(
                            title: "Carbs",
                            icon: "flame.fill",
                            iconColor: DesignSystem.Colors.warning,
                            placeholder: "0",
                            text: $viewModel.formCarbs,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["carbs"]
                        )

                        // Fat
                        numberInputField(
                            title: "Fat",
                            icon: "drop.fill",
                            iconColor: DesignSystem.Colors.secondary,
                            placeholder: "0",
                            text: $viewModel.formFat,
                            unit: "g",
                            errorMessage: viewModel.formValidationErrors["fat"]
                        )
                    }

                    // Advanced Nutrition Section (expandable)
                    if settings.trackAdvancedNutrition {
                        advancedNutritionSection
                    }

                    // Toxin score slider
                    toxinScoreSection

                    // Action buttons
                    actionButtons
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Add Food")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showingPhotoSourceSheet) {
                Button("Take Photo") {
                    viewModel.showCamera()
                }
                Button("Choose from Library") {
                    viewModel.showPhotoLibrary()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $viewModel.showingCameraPicker) {
                CameraPickerView { image in
                    Task {
                        await viewModel.selectPhoto(image)
                    }
                }
            }
            .photosPicker(isPresented: $viewModel.showingPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { oldValue, newValue in
                Task {
                    if let item = newValue,
                       let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.selectPhoto(image)
                    }
                    photoPickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $viewModel.showingBarcodeScanner) {
                BarcodeScannerView { barcode in
                    Task {
                        await viewModel.handleBarcodeScanned(barcode)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingManualBarcodeEntry) {
                ManualBarcodeEntryView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Subviews

    /// Photo capture section at top of form
    private var photoCaptureSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Photo (Optional)")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Button {
                showingPhotoSourceSheet = true
            } label: {
                ZStack {
                    if let selectedPhoto = viewModel.selectedPhoto {
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
                                            viewModel.removePhoto()
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
                    if viewModel.isProcessingPhoto {
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
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.selectedPhoto != nil)
        }
    }

    /// Header section with icon and description
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: DesignSystem.Sizes.thumbnailLarge, height: DesignSystem.Sizes.thumbnailLarge)

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text("Log Your Meal")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("Enter the nutritional information for your meal")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    /// Generic input section with optional error message
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
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    viewModel.validateField("foodName")
                }
        }
    }

    /// Number input field with icon, unit, and optional error message
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
        .onChange(of: text.wrappedValue) { oldValue, newValue in
            // Validate the specific field
            let fieldName = title.lowercased()
            viewModel.validateField(fieldName)
        }
    }

    /// Toxin score slider section
    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Purity Score")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        // Info button (44x44pt touch target)
                        Button {
                            showingPurityScoreInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }

                    Text("Lower is better (0-100)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Text("\(Int(viewModel.formToxinScore))")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(toxinScoreColor)
            }

            // Slider
            Slider(value: $viewModel.formToxinScore, in: 0...100, step: 1)
                .tint(toxinScoreColor)

            // Labels
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
        .sheet(isPresented: $showingPurityScoreInfo) {
            PurityScoreInfoSheet()
        }
    }

    /// Barcode scan section
    private var barcodeScanSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Quick Entry")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Button {
                viewModel.showBarcodeScanner()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Barcode icon
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.secondary.opacity(0.15))
                            .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Scan Barcode")
                            .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("Auto-fill nutrition from product database")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .strokeBorder(DesignSystem.Colors.secondary.opacity(0.25), lineWidth: 1.5)
                )
                .shadow(
                    color: DesignSystem.Shadows.card.color,
                    radius: DesignSystem.Shadows.card.radius / 2,
                    x: DesignSystem.Shadows.card.x,
                    y: DesignSystem.Shadows.card.y
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Enter Barcode Manually Button
            Button {
                viewModel.showManualBarcodeEntry()
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Keyboard icon
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.secondary.opacity(0.15))
                            .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                        Image(systemName: "keyboard")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Enter Barcode Manually")
                            .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("Type barcode number when camera isn't available")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .strokeBorder(DesignSystem.Colors.secondary.opacity(0.25), lineWidth: 1.5)
                )
                .shadow(
                    color: DesignSystem.Shadows.card.color,
                    radius: DesignSystem.Shadows.card.radius / 2,
                    x: DesignSystem.Shadows.card.x,
                    y: DesignSystem.Shadows.card.y
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Show loading indicator when fetching barcode data
            if viewModel.isLoadingBarcodeNutrition {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Looking up nutrition...")
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.top, DesignSystem.Spacing.xs)
            }

            // Show error if barcode lookup failed
            if let error = viewModel.barcodeError {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.warning)

                    Text(error)
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.warning)
                }
                .padding(.top, DesignSystem.Spacing.xs)
            }

            // Show success message if barcode was scanned
            if let barcode = viewModel.scannedBarcode, viewModel.barcodeError == nil, !viewModel.isLoadingBarcodeNutrition {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)

                    Text("Scanned: \(barcode)")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Spacer()

                    Button {
                        viewModel.clearBarcodeData()
                    } label: {
                        Text("Clear")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
                .padding(.top, DesignSystem.Spacing.xs)
            }
        }
    }

    /// Action buttons (Save and Cancel)
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            AppButton(
                title: "Save Meal",
                style: .primary,
                action: saveFood,
                isLoading: viewModel.isSubmittingForm,
                isDisabled: viewModel.isSubmittingForm || viewModel.isLoadingBarcodeNutrition,
                icon: "checkmark.circle.fill"
            )

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.top, DesignSystem.Spacing.md)
    }

    // MARK: - Advanced Nutrition Section

    /// Expandable section for advanced nutrition tracking
    private var advancedNutritionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Header with disclosure indicator
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isAdvancedNutritionExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)

                    Text("Advanced Nutrition")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Image(systemName: viewModel.isAdvancedNutritionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content
            if viewModel.isAdvancedNutritionExpanded {
                VStack(spacing: DesignSystem.Spacing.md) {
                    // Fiber (g)
                    advancedNutrientField(
                        title: "Fiber",
                        icon: "leaf.fill",
                        iconColor: DesignSystem.Colors.primary,
                        placeholder: "0",
                        text: $viewModel.formFiber,
                        unit: "g"
                    )

                    // Sugar (g)
                    advancedNutrientField(
                        title: "Sugar",
                        icon: "cube.fill",
                        iconColor: DesignSystem.Colors.warning,
                        placeholder: "0",
                        text: $viewModel.formSugar,
                        unit: "g"
                    )

                    // Sodium (mg)
                    advancedNutrientField(
                        title: "Sodium",
                        icon: "drop.fill",
                        iconColor: DesignSystem.Colors.secondary,
                        placeholder: "0",
                        text: $viewModel.formSodium,
                        unit: "mg"
                    )

                    // Saturated Fat (g)
                    advancedNutrientField(
                        title: "Sat. Fat",
                        icon: "heart.fill",
                        iconColor: DesignSystem.Colors.danger,
                        placeholder: "0",
                        text: $viewModel.formSaturatedFat,
                        unit: "g"
                    )

                    // Cholesterol (mg)
                    advancedNutrientField(
                        title: "Cholesterol",
                        icon: "heart.circle.fill",
                        iconColor: DesignSystem.Colors.energy,
                        placeholder: "0",
                        text: $viewModel.formCholesterol,
                        unit: "mg"
                    )

                    // Potassium (mg)
                    advancedNutrientField(
                        title: "Potassium",
                        icon: "bolt.fill",
                        iconColor: DesignSystem.Colors.growth,
                        placeholder: "0",
                        text: $viewModel.formPotassium,
                        unit: "mg"
                    )
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Input field for advanced nutrients
    private func advancedNutrientField(
        title: String,
        icon: String,
        iconColor: Color,
        placeholder: String,
        text: Binding<String>,
        unit: String
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
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
                    .frame(width: 60)

                Text(unit)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 25, alignment: .leading)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Computed Properties

    /// Color for toxin score (green to red gradient)
    private var toxinScoreColor: Color {
        if viewModel.formToxinScore < 30 {
            return DesignSystem.Colors.primary
        } else if viewModel.formToxinScore < 60 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    // MARK: - Actions

    /// Validates and saves the food entry
    private func saveFood() {
        Task {
            await viewModel.submitForm()

            // Dismiss the sheet if successful (no error)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}

// MARK: - Manual Barcode Entry View

/// Sheet for manually entering a barcode number
struct ManualBarcodeEntryView: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "keyboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                // Instructions
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Enter Barcode Number")
                        .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Enter the UPC or EAN barcode from the product packaging")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                // Barcode input field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    TextField("e.g., 737628064502", text: $viewModel.manualBarcodeInput)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        .focused($isFocused)

                    // Helper text
                    Text("Note: Nutrition shown is per 100g, not per serving")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .padding(.top, DesignSystem.Spacing.sm)
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)

                Spacer()

                // Action buttons
                VStack(spacing: DesignSystem.Spacing.md) {
                    AppButton(
                        title: "Look Up Nutrition",
                        style: .primary,
                        action: {
                            Task {
                                await viewModel.submitManualBarcode()
                            }
                        },
                        isDisabled: viewModel.manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        icon: "magnifyingglass"
                    )

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    /// Helper view for displaying example barcodes
    private func barcodeExample(_ barcode: String, product: String) -> some View {
        Button {
            viewModel.manualBarcodeInput = barcode
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(barcode)
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)

                Text("(\(product))")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Add Food Form") {
    // Create mock view model
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let coordinator = AppCoordinator(modelContext: context)
    let viewModel = FoodLogViewModel(coordinator: coordinator)

    return AddFoodFormView(viewModel: viewModel)
}
