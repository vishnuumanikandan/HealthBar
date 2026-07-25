//
//  DescribeMealView.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import SwiftUI
import PhotosUI

/// Text input sheet where the user types a natural-language meal description
/// and can optionally attach one photo for better accuracy.
///
/// Presented from AddFoodChoiceSheet → "Describe Your Meal".
/// On success the ViewModel closes this sheet and opens RecognizedFoodsReviewView.
struct DescribeMealView: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var showingPhotoSourceSheet: Bool = false
    @State private var photoPickerItem: PhotosPickerItem? = nil

    private var tc: ThemeColors { settings.activeColors }

    private var canAnalyze: Bool {
        let hasText = !viewModel.mealDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = viewModel.describeMealPhotoData != nil
        return (hasText || hasImage) && !viewModel.isRecognizing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drag handle
                AdaptivePillShapeStyle()
                    .fill(tc.primary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                // Header
                HStack {
                    Text("Describe Your Meal")
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        // Category chips (AILOG-1b) — directly under the header.
                        categoryChipRow

                        // Error / clarification message
                        if let error = viewModel.recognitionError {
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(AppFont.bold(14))
                                    .foregroundColor(DesignSystem.Colors.warning)
                                Text(error)
                                    .font(AppFont.regular(13))
                                    .foregroundColor(DesignSystem.Colors.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DesignSystem.Spacing.md)
                            .adaptiveCard(
                                borderColor: DesignSystem.Colors.warning.opacity(0.4),
                                fillColor: DesignSystem.Colors.warning.opacity(0.08)
                            )
                            .accessibilityLabel("Error: \(error)")
                        }

                        composerSection
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
            }
            .background(tc.cardBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.textSecondary)
                        .accessibilityLabel("Cancel meal description")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.CornerRadius.xl)
        .onAppear {
            isInputFocused = true
        }
        .onDisappear {
            viewModel.cancelRecognition()
        }
        .confirmationDialog("Choose Photo Source", isPresented: $showingPhotoSourceSheet) {
            Button("Take Photo") {
                viewModel.showingDescribeMealCameraPicker = true
            }
            Button("Choose from Library") {
                viewModel.showingDescribeMealPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.showingDescribeMealCameraPicker) {
            CameraPickerView { image in
                Task {
                    await viewModel.attachDescribeMealPhoto(image)
                }
            }
        }
        .photosPicker(isPresented: $viewModel.showingDescribeMealPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { oldValue, newValue in
            Task {
                if let item = newValue,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.attachDescribeMealPhoto(image)
                }
                photoPickerItem = nil
            }
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerSection: some View {
        // Field labels come from the selected category's 1a table — the view hardcodes zero
        // copy for these three fields; each label sits persistently above its input.
        let labels = viewModel.describeCategory.fieldLabels

        // Field 1 — the "what" (gates Analyze; keeps binding, TextEditor sizing, focus-on-appear).
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(labels.item)
                .font(AppFont.display(14))
                .foregroundColor(tc.textSecondary)

            TextEditor(text: $viewModel.mealDescriptionInput)
                .font(AppFont.regular(15))
                .foregroundColor(tc.textPrimary)
                .frame(minHeight: 100, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .focused($isInputFocused)
                .padding(DesignSystem.Spacing.sm)
                .adaptiveCard(
                    borderColor: tc.primary.opacity(0.3),
                    fillColor: tc.primaryBackground
                )
                .accessibilityLabel(labels.item)
        }

        // Field 2 — amount/size (optional).
        describeField(label: labels.amount, text: $viewModel.describeAmountInput)

        // Field 3 — extras (optional).
        describeField(label: labels.extras, text: $viewModel.describeExtrasInput)

        // Photo attach control
        photoSection

        // Combined-input helper text (when photo attached)
        if viewModel.describeMealPhotoData != nil {
            Text("Describe what's in the photo for better accuracy")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        loadingIndicator

        // Analyze button
        AppButton(
            title: "Analyze",
            style: .primary,
            action: { Task { await viewModel.recognizeMeal() } },
            isDisabled: !canAnalyze,
            icon: "sparkles"
        )
        .accessibilityLabel("Analyze meal description")
        .accessibilityHint(!canAnalyze ? "Enter a meal description or add a photo first" : "Tap to estimate nutrition")

        // Manual entry fallback
        Button {
            dismiss()
            viewModel.openAddFoodFormAfterDelay()
        } label: {
            Text("Enter manually instead")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .underline()
        }
        .accessibilityLabel("Enter food manually instead")
    }

    // MARK: - Category Chips (AILOG-1b)

    /// Horizontal, single-select category row under the header. Renders every
    /// `FoodCategory.allCases` in declaration order; `.meal` is the default. Switching a
    /// category swaps the field labels/placeholders but never clears typed field contents.
    @ViewBuilder
    private var categoryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(FoodCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 2) // keep chip outlines off the clip edge
        }
    }

    private func categoryChip(_ category: FoodCategory) -> some View {
        let isSelected = viewModel.describeCategory == category
        return Button {
            viewModel.describeCategory = category
        } label: {
            Text(category.displayName)
                .font(AppFont.bold(12))
                .foregroundColor(isSelected ? .white : tc.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.xs + 2)
                .background(isSelected ? tc.primary : Color.clear)
                .clipShape(AdaptivePillShapeStyle())
                .overlay(
                    AdaptivePillShapeStyle()
                        .stroke(isSelected ? Color.clear : tc.primary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(category.displayName) category")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A single optional structured input (fields 2 and 3): a persistent table-sourced label
    /// above an empty-placeholder field.
    private func describeField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(AppFont.display(14))
                .foregroundColor(tc.textSecondary)

            TextField("", text: text)
                .font(AppFont.regular(15))
                .foregroundColor(tc.textPrimary)
                .padding(DesignSystem.Spacing.sm)
                .adaptiveCard(
                    borderColor: tc.primary.opacity(0.3),
                    fillColor: tc.primaryBackground
                )
                .accessibilityLabel(label)
        }
    }

    // MARK: - Loading Indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        if viewModel.isRecognizing {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .tint(tc.primary)
                Text("Estimating nutrition…")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
            .accessibilityLabel("Estimating nutrition")
        }
    }

    // MARK: - Photo Section

    @ViewBuilder
    private var photoSection: some View {
        if viewModel.isAttachingDescribeMealPhoto {
            // Processing state
            HStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .tint(tc.primary)
                Text("Processing photo…")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Processing photo")
        } else if let photoData = viewModel.describeMealPhotoData,
                  let uiImage = UIImage(data: photoData) {
            // Photo attached — thumbnail with remove button
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                        .accessibilityLabel("Attached meal photo")

                    Button {
                        viewModel.clearDescribeMealPhoto()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, tc.primary)
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Remove photo")
                }

                Spacer()
            }
        } else {
            // No photo — add photo button
            Button {
                showingPhotoSourceSheet = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "camera")
                        .font(AppFont.regular(14))
                    Text("Add photo")
                        .font(AppFont.regular(14))
                }
                .foregroundColor(tc.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Add photo")
            .accessibilityHint("Attach a photo of your meal for better accuracy")
        }
    }
}
