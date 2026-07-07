//
//  MacroGuessQTESheet.swift
//  HealthBar
//
//  Created by Claude on 7/5/26.
//

import SwiftUI

/// Macro-guess micro-game (D1d): pick the closer protein estimate for a random built-in food.
/// One attempt/day regardless of outcome. `Bool.random()` for option order is fine — the
/// deterministic-RNG rule applies only to duel resolution deltas, not UI.
struct MacroGuessQTESheet: View {

    let coordinator: AppCoordinator
    let dateKey: String
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var food: BuiltInFood?
    @State private var options: [Int] = []       // [left, right]
    @State private var correctValue = 0
    @State private var resultText: String?
    @State private var revealed = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Macro Guess").font(AppFont.bold(22)).foregroundColor(tc.textPrimary)
            if let food {
                Text("How much protein in \(food.name)?")
                    .font(AppFont.regular(16)).foregroundColor(tc.textPrimary).multilineTextAlignment(.center)
                Text("(\(food.servingDescription))").font(AppFont.regular(12)).foregroundColor(tc.textSecondary)

                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(options, id: \.self) { optionButton($0) }
                }
                .padding(.top, DesignSystem.Spacing.sm)

                if let resultText {
                    Text(resultText).font(AppFont.bold(20)).foregroundColor(tc.primary)
                }
            } else {
                ProgressView().tint(tc.primary)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear(perform: setup)
    }

    private func optionButton(_ value: Int) -> some View {
        Button { answer(value) } label: {
            Text("\(value)g")
                .font(AppFont.bold(20))
                .foregroundColor(revealed && value == correctValue ? .white : tc.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(revealed && value == correctValue ? tc.primary : tc.cardBackground)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: .clear)
        }
        .buttonStyle(.plain)
        .disabled(revealed)
    }

    private func setup() {
        guard let picked = BuiltInFoods.all.filter({ $0.protein > 0 }).randomElement() else {
            dismiss(); return
        }
        food = picked
        let truth = Int(picked.protein.rounded())
        correctValue = truth
        var decoy = Int((Double(truth) * DuelConstants.macroGuessDecoyFactor).rounded())
        if Double(abs(decoy - truth)) < DuelConstants.macroGuessMinGapGrams {
            decoy = truth + Int(DuelConstants.macroGuessMinGapGrams.rounded())
        }
        options = Bool.random() ? [truth, decoy] : [decoy, truth]
    }

    private func answer(_ value: Int) {
        guard !revealed else { return }
        revealed = true
        let correct = value == correctValue
        Task {
            _ = await coordinator.awardMacroGuessQTE(points: correct ? DuelConstants.macroGuessPoints : 0, dateKey: dateKey)
            resultText = correct ? "CORRECT +\(DuelConstants.macroGuessPoints)" : "It was \(correctValue)g"
            try? await Task.sleep(for: .seconds(1.6))
            onFinished()
            dismiss()
        }
    }
}
