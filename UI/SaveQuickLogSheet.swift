//
//  SaveQuickLogSheet.swift
//  HealthBar
//
//  Created by Claude on 6/12/26.
//

import SwiftUI

/// Saves an AI-recognized item snapshot as a reusable SavedMeal or SavedRecipe
/// (Friend System Phase 10), with an optional "Save & Share" that chains into
/// Prompt 9's FriendPickerSheet for the just-created model.
///
/// Operates on the snapshot passed in at presentation — it does NOT live-bind to
/// the review screen's draft items. Saving goes through the existing add
/// pipeline (no parallel save path); a share failure never undoes the save.
struct SaveQuickLogSheet: View {

    enum Mode: String, Identifiable {
        case meal
        case recipe
        var id: String { rawValue }
    }

    private let coordinator: AppCoordinator
    private let mode: Mode

    /// Frozen snapshot of the recognized items at presentation time.
    private let items: [RecognizedFoodItem]

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var name: String
    @State private var yield: Int = 1
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var savedToast = false

    init(coordinator: AppCoordinator, mode: Mode, prefillName: String, items: [RecognizedFoodItem]) {
        self.coordinator = coordinator
        self.mode = mode
        self.items = items
        self._name = State(initialValue: prefillName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isRecipe: Bool { mode == .recipe }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What will actually be saved (blank-name / negative items already excluded).
    private var convertedComponents: [SavedMealComponent] {
        DataManager.components(from: items)
    }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving && !convertedComponents.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        AuthTextField(
                            label: isRecipe ? "Recipe name" : "Meal name",
                            placeholder: isRecipe ? "Name this recipe" : "Name this meal",
                            text: $name
                        )

                        if isRecipe {
                            yieldStepper
                        }

                        summaryCard

                        if convertedComponents.isEmpty {
                            inlineError("Nothing to save.")
                        } else if let errorMessage {
                            inlineError(errorMessage)
                        }

                        actionButtons
                    }
                    .padding(DesignSystem.Spacing.lg)
                }

                if savedToast {
                    savedToastView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isRecipe ? "Save as Recipe" : "Save as Meal")
                        .font(AppFont.bold(18))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.primary)
                }
            }
        }
    }

    // MARK: - Pieces

    private var yieldStepper: some View {
        HStack {
            Text("Yield")
                .font(AppFont.bold(14))
                .foregroundColor(tc.textPrimary)
            Spacer()
            Stepper(value: $yield, in: 1...50) {
                Text("\(yield) serving\(yield == 1 ? "" : "s")")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
                    .monospacedDigit()
            }
            .fixedSize()
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var summaryCard: some View {
        let count = convertedComponents.count
        let cal = convertedComponents.reduce(0) { $0 + $1.calories }
        return HStack {
            Text("\(count) item\(count == 1 ? "" : "s")")
                .font(AppFont.bold(14))
                .foregroundColor(tc.textPrimary)
            Spacer()
            Text("\(cal) cal")
                .font(AppFont.bold(13))
                .foregroundColor(tc.textSecondary)
                .monospacedDigit()
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var actionButtons: some View {
        AppButton(
            title: "Save",
            style: .primary,
            action: { Task { await save() } }
        )
        .disabled(!canSave)
        .padding(.top, DesignSystem.Spacing.sm)
    }

    private var savedToastView: some View {
        VStack {
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(tc.primary)
                Text(isRecipe ? "Saved to your recipes" : "Saved to your meals")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.5), fillColor: tc.cardBackground)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.danger)
            Text(message)
                .font(AppFont.regular(12))
                .foregroundColor(DesignSystem.Colors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            if isRecipe {
                _ = try await coordinator.saveQuickLog(asRecipeNamed: trimmedName, yield: yield, items: items)
            } else {
                _ = try await coordinator.saveQuickLog(asMealNamed: trimmedName, items: items)
            }
            await finishSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save. Try again."
            isSaving = false
        }
    }

    private func finishSaved() async {
        withAnimation { savedToast = true }
        try? await Task.sleep(for: .seconds(0.9))
        dismiss()
    }
}
