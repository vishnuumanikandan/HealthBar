//
//  RankJourneyCard.swift
//  HealthBar
//
//  Created by Claude on 7/22/26.
//
//  D3b (D9 extraction). The Rank Journey card + its RR/tier math, moved VERBATIM out of
//  ProfileView / ProfileViewModel (D2 is the canonical source — this is a MOVE, not a rewrite)
//  so a SECOND surface (FriendProfileView) can render the identical card. The justification
//  class is AvatarKit's: a two-consumer shared component, no new file otherwise.
//
//  The card consumes SOLELY `rr` (own page: `userProgress.rr`; FPV: `stats?.rr`). All rank math
//  stays here / in Rank.swift (untouched) — after this extraction neither ProfileViewModel nor
//  FriendProfileViewModel carries any journey-card RR/tier computation.
//

import SwiftUI

// MARK: - Rank Journey (math)

/// Rank Journey card view-data, a pure function of `rr` through Rank.swift's existing API
/// (no new math constants). Verified by a standalone TDD harness against Rank.swift.
struct RankJourney {
    let rr: Int

    var rank: Rank { Rank.getRank(from: rr) }
    private var tierInfo: RankTier { Rank.rankTier(from: rr) }
    var tier: Int { tierInfo.tier }

    /// Card title / caption-left: the current tier's name, e.g. "Copper 2".
    var tierTitle: String { tierInfo.displayName }

    /// Peak of the ladder: top rank, top tier — the bar + caption are replaced by one line.
    var isPeak: Bool { rank == .zenith && tier == Rank.tiersPerRank }

    /// Sub-line: "<rr> RR · Rank <i> of <count>" — `i` is the 1-based position of the current
    /// rank in `Rank.allCases`, `<count>` is `Rank.allCases.count` (no hardcoded 9).
    var rankIndex: Int { (Rank.allCases.firstIndex(of: rank) ?? 0) + 1 }
    var rankCount: Int { Rank.allCases.count }
    var subline: String { "\(rr) RR · Rank \(rankIndex) of \(rankCount)" }

    /// RR at which the current tier begins: `rank.rrThreshold + (tier − 1) * Rank.rrPerTier`.
    private var currentTierFloor: Int { rank.rrThreshold + (tier - 1) * Rank.rrPerTier }
    private var nextTierFloor: Int { currentTierFloor + Rank.rrPerTier }

    /// Progress through the current tier: `(rr − currentTierFloor) / Rank.rrPerTier`, clamped 0…1.
    var fill: Double {
        min(1, max(0, Double(rr - currentTierFloor) / Double(Rank.rrPerTier)))
    }

    /// RR still needed to reach the next tier.
    var remaining: Int { max(0, nextTierFloor - rr) }

    /// The next rank in ladder order (`Rank.allCases`), or nil at the top.
    private var nextRank: Rank? {
        let all = Rank.allCases
        guard let idx = all.firstIndex(of: rank), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    /// ASCENDING next-tier label: tier+1 in the same rank, or the NEXT rank's tier 1 when at
    /// tier 3 (Copper 2 → Copper 3 → Iron 1). Fixes the mockup's descending "Copper 1" error.
    var nextTierLabel: String {
        if tier < Rank.tiersPerRank {
            return "\(rank.displayName) \(tier + 1)"
        } else if let nr = nextRank {
            return "\(nr.displayName) 1"
        } else {
            return tierTitle   // zenith tier 3 = peak; caption is replaced upstream.
        }
    }

    /// Caption-right: "<remaining> RR to <next>".
    var captionRight: String { "\(remaining) RR to \(nextTierLabel)" }
}

// MARK: - Rank Journey (card)

/// The D2 Rank Journey card — driven purely by `rr` via `RankJourney` (Rank.swift's API). Rendered
/// on the own profile (ProfileView) and on any profile (FriendProfileView). The caller decides
/// WHEN to show it (only when it holds a real `rr`) — there is no invented default RR, no
/// force-unwrap; a nil-rr caller shows its own legacy fallback instead of this card.
struct RankJourneyCard: View {
    let rr: Int

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        let journey = RankJourney(rr: rr)
        // rankMetal returns nil for Stone (and nil rr); FriendProfileView.rankColor is the
        // canonical per-rank switch, but D8 forbids new hex here, so fall back to the neutral
        // textTertiary token (the established `?? tc.textTertiary` FriendsView pattern).
        let accent = DesignSystem.Erewhon.rankMetal(forRR: journey.rr) ?? tc.textTertiary
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.md) {
                RankPlaque(rank: journey.rank, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.tierTitle)
                        .font(AppFont.bold(22))
                        .foregroundColor(tc.textPrimary)
                    Text(journey.subline)
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textSecondary)
                        .monospacedDigit()
                }

                Spacer()
            }

            if journey.isPeak {
                // Peak state: bar + caption replaced by a single line (D3).
                Text("Peak of the ladder")
                    .font(AppFont.bold(14))
                    .foregroundColor(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Progress bar: fill = (rr − currentTierFloor) / Rank.rrPerTier, clamped 0…1.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        AdaptivePillShapeStyle()
                            .fill(accent.opacity(0.18))
                        AdaptivePillShapeStyle()
                            .fill(accent)
                            .frame(width: max(0, geo.size.width * journey.fill))
                    }
                }
                .frame(height: 8)

                // Caption: left = current tier name; right = "<remaining> RR to <next>"
                // (ascending — next tier in-rank, or the next rank's tier 1 at tier 3).
                HStack {
                    Text(journey.tierTitle)
                    Spacer()
                    Text(journey.captionRight)
                }
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .monospacedDigit()
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: accent.opacity(0.4), fillColor: tc.cardBackground)
    }
}
