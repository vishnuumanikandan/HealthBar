//
//  DescribeMealView.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import SwiftUI

/// Text input sheet where the user types a natural-language meal description.
///
/// Presented from AddFoodChoiceSheet → "Describe Your Meal".
/// On success the ViewModel closes this sheet and opens RecognizedFoodsReviewView.
struct DescribeMealView: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    @FocusState private var isInputFocused: Bool

    private var tc: ThemeColors { settings.activeTheme.colors }

    private var inputIsEmpty: Bool {
        viewModel.mealDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drag handle
                PixelPillShape()
                    .fill(tc.primary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                // Header
                HStack {
                    Text("Describe Your Meal")
                        .font(PixelFont.bold(20))
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
                                    .font(PixelFont.bold(14))
                                    .foregroundColor(DesignSystem.Colors.warning)
                                Text(error)
                                    .font(PixelFont.regular(13))
                                    .foregroundColor(DesignSystem.Colors.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DesignSystem.Spacing.md)
                            .pixelCard(
                                borderColor: DesignSystem.Colors.warning.opacity(0.4),
                                fillColor: DesignSystem.Colors.warning.opacity(0.08)
                            )
                            .accessibilityLabel("Error: \(error)")
                        }

                        // Text input
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("What did you eat?")
                                .font(PixelFont.bold(14))
                                .foregroundColor(tc.textSecondary)

                            TextEditor(text: $viewModel.mealDescriptionInput)
                                .font(PixelFont.regular(15))
                                .foregroundColor(tc.textPrimary)
                                .frame(minHeight: 100, maxHeight: 160)
                                .scrollContentBackground(.hidden)
                                .focused($isInputFocused)
                                .overlay(alignment: .topLeading) {
                                    if viewModel.mealDescriptionInput.isEmpty {
                                        Text("e.g. grilled chicken breast, half cup rice, side salad")
                                            .font(PixelFont.regular(14))
                                            .foregroundColor(tc.textTertiary)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(DesignSystem.Spacing.sm)
                                .pixelCard(
                                    borderColor: tc.primary.opacity(0.3),
                                    fillColor: tc.primaryBackground
                                )
                        }

                        // Loading indicator
                        if viewModel.isRecognizing {
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                ProgressView()
                                    .tint(tc.primary)
                                Text("Estimating nutrition…")
                                    .font(PixelFont.regular(14))
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
                                    .font(PixelFont.bold(16))
                                Text("Analyze")
                                    .font(PixelFont.bold(16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(
                                DesignSystem.Colors.band3Green
                            )
                            .clipShape(PixelPillShape())
                            .opacity(inputIsEmpty || viewModel.isRecognizing ? 0.5 : 1.0)
                        }
                        .disabled(inputIsEmpty || viewModel.isRecognizing)
                        .accessibilityLabel("Analyze meal description")
                        .accessibilityHint(inputIsEmpty ? "Enter a meal description first" : "Tap to estimate nutrition")

                        // Manual entry fallback
                        Button {
                            dismiss()
                            viewModel.openAddFoodFormAfterDelay()
                        } label: {
                            Text("Enter manually instead")
                                .font(PixelFont.regular(13))
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
                        .font(PixelFont.regular(15))
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
    }
}
