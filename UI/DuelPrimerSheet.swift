//
//  DuelPrimerSheet.swift
//  HealthBar
//
//  Created by Claude on 7/24/26.
//

import SwiftUI

/// DUEL-CLARITY-1: "How duels work" — the scoring table, the comeback rule, the concurrent-duel
/// caps, and the per-league RR stakes.
///
/// PURE STATIC CONTENT. It reads `DuelConstants` and nothing else: no view model, no
/// DataManager, no coordinator, no user or duel state, no async work. Presented from two
/// entry points (the Battle ongoing-list foot button and the Arena info affordance), and it
/// renders identically from both.
///
/// Every figure on this sheet is bound to a NAMED tuning constant — there are no numeric
/// literals for point values, multipliers, caps, or RR deltas. If a balancing pass edits
/// `DuelConstants`, this sheet follows with no code change.
struct DuelPrimerSheet: View {

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        VStack(spacing: 0) {
            // Custom drag handle (sheet convention — the system indicator is hidden below).
            AdaptivePillShapeStyle()
                .fill(tc.primary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)

            Text("HOW DUELS WORK")
                .font(AppFont.display(20))
                .foregroundColor(tc.textPrimary)
                .padding(.bottom, DesignSystem.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    intro
                    scoringTable
                    comebackSection
                    multipleDuelsSection
                    stakesSection
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.CornerRadius.xl)
    }

    // MARK: - Intro

    private var intro: some View {
        Text("Every day you log is scored out of \(number(DuelConstants.maxDayScore)) duel points. Those points count in every duel you're in — the highest total when the clock runs out wins.")
            .font(AppFont.regular(13))
            .foregroundColor(tc.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Scoring table

    /// The five components, in the order the Arena breakdown card renders them.
    private var scoringTable: some View {
        VStack(spacing: 0) {
            sectionLabel("DAILY SCORING")
                .padding(.bottom, DesignSystem.Spacing.md)

            VStack(spacing: DesignSystem.Spacing.md) {
                scoringRow("Calories",
                           "Closer to your calorie goal scores more — going over costs more than going under.",
                           DuelConstants.caloriePoints)
                scoringRow("Protein",
                           "Scaled to your protein target: hit it in full for all \(number(DuelConstants.proteinPoints)).",
                           DuelConstants.proteinPoints)
                scoringRow("Purity",
                           "Full points while your daily toxin score sits at or under your purity target.",
                           DuelConstants.purityPoints)
                scoringRow("Quests",
                           "Your share of today's completed quests.",
                           DuelConstants.questPoints)
                scoringRow("QTE bonus",
                           "Spark \(DuelConstants.sparkPointsCap) · Clean Log \(DuelConstants.cleanLogPointsCap) · Macro Guess \(DuelConstants.macroGuessPointsCap).",
                           DuelConstants.qteBonusCap)
            }

            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
                .padding(.vertical, DesignSystem.Spacing.md)

            HStack(alignment: .firstTextBaseline) {
                Text("MAX PER DAY")
                    .font(AppFont.display(11))
                    .tracking(1.1)
                    .foregroundColor(tc.textSecondary)
                Spacer()
                Text(number(DuelConstants.maxDayScore))
                    .font(AppFont.display(22))
                    .foregroundColor(tc.primary)
            }
        }
    }

    private func scoringRow(_ title: String, _ detail: String, _ points: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                Text(detail)
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignSystem.Spacing.sm)
            Text(number(points))
                .font(AppFont.display(20))
                .foregroundColor(tc.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Comeback

    private var comebackSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("COMEBACK")
            Text("Behind in a duel? Your QTE points count for ×\(number(DuelConstants.comebackMultiplier)) in that duel — still capped at the \(number(DuelConstants.qteBonusCap))-point QTE ceiling. Being behind is worth playing from.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Multiple duels

    private var multipleDuelsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("MULTIPLE DUELS")
            Text("One day's points count in every duel you're running, so duels stack instead of splitting your effort. Each league has its own limit:")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(DuelConstants.leagues, id: \.self) { league in
                    HStack {
                        leagueTag(league)
                        Spacer()
                        Text(concurrentLabel(league))
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// "up to 2 at once" / "1 at a time" — the cap straight off the constants.
    private func concurrentLabel(_ league: Int) -> String {
        let cap = DuelConstants.maxConcurrentDuels(league: league)
        return cap == 1 ? "\(cap) at a time" : "up to \(cap) at once"
    }

    // MARK: - Stakes

    /// Per-league RR movement. Win and loss are ROLLED RANGES at resolution, so the range is
    /// what's shown; a draw is a fixed figure, so the figure is what's shown.
    private var stakesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionLabel("STAKES")
            Text("Every resolved duel moves your RR. Win and loss are rolled from a range when the duel resolves; a draw is fixed. Longer leagues stake more.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DesignSystem.Spacing.md) {
                ForEach(DuelConstants.leagues, id: \.self) { league in
                    VStack(alignment: .leading, spacing: 6) {
                        leagueTag(league)
                        HStack(spacing: DesignSystem.Spacing.md) {
                            stake("WIN", signedRange(DuelConstants.winDelta(league: league)))
                            stake("LOSS", signedRange(DuelConstants.lossDelta(league: league)))
                            stake("DRAW", signed(DuelConstants.drawDelta(league: league)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
    }

    private func stake(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.display(10))
                .tracking(0.9)
                .foregroundColor(tc.textTertiary)
            Text(value)
                .font(AppFont.display(15))
                .foregroundColor(tc.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    /// Hairline-flanked tracked-uppercase micro-section label (the ArenaView D5 language).
    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Rectangle().fill(DesignSystem.Erewhon.line).frame(height: 1)
            Text(text)
                .font(AppFont.display(11))
                .tracking(1.1)
                .foregroundColor(tc.primary)
                .layoutPriority(1)
            Rectangle().fill(DesignSystem.Erewhon.line).frame(height: 1)
        }
    }

    /// The keyline league tag ("1-DAY"), matching the ongoing-list section headers.
    private func leagueTag(_ league: Int) -> some View {
        Text("\(league)-DAY")
            .font(AppFont.display(10))
            .tracking(0.9)
            .foregroundColor(tc.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(tc.primary.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - Number rendering (no tuning literals — every value is a named constant)

    /// A tuning constant with no trailing ".0" (30.0 → "30", 1.25 → "1.25").
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// A signed RR figure ("+10", "−25"), using a real minus sign.
    private func signed(_ value: Int) -> String {
        value < 0 ? "−\(abs(value))" : "+\(value)"
    }

    /// A signed RR range ("+25–30", "−25 to −20"). Losses read as two signed endpoints so a
    /// negative range can never be misread as a subtraction.
    private func signedRange(_ range: ClosedRange<Int>) -> String {
        range.lowerBound < 0
            ? "\(signed(range.lowerBound)) to \(signed(range.upperBound))"
            : "\(signed(range.lowerBound))–\(range.upperBound)"
    }
}
