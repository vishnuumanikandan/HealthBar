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

    /// "Save for later" (Phase 10): the mode drives the sheet; the snapshot is
    /// frozen at tap time so later edits don't affect an open save sheet.
    @State private var quickLogMode: SaveQuickLogSheet.Mode? = nil
    @State private var saveSnapshot: [RecognizedFoodItem] = []

    private var tc: ThemeColors { settings.activeColors }

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
                AdaptivePillShapeStyle()
                    .fill(tc.primary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.sm)

                // Header
                HStack {
                    Text("Review & Confirm")
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    MealTypePill(mealType: viewModel.pendingMealType)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.md)

                // Summary bar
                HStack {
                    Text("\(includedCount) item\(includedCount == 1 ? "" : "s")")
                        .font(AppFont.bold(14))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text("\(totalCalories) cal total")
                        .font(AppFont.bold(14))
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
                    AppButton(
                        title: "Log \(includedCount) item\(includedCount == 1 ? "" : "s")",
                        style: .primary,
                        action: logItems,
                        isLoading: viewModel.isSubmittingForm,
                        isDisabled: includedCount == 0 || viewModel.isSubmittingForm,
                        icon: "checkmark.circle.fill"
                    )
                    .accessibilityLabel("Log \(includedCount) food item\(includedCount == 1 ? "" : "s")")
                    .accessibilityHint(includedCount == 0 ? "No items selected" : "Tap to log selected items")

                    // Save for later (Phase 10) — capture this AI result as a
                    // reusable meal/recipe. Independent of logging; hidden when
                    // there are no included items.
                    if includedCount > 0 {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            saveForLaterButton(title: "Save as Meal", icon: "rectangle.stack.fill") {
                                presentSaveSheet(.meal)
                            }
                            saveForLaterButton(title: "Save as Recipe", icon: "list.bullet.rectangle.fill") {
                                presentSaveSheet(.recipe)
                            }
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
                        .font(AppFont.regular(15))
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
        .sheet(item: $quickLogMode) { mode in
            SaveQuickLogSheet(
                coordinator: viewModel.coordinator,
                mode: mode,
                prefillName: viewModel.mealDescriptionInput,
                items: saveSnapshot
            )
        }
    }

    // MARK: - Save for Later (Phase 10)

    private func saveForLaterButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(AppFont.regular(13))
                Text(title)
                    .font(AppFont.bold(13))
            }
            .foregroundColor(tc.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Freezes the current included-items snapshot, then opens the save sheet.
    private func presentSaveSheet(_ mode: SaveQuickLogSheet.Mode) {
        saveSnapshot = includedItems.compactMap { $0.toRecognizedFoodItem() }
        quickLogMode = mode
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
                        .font(AppFont.bold(15))
                        .foregroundColor(draft.isIncluded ? tc.textPrimary : tc.textTertiary)
                        .accessibilityLabel("Food name")

                    if !draft.quantityText.isEmpty {
                        Text(draft.quantityText)
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Quantity: \(draft.quantityText)")
                    }
                }

                Spacer()

                confidenceLabel(for: draft)
            }

            if draft.isIncluded {
                // Clarification chips (above macro fields, ordered by importance)
                if !draft.clarifications.isEmpty {
                    clarificationSection(item: item)
                }

                // Macro edit grid
                HStack(spacing: DesignSystem.Spacing.sm) {
                    macroField(label: "Cal", value: item.caloriesText, suffix: "", color: tc.primary, item: item)
                        .accessibilityLabel("Calories")
                    macroField(label: "P", value: item.proteinText, suffix: "g", color: tc.macroBarProtein, item: item)
                        .accessibilityLabel("Protein grams")
                    macroField(label: "C", value: item.carbsText, suffix: "g", color: tc.macroBarCarbs, item: item)
                        .accessibilityLabel("Carbs grams")
                    macroField(label: "F", value: item.fatText, suffix: "g", color: tc.macroBarFat, item: item)
                        .accessibilityLabel("Fat grams")
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: draft.isIncluded ? tc.primary.opacity(0.3) : tc.textTertiary.opacity(0.2),
            fillColor: draft.isIncluded ? tc.primaryBackground : tc.cardBackground
        )
        .opacity(draft.isIncluded ? 1.0 : 0.6)
    }

    // MARK: - Clarification Section

    @ViewBuilder
    private func clarificationSection(item: Binding<DraftItem>) -> some View {
        let draft = item.wrappedValue
        let isClean = SettingsManager.shared.isCleanUI

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(draft.clarifications.indices, id: \.self) { cIndex in
                let clarification = draft.clarifications[cIndex]

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(clarification.question)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                        .accessibilityLabel(clarification.question)

                    // Option chips row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            ForEach(clarification.options) { option in
                                let isSelected = clarification.selectedOptionID == option.id
                                let isDisabled = draft.manualEditLocked

                                Button {
                                    guard !isDisabled else { return }
                                    item.wrappedValue.clarifications[cIndex].selectedOptionID = option.id
                                    recomputeDraftMacros(item: item)
                                } label: {
                                    Text(option.label)
                                        .font(AppFont.bold(11))
                                        .foregroundColor(chipTextColor(selected: isSelected, disabled: isDisabled, isClean: isClean))
                                        .padding(.horizontal, DesignSystem.Spacing.sm)
                                        .padding(.vertical, DesignSystem.Spacing.xs + 2)
                                        .background(chipBackground(selected: isSelected, disabled: isDisabled, isClean: isClean))
                                        .clipShape(AdaptivePillShapeStyle())
                                        .overlay(
                                            AdaptivePillShapeStyle()
                                                .stroke(
                                                    chipBorderColor(selected: isSelected, disabled: isDisabled, isClean: isClean),
                                                    lineWidth: isClean ? 1.5 : 1
                                                )
                                        )
                                }
                                .disabled(isDisabled)
                                .accessibilityLabel("\(clarification.question), \(option.label), \(isSelected ? "selected" : "not selected")")
                                .accessibilityHint(isDisabled ? "Manual edits in effect" : (isSelected ? "Currently selected" : "Tap to select"))
                            }
                        }
                    }
                }
            }

            // Manual-edit lock note
            if draft.manualEditLocked {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Manual edits in effect")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)

                    Button {
                        resetToChipDriven(item: item)
                    } label: {
                        Text("Reset")
                            .font(AppFont.bold(11))
                            .foregroundColor(tc.primary)
                    }
                    .accessibilityLabel("Reset to use clarification questions again")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Chip Styling Helpers

    private func chipTextColor(selected: Bool, disabled: Bool, isClean: Bool) -> Color {
        if disabled { return tc.textTertiary }
        if selected { return .white }
        return isClean ? tc.textSecondary : tc.textPrimary
    }

    private func chipBackground(selected: Bool, disabled: Bool, isClean: Bool) -> Color {
        if disabled {
            return isClean ? tc.primaryBackground.opacity(0.5) : tc.cardBackground.opacity(0.5)
        }
        if selected { return tc.primary }
        return isClean ? tc.primaryBackground : tc.cardBackground
    }

    private func chipBorderColor(selected: Bool, disabled: Bool, isClean: Bool) -> Color {
        if disabled {
            return isClean ? tc.textTertiary.opacity(0.2) : tc.textTertiary.opacity(0.3)
        }
        if selected { return tc.primary }
        return isClean ? tc.primary.opacity(0.25) : tc.textTertiary.opacity(0.3)
    }

    // MARK: - Macro Field

    private func macroField(
        label: String,
        value: Binding<String>,
        suffix: String,
        color: Color,
        item: Binding<DraftItem>
    ) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppFont.bold(10))
                .foregroundColor(color)

            HStack(spacing: 1) {
                TextField("0", text: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = newValue
                        if !item.wrappedValue.clarifications.isEmpty && !item.wrappedValue.manualEditLocked {
                            item.wrappedValue.manualEditLocked = true
                        }
                    }
                ))
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 30)

                if !suffix.isEmpty {
                    Text(suffix)
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .adaptiveCard(borderColor: color.opacity(0.2), fillColor: tc.cardBackground)
    }

    // MARK: - Confidence Label

    @ViewBuilder
    private func confidenceLabel(for draft: DraftItem) -> some View {
        let isClean = SettingsManager.shared.isCleanUI

        if let reason = draft.confidenceReason {
            if draft.allClarificationsAnswered {
                Text("Clarified")
                    .font(AppFont.bold(9))
                    .foregroundColor(isClean ? tc.primary : tc.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .adaptivePill(
                        borderColor: isClean ? tc.primary.opacity(0.2) : tc.textTertiary.opacity(0.3),
                        fillColor: isClean ? tc.primary.opacity(0.08) : tc.cardBackground
                    )
                    .accessibilityLabel("Clarified")
            } else {
                Text("⚠ " + reason)
                    .font(AppFont.bold(9))
                    .foregroundColor(DesignSystem.Colors.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .adaptivePill(
                        borderColor: DesignSystem.Colors.warning.opacity(isClean ? 0.25 : 0.3),
                        fillColor: DesignSystem.Colors.warning.opacity(isClean ? 0.08 : 0.1)
                    )
                    .accessibilityLabel(reason)
                    .lineLimit(1)
            }
        } else {
            confidenceBadge(draft.confidence)
        }
    }

    // MARK: - Confidence Badge (high-confidence items, no clarifications)

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
            .font(AppFont.bold(9))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .adaptivePill(borderColor: color.opacity(0.3), fillColor: color.opacity(0.1))
            .accessibilityLabel(hint)
    }

    // MARK: - Recompute & Reset

    private func recomputeDraftMacros(item: Binding<DraftItem>) {
        let draft = item.wrappedValue
        let baseline = (cal: draft.baselineCalories, p: draft.baselineProtein, c: draft.baselineCarbs, f: draft.baselineFat)
        let result = recomputedMacros(forBaseline: baseline, clarifications: draft.clarifications)

        item.wrappedValue.caloriesText = "\(result.cal)"
        item.wrappedValue.proteinText = DraftItem.formatMacro(result.p)
        item.wrappedValue.carbsText = DraftItem.formatMacro(result.c)
        item.wrappedValue.fatText = DraftItem.formatMacro(result.f)

        print("[AIFoodRecognition] Recomputed item \(draft.id): \(result.cal) cal")
    }

    private func resetToChipDriven(item: Binding<DraftItem>) {
        item.wrappedValue.manualEditLocked = false
        recomputeDraftMacros(item: item)
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

    let baselineCalories: Int
    let baselineProtein: Double
    let baselineCarbs: Double
    let baselineFat: Double

    /// Advanced nutrition carried through the review round-trip unedited (not shown/editable here).
    let toxinScore: Int
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
    let saturatedFat: Double?
    let cholesterol: Double?
    let potassium: Double?

    var confidenceReason: String?
    var clarifications: [FoodClarification]
    var manualEditLocked: Bool = false

    var allClarificationsAnswered: Bool {
        guard !clarifications.isEmpty else { return false }
        return clarifications.allSatisfy { c in
            let defaultOption = c.options.first(where: {
                $0.deltaCalories == 0 && $0.deltaProtein == 0 && $0.deltaCarbs == 0 && $0.deltaFat == 0
            })
            return defaultOption == nil || c.selectedOptionID != defaultOption!.id
        }
    }

    init(from item: RecognizedFoodItem) {
        self.id = item.id
        self.name = item.name
        self.quantityText = item.quantityText
        self.caloriesText = "\(item.calories)"
        self.proteinText = Self.formatMacro(item.protein)
        self.carbsText = Self.formatMacro(item.carbs)
        self.fatText = Self.formatMacro(item.fat)
        self.confidence = item.confidence
        self.baselineCalories = item.baselineCalories
        self.baselineProtein = item.baselineProtein
        self.baselineCarbs = item.baselineCarbs
        self.baselineFat = item.baselineFat
        self.toxinScore = item.toxinScore
        self.fiber = item.fiber
        self.sugar = item.sugar
        self.sodium = item.sodium
        self.saturatedFat = item.saturatedFat
        self.cholesterol = item.cholesterol
        self.potassium = item.potassium
        self.confidenceReason = item.confidenceReason
        self.clarifications = item.clarifications
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
            confidence: confidence,
            toxinScore: toxinScore,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            saturatedFat: saturatedFat,
            cholesterol: cholesterol,
            potassium: potassium
        )
    }

    /// Format a macro value for display: 1 decimal place, drop trailing ".0".
    static func formatMacro(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
