//
//  RecognizedFoodsReviewView.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import SwiftUI

/// Review sheet showing AI-recognized food items before logging.
///
/// Input-agnostic — works identically regardless of whether items came from
/// text description, photo recognition, barcode, or any future source.
/// All edits are made on a local draft array; the ViewModel's `recognizedItems`
/// is only read once on appear and never mutated during editing.
struct RecognizedFoodsReviewView: View {

    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    @State private var draftItems: [DraftItem] = []

    private var tc: ThemeColors { settings.activeTheme.colors }

    private var includedItems: [DraftItem] {
        draftItems.filter(\.isIncluded)
    }

    private var includedCount: Int { includedItems.count }

    private var totalCalories: Int {
        includedItems.reduce(into: 0) { $0 += Int($1.caloriesText) ?? 0 }
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
                    Text("Review & Confirm")
                        .font(PixelFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)

                // Summary bar
                HStack {
                    Text("\(includedCount) item\(includedCount == 1 ? "" : "s")")
                        .font(PixelFont.bold(14))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text("\(totalCalories) cal total")
                        .font(PixelFont.bold(14))
                        .foregroundColor(tc.primary)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.sm)

                // Item list
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach($draftItems) { $item in
                            reviewRow(item: $item)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }

                // Bottom bar
                VStack(spacing: DesignSystem.Spacing.sm) {
                    // Log button
                    Button {
                        logItems()
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(PixelFont.bold(16))
                            Text("Log \(includedCount) item\(includedCount == 1 ? "" : "s")")
                                .font(PixelFont.bold(16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.band3Green)
                        .clipShape(PixelPillShape())
                        .opacity(includedCount == 0 || viewModel.isSubmittingForm ? 0.5 : 1.0)
                    }
                    .disabled(includedCount == 0 || viewModel.isSubmittingForm)
                    .accessibilityLabel("Log \(includedCount) food item\(includedCount == 1 ? "" : "s")")
                    .accessibilityHint(includedCount == 0 ? "No items selected" : "Tap to log selected items")

                    if viewModel.isSubmittingForm {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            ProgressView()
                                .tint(tc.primary)
                            Text("Logging…")
                                .font(PixelFont.regular(13))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
                .background(tc.cardBackground)
            }
            .background(tc.cardBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(PixelFont.regular(15))
                        .foregroundColor(tc.textSecondary)
                        .accessibilityLabel("Cancel review, discard edits")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.CornerRadius.xl)
        .onAppear {
            draftItems = viewModel.recognizedItems.map { DraftItem(from: $0) }
        }
    }

    // MARK: - Item Row

    @ViewBuilder
    private func reviewRow(item: Binding<DraftItem>) -> some View {
        let draft = item.wrappedValue

        VStack(spacing: DesignSystem.Spacing.sm) {
            // Top row: toggle + name + confidence
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Toggle(isOn: item.isIncluded) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(tc.primary)
                .accessibilityLabel("\(draft.name) include toggle")
                .accessibilityHint(draft.isIncluded ? "Currently included, tap to exclude" : "Currently excluded, tap to include")

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: item.name)
                        .font(PixelFont.bold(15))
                        .foregroundColor(draft.isIncluded ? tc.textPrimary : tc.textTertiary)
                        .accessibilityLabel("Food name")

                    TextField("Quantity", text: item.quantityText)
                        .font(PixelFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                        .accessibilityLabel("Quantity description")
                }

                Spacer()

                confidenceBadge(draft.confidence)
            }

            if draft.isIncluded {
                // Macro edit grid
                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroField(label: "Cal", value: item.caloriesText, suffix: "", color: tc.primary)
                        .accessibilityLabel("Calories")
                    macroField(label: "P", value: item.proteinText, suffix: "g", color: tc.macroBarProtein)
                        .accessibilityLabel("Protein grams")
                    macroField(label: "C", value: item.carbsText, suffix: "g", color: tc.macroBarCarbs)
                        .accessibilityLabel("Carbs grams")
                    macroField(label: "F", value: item.fatText, suffix: "g", color: tc.macroBarFat)
                        .accessibilityLabel("Fat grams")
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .pixelCard(
            borderColor: draft.isIncluded ? tc.primary.opacity(0.3) : tc.textTertiary.opacity(0.2),
            fillColor: draft.isIncluded ? tc.primaryBackground : tc.cardBackground
        )
        .opacity(draft.isIncluded ? 1.0 : 0.6)
    }

    // MARK: - Macro Field

    private func macroField(
        label: String,
        value: Binding<String>,
        suffix: String,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(PixelFont.bold(10))
                .foregroundColor(color)

            HStack(spacing: 1) {
                TextField("0", text: value)
                    .font(PixelFont.regular(14))
                    .foregroundColor(tc.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 30)

                if !suffix.isEmpty {
                    Text(suffix)
                        .font(PixelFont.regular(10))
                        .foregroundColor(tc.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .pixelCard(borderColor: color.opacity(0.2), fillColor: tc.cardBackground)
    }

    // MARK: - Confidence Badge

    private func confidenceBadge(_ confidence: RecognizedFoodItem.Confidence) -> some View {
        let (text, color, hint): (String, Color, String) = {
            switch confidence {
            case .low:
                return ("Low", DesignSystem.Colors.warning, "Low confidence, review recommended")
            case .medium:
                return ("Med", tc.textTertiary, "Medium confidence")
            case .high:
                return ("High", tc.primary, "High confidence")
            }
        }()

        return Text(text)
            .font(PixelFont.bold(9))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .pixelPill(borderColor: color.opacity(0.3), fillColor: color.opacity(0.1))
            .accessibilityLabel(hint)
    }

    // MARK: - Actions

    private func logItems() {
        let validItems = includedItems.compactMap { $0.toRecognizedFoodItem() }
        guard !validItems.isEmpty else { return }

        Task {
            await viewModel.logRecognizedItems(validItems)
        }
    }
}

// MARK: - Draft Item

/// Local draft wrapper for editing recognized items without mutating the ViewModel's source array.
/// Stores macro values as strings for live editing without mid-typing rounding.
private struct DraftItem: Identifiable {
    let id: UUID
    var name: String
    var quantityText: String
    var caloriesText: String
    var proteinText: String
    var carbsText: String
    var fatText: String
    var confidence: RecognizedFoodItem.Confidence
    var isIncluded: Bool = true

    init(from item: RecognizedFoodItem) {
        self.id = item.id
        self.name = item.name
        self.quantityText = item.quantityText
        self.caloriesText = "\(item.calories)"
        self.proteinText = Self.formatMacro(item.protein)
        self.carbsText = Self.formatMacro(item.carbs)
        self.fatText = Self.formatMacro(item.fat)
        self.confidence = item.confidence
    }

    /// Converts draft back to a RecognizedFoodItem with validated/clamped values.
    /// Returns nil if name is empty.
    func toRecognizedFoodItem() -> RecognizedFoodItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let cal = min(max(Int(caloriesText) ?? 0, 0), 5000)
        let p = min(max(Double(proteinText) ?? 0, 0), 1000)
        let c = min(max(Double(carbsText) ?? 0, 0), 1000)
        let f = min(max(Double(fatText) ?? 0, 0), 1000)

        return RecognizedFoodItem(
            id: id,
            name: trimmedName,
            quantityText: quantityText,
            calories: cal,
            protein: p,
            carbs: c,
            fat: f,
            confidence: confidence
        )
    }

    /// Format a macro value for display: 1 decimal place, drop trailing ".0".
    private static func formatMacro(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
