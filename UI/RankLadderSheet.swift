//
//  RankLadderSheet.swift
//  HealthBar
//
//  Created by Claude on 7/12/26.
//

import SwiftUI

/// R7b §4b: the full ranked ladder, presented from the tappable rank block on Battle. Nine
/// rows Stone → Zenith, each a plaque · rank name · RR band. Read-only — no actions in rows.
///
/// The current rank (derived from `currentRR` via `Rank.getRank`) is highlighted through the
/// R6c explicit `isSelected` API — the ladder's the first intentional consumer. `currentRR`
/// nil (the progress fetch failed upstream) highlights nothing.
struct RankLadderSheet: View {

    let currentRR: Int?

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// The rank the user currently occupies, or nil when RR is unknown (→ no highlight).
    private var currentRank: Rank? {
        currentRR.map { Rank.getRank(from: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom drag handle (sheet convention — the system indicator is hidden below).
            AdaptivePillShapeStyle()
                .fill(tc.primary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)

            Text("RANKED LADDER")
                .font(AppFont.display(20))
                .foregroundColor(tc.textPrimary)
                .padding(.bottom, DesignSystem.Spacing.md)

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Rank.allCases, id: \.self) { rank in
                        ladderRow(rank)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.CornerRadius.xl)
    }

    /// One ladder row. The current-rank row uses the R6c explicit `isSelected` selection ring;
    /// every other row is a quiet hairline.
    private func ladderRow(_ rank: Rank) -> some View {
        let isCurrent = (currentRank == rank)
        return HStack(spacing: DesignSystem.Spacing.md) {
            RankPlaque(rank: rank, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rank.displayName)
                    .font(AppFont.display(18))
                    .foregroundColor(tc.textPrimary)
                Text(rrRangeText(rank))
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: isCurrent ? tc.primary : tc.primary.opacity(0.15),
            fillColor: tc.cardBackground,
            isSelected: isCurrent
        )
    }

    /// RR band for a rank, straight from the tuning constants (no magic numbers). The top rank
    /// has no ceiling ("2400+ RR"); every other rank spans `rrPerTier × tiersPerRank` and is
    /// rendered as a closed range ("300–599 RR").
    private func rrRangeText(_ rank: Rank) -> String {
        let lower = rank.rrThreshold
        let span = Rank.rrPerTier * Rank.tiersPerRank
        if rank == Rank.allCases.last {
            return "\(lower)+ RR"
        }
        return "\(lower)–\(lower + span - 1) RR"
    }
}
