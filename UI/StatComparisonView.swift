//
//  StatComparisonView.swift
//  HealthBar
//
//  Created by Claude on 6/11/26.
//

import SwiftUI

/// "You vs. them" stat comparison (Friend System Phase 6).
///
/// A reusable, self-contained subview rendered INLINE inside the friend profile
/// sheet — never its own sheet. It takes two already-loaded projections (the
/// friend's, reused from the profile; mine, built locally with no self-read)
/// and lays out a fixed-order metric table with a per-metric leader highlight
/// and a "You lead N of M" tally.
///
/// All inputs are decoration except the numeric scores: identity keys on uid
/// upstream, never on these display strings. Owns no padding — the presenter
/// places it within the profile's existing spacing.
struct StatComparisonView: View {

    // MARK: - Inputs

    /// The current user's locally built projection.
    let mine: PublicStatsDTO

    /// The friend's already-loaded published projection.
    let theirs: PublicStatsDTO

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Leader

    private enum Leader { case mine, theirs, tie }

    /// One comparison row: display strings plus the numeric scores that decide
    /// the leader. Higher score wins; equal scores are a neutral tie.
    private struct Metric: Identifiable {
        let id = UUID()
        let label: String
        let mineDisplay: String
        let theirsDisplay: String
        let mineScore: Double
        let theirsScore: Double

        var leader: Leader {
            if mineScore > theirsScore { return .mine }
            if theirsScore > mineScore { return .theirs }
            return .tie
        }
    }

    // MARK: - Metric Table (LOCKED ORDER)

    /// Ordered array (never a dictionary) so the row order is deterministic:
    /// adherence → level → XP → current streak → longest streak → badges → rank.
    private var metrics: [Metric] {
        let rankScores = rankComparisonScores()
        return [
            Metric(
                label: "Weekly adherence",
                mineDisplay: "\(mine.weeklyGoalsMet)/7",
                theirsDisplay: "\(theirs.weeklyGoalsMet)/7",
                mineScore: Double(mine.weeklyGoalsMet),
                theirsScore: Double(theirs.weeklyGoalsMet)
            ),
            Metric(
                label: "Level",
                mineDisplay: "\(mine.level)",
                theirsDisplay: "\(theirs.level)",
                mineScore: Double(mine.level),
                theirsScore: Double(theirs.level)
            ),
            Metric(
                label: "Total XP",
                mineDisplay: mine.totalXP.formatted(),
                theirsDisplay: theirs.totalXP.formatted(),
                mineScore: Double(mine.totalXP),
                theirsScore: Double(theirs.totalXP)
            ),
            Metric(
                label: "Current streak",
                mineDisplay: "\(mine.currentStreak)",
                theirsDisplay: "\(theirs.currentStreak)",
                mineScore: Double(mine.currentStreak),
                theirsScore: Double(theirs.currentStreak)
            ),
            Metric(
                label: "Longest streak",
                mineDisplay: "\(mine.longestStreak ?? 0)",
                theirsDisplay: "\(theirs.longestStreak ?? 0)",
                mineScore: Double(mine.longestStreak ?? 0),
                theirsScore: Double(theirs.longestStreak ?? 0)
            ),
            Metric(
                label: "Badges",
                mineDisplay: "\(mine.badgeCount ?? 0)",
                theirsDisplay: "\(theirs.badgeCount ?? 0)",
                mineScore: Double(mine.badgeCount ?? 0),
                theirsScore: Double(theirs.badgeCount ?? 0)
            ),
            Metric(
                label: "Rank",
                mineDisplay: Rank.displayString(rr: mine.rr, legacyRank: mine.rank),
                theirsDisplay: Rank.displayString(rr: theirs.rr, legacyRank: theirs.rank),
                // Prefer rr (higher wins) when both have it; else fall back to the
                // Rank.allCases index. Unknown/retired strings tie (see rankComparisonScores).
                mineScore: rankScores.mine,
                theirsScore: rankScores.theirs
            )
        ]
    }

    /// Decisive (scored, non-tied) metrics — the denominator of the tally.
    private var decisiveCount: Int { metrics.filter { $0.leader != .tie }.count }

    /// Metrics the current user leads — the numerator. Ties count toward neither.
    private var myWins: Int { metrics.filter { $0.leader == .mine }.count }

    // MARK: - Body

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            headerRow
            tallyPill

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(metrics) { metric in
                    metricRow(metric)
                }
            }

            // joinedAt is NOT scored — neutral context only, never a win/lose row.
            memberSinceFooter
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Header

    /// The two sides: "You" on the left, the friend on the right, tinted with
    /// their rank color for identity.
    private var headerRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text("You")
                .font(AppFont.bold(14))
                .foregroundColor(tc.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("vs")
                .font(AppFont.regular(11))
                .foregroundColor(tc.textTertiary)

            Text(theirName)
                .font(AppFont.bold(14))
                .foregroundColor(theirAccent)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var tallyPill: some View {
        Text(tallyText)
            .font(AppFont.bold(13))
            .foregroundColor(tc.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 6)
            .adaptivePill(borderColor: tc.primary.opacity(0.4), fillColor: tc.primary.opacity(0.10))
    }

    private var tallyText: String {
        guard decisiveCount > 0 else { return "All even" }
        return "You lead \(myWins) of \(decisiveCount)"
    }

    // MARK: - Metric Row

    /// Three columns: my value (left), the metric label (center), their value
    /// (right). The leader's value is highlighted; a tie leaves both neutral.
    private func metricRow(_ metric: Metric) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            valueCell(metric.mineDisplay, highlighted: metric.leader == .mine, color: tc.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(metric.label)
                .font(AppFont.regular(11))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 104)

            valueCell(metric.theirsDisplay, highlighted: metric.leader == .theirs, color: theirAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    /// A single value: bold + tinted + a faint capsule when it leads; plain
    /// secondary text when it loses or ties.
    private func valueCell(_ text: String, highlighted: Bool, color: Color) -> some View {
        Text(text)
            .font(AppFont.bold(highlighted ? 17 : 15))
            .foregroundColor(highlighted ? color : tc.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, highlighted ? DesignSystem.Spacing.sm : 0)
            .padding(.vertical, highlighted ? 3 : 0)
            .background {
                if highlighted {
                    Capsule().fill(color.opacity(0.14))
                }
            }
    }

    // MARK: - Member Since (neutral, not scored)

    @ViewBuilder
    private var memberSinceFooter: some View {
        if mine.joinedAt != nil || theirs.joinedAt != nil {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text(memberSince(mine.joinedAt))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Member since")
                    .frame(width: 104)

                Text(memberSince(theirs.joinedAt))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(AppFont.regular(10))
            .foregroundColor(tc.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func memberSince(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    // MARK: - Rank Comparison

    /// Comparison scores for the Rank metric. Prefers `rr` (higher wins) when BOTH
    /// sides have it; otherwise falls back to the rank strings' index in
    /// `Rank.allCases`. If either string doesn't resolve to a current `Rank` case
    /// (retired/unknown, e.g. "bronze" from an old build), both score 0 → the metric
    /// ties (never guessed, never crashes).
    private func rankComparisonScores() -> (mine: Double, theirs: Double) {
        if let mr = mine.rr, let tr = theirs.rr { return (Double(mr), Double(tr)) }
        guard let mi = Rank(rawValue: mine.rank).flatMap({ Rank.allCases.firstIndex(of: $0) }),
              let ti = Rank(rawValue: theirs.rank).flatMap({ Rank.allCases.firstIndex(of: $0) })
        else { return (0, 0) }
        return (Double(mi), Double(ti))
    }

    // MARK: - Friend Identity / Color

    private var theirName: String {
        theirs.displayName.isEmpty ? "@\(theirs.username)" : theirs.displayName
    }

    /// The friend's rank color — same mapping the profile and leaderboard use.
    private var theirAccent: Color {
        switch theirs.rank {
        case Rank.stone.rawValue: return Color(hex: "#A8A29E")
        case Rank.copper.rawValue: return Color(hex: "#B87333")
        case Rank.iron.rawValue: return tc.textTertiary
        case Rank.gold.rawValue: return DesignSystem.Colors.goldMid
        case Rank.platinum.rawValue: return Color(hex: "#5EEAD4")
        case Rank.diamond.rawValue: return Color(hex: "#38BDF8")
        case Rank.sentinel.rawValue, Rank.prismatic.rawValue, Rank.zenith.rawValue:
            return Color(hex: "#38BDF8") // TODO: replace placeholder styling before public launch
        case "bronze": return Color(hex: "#CD7F32") // retired pre-RR-0a legacy string
        case "silver": return Color(hex: "#9CA3AF") // retired pre-RR-0a legacy string
        default: return tc.textTertiary
        }
    }
}
