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
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
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

                        // Text input
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("What did you eat?")
                                .font(AppFont.bold(14))
                                .foregroundColor(tc.textSecondary)

                            TextEditor(text: $viewModel.mealDescriptionInput)
                                .font(AppFont.regular(15))
                                .foregroundColor(tc.textPrimary)
                                .frame(minHeight: 100, maxHeight: 160)
                                .scrollContentBackground(.hidden)
                                .focused($isInputFocused)
                                .overlay(alignment: .topLeading) {
                                    if viewModel.mealDescriptionInput.isEmpty {
                                        Text("e.g. grilled chicken breast, half cup rice, side salad")
                                            .font(AppFont.regular(14))
                                            .foregroundColor(tc.textTertiary)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(DesignSystem.Spacing.sm)
                                .adaptiveCard(
                                    borderColor: tc.primary.opacity(0.3),
                                    fillColor: tc.primaryBackground
                                )
                        }

                        // Photo attach control
                        photoSection

                        // Combined-input helper text (when photo attached)
                        if viewModel.describeMealPhotoData != nil {
                            Text("Describe what's in the photo for better accuracy")
                                .font(AppFont.regular(12))
                                .foregroundColor(tc.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Loading indicator
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

                        // Analyze button
                        Button {
                            Task { await viewModel.recognizeMeal() }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: "sparkles")
                                    .font(AppFont.bold(16))
                                Text("Analyze")
                                    .font(AppFont.bold(16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(
                                SettingsManager.shared.isCleanUI
                                    ? LinearGradient(colors: [DesignSystem.Colors.primary], startPoint: .top, endPoint: .bottom)
                                    : DesignSystem.Colors.band3Green
                            )
                            .clipShape(AdaptivePillShapeStyle())
                            .opacity(canAnalyze ? 1.0 : 0.5)
                        }
                        .disabled(!canAnalyze)
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
