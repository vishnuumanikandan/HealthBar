//
//  DuelRecapSheet.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import SwiftUI

/// The end-of-duel recap (D1c) — the single duel modal in the app. Presented from the
/// Battle tab when a duel resolves. Renders from a captured `DuelResolutionSummary`.
struct DuelRecapSheet: View {

    let summary: DuelResolutionSummary

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var displayDelta = 0

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                headline
                Text("vs \(summary.opponentLabel)")
                    .font(AppFont.regular(15))
                    .foregroundColor(tc.textSecondary)
                Text(finalScoreLine)
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
                dayTimeline
                rrCounter
                tierLine
                AppButton(title: "Continue", style: .primary, action: { dismiss() })
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.large])
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 2) {
            Text(headlineText)
                .font(AppFont.bold(28))
                .foregroundColor(isWin ? tc.primary : tc.textPrimary)
            if summary.outcome == .forfeitWin {
                Text("(opponent forfeited)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
        }
    }

    private var headlineText: String {
        switch summary.outcome {
        case .won, .forfeitWin: return "VICTORY"
        case .lost:             return "DEFEAT"
        case .forfeitLoss:      return "FORFEIT"
        case .draw:             return "DRAW"
        }
    }

    private var isWin: Bool { summary.outcome == .won || summary.outcome == .forfeitWin }

    private var finalScoreLine: String {
        "You \(Int(summary.myScore.rounded())) — \(Int(summary.theirScore.rounded())) \(summary.opponentLabel)"
    }

    // MARK: - Day-by-day recap timeline (whole duel)

    private var dayTimeline: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(1...max(1, summary.league), id: \.self) { day in dayRow(day) }
        }
    }

    private func dayRow(_ day: Int) -> some View {
        let idx = day - 1
        let my = idx < summary.myDayScores.count ? summary.myDayScores[idx] : nil
        let their = idx < summary.theirDayScores.count ? summary.theirDayScores[idx] : nil
        let myWins: Bool? = {
            guard let m = my, let t = their else { return nil }
            let mi = Int((m * 10).rounded()), ti = Int((t * 10).rounded())
            return mi == ti ? nil : mi > ti
        }()
        return HStack {
            Text("Day \(day)").font(AppFont.bold(13)).foregroundColor(tc.textSecondary)
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                dayScoreLabel(my, winner: myWins == true)
                Text("vs").font(AppFont.regular(11)).foregroundColor(tc.textTertiary)
                dayScoreLabel(their, winner: myWins == false)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .adaptiveCard(borderColor: tc.primary.opacity(0.15), fillColor: tc.cardBackground)
    }

    private func dayScoreLabel(_ score: Double?, winner: Bool) -> some View {
        HStack(spacing: 3) {
            if winner {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(tc.primary)
            }
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(AppFont.bold(14))
                .foregroundColor(tc.textPrimary)
        }
    }

    // MARK: - Animated RR + tier

    private var rrCounter: some View {
        Text("\(displayDelta >= 0 ? "+" : "")\(displayDelta) RR")
            .font(AppFont.bold(34))
            .foregroundColor(summary.rrDelta >= 0 ? tc.primary : tc.textPrimary)
            .contentTransition(.numericText())
            .onAppear {
                let target = summary.rrDelta
                let steps = 20
                Task {
                    for i in 1...steps {
                        try? await Task.sleep(for: .milliseconds(50))
                        withAnimation(.easeOut(duration: 0.05)) { displayDelta = target * i / steps }
                    }
                    withAnimation { displayDelta = target }
                }
            }
    }

    @ViewBuilder
    private var tierLine: some View {
        let preTier = Rank.rankTier(from: summary.preRR)
        let postTier = Rank.rankTier(from: summary.postRR)
        if preTier.displayName != postTier.displayName {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(preTier.displayName).font(AppFont.regular(14)).foregroundColor(tc.textSecondary)
                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(tc.primary)
                Text(postTier.displayName).font(AppFont.bold(14)).foregroundColor(tc.textPrimary)
            }
        } else {
            Text("\(postTier.displayName) · \(summary.postRR) RR")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)
        }
    }
}
