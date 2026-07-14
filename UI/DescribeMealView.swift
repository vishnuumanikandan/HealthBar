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
    @FocusState private var isAnswerFocused: Bool
    @State private var showingPhotoSourceSheet: Bool = false
    @State private var photoPickerItem: PhotosPickerItem? = nil

    private var tc: ThemeColors { settings.activeColors }

    private var canAnalyze: Bool {
        let hasText = !viewModel.mealDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = viewModel.describeMealPhotoData != nil
        return (hasText || hasImage) && !viewModel.isRecognizing
    }

    private var canSendAnswer: Bool {
        !viewModel.detailAnswerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isRecognizing
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

                        // The model needs one more detail before it can estimate well —
                        // answering (or skipping) replaces the composer until it's resolved.
                        if let question = viewModel.detailRequestQuestion {
                            detailRequestSection(question: question)
                        } else {
                            composerSection
                        }
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
        .onChange(of: viewModel.detailRequestQuestion) { _, newValue in
            if newValue != nil {
                isInputFocused = false
                isAnswerFocused = true
            }
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
        // Text input
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("What did you eat?")
                .font(AppFont.display(14))
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

    // MARK: - Detail Request (One-Round Escalation)

    @ViewBuilder
    private func detailRequestSection(question: String) -> some View {
        Text("One quick question")
            .font(AppFont.display(14))
            .foregroundColor(tc.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        // Question card
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            // R5b tinted icon-box
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tc.primary)
                .frame(width: 28, height: 28)
                .background(tc.primary.opacity(0.14))
                .clipShape(AdaptivePillShapeStyle())

            Text(question)
                .font(AppFont.regular(15))
                .foregroundColor(tc.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: tc.primary.opacity(0.3),
            fillColor: tc.primaryBackground
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("One quick question: \(question)")

        // Answer field
        TextEditor(text: $viewModel.detailAnswerInput)
            .font(AppFont.regular(15))
            .foregroundColor(tc.textPrimary)
            .frame(minHeight: 80, maxHeight: 160)
            .scrollContentBackground(.hidden)
            .focused($isAnswerFocused)
            .overlay(alignment: .topLeading) {
                if viewModel.detailAnswerInput.isEmpty {
                    Text("Add a little more detail…")
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
            .accessibilityLabel("Your answer")
            .accessibilityHint("Add more detail so the estimate is accurate")

        loadingIndicator

        AppButton(
            title: "Send Answer",
            style: .primary,
            action: { Task { await viewModel.submitDetailAnswer() } },
            isDisabled: !canSendAnswer,
            icon: "sparkles"
        )
        .accessibilityLabel("Send answer")
        .accessibilityHint(!canSendAnswer ? "Add a little more detail first" : "Tap to re-estimate with your answer")

        // Secondary action: fall back to the round-1 estimates, or — when there are none —
        // go back and rewrite the description.
        if viewModel.canSkipDetailRequest {
            Button {
                viewModel.skipDetailRequest()
            } label: {
                Text("Skip — use estimates")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .underline()
            }
            .accessibilityLabel("Skip the question and use the current estimates")
        } else {
            Button {
                viewModel.editDescriptionFromDetailRequest()
            } label: {
                Text("Edit description")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .underline()
            }
            .accessibilityLabel("Go back and edit the meal description")
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
