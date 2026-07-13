//
//  StandingsPieces.swift
//  HealthBar
//
//  Created by Claude on 7/13/26.
//

import SwiftUI

/// The standings row's shared visual pieces: rank chip, initials avatar, podium metal.
///
/// R7c §1 — the consolidation rule firing on its third consumer. These three were written for the
/// merged standings mockup in `LeaderboardSection` (Home), then duplicated into `BattleView`'s
/// standings block (the R4b watch-item). FriendsView's rows are the third consumer, so the pieces
/// move here ONCE and the duplicates die.
///
/// This enum is the single canonical implementation — `LeaderboardSection`, `BattleStandingsBlock`
/// and `FriendsView` are consumers only. The function bodies moved byte-identically from
/// `LeaderboardSection` (the merged mockup-truth implementation); the only adaptation a static
/// namespace forces is resolving `tc` from `SettingsManager.shared` instead of the view's own
/// `@State settings` — the same object, read during the caller's `body`, so theme flips still
/// re-render every consumer.
///
/// NOT consumers, deliberately: `GlobalLeaderboardView` and `GuildLeaderboardView`. Their rows are
/// the older compound-tint card anatomy — a large bare numeral (no chip), no avatar at all, and the
/// metal driving the card's border/fill rather than a chip fill. They are not duplicates of these
/// bodies, so migrating them would be a redesign, not a move.
enum StandingsPieces {

    /// Mockup `.pos`: a small rounded-square rank chip. Podium chips are metal-filled (white
    /// numeral); off-podium chips are neutral. Crown kept above #1 (where it lives today).
    static func rankChip(position: Int, hasData: Bool, metal: Color?) -> some View {
        let tc = SettingsManager.shared.activeColors
        return VStack(spacing: 1) {
            if hasData && position == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(metal ?? DesignSystem.Colors.goldMid)
            }
            Text(hasData ? "\(position)" : "–")
                .font(AppFont.display(15))
                .foregroundColor(metal != nil ? .white : (hasData ? tc.textSecondary : tc.textTertiary))
                .monospacedDigit()
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(metal ?? tc.segBackground))
        }
        .frame(width: 30)
    }

    /// Mockup `.av`: 38×38 rounded-square initials avatar, rank-tinted (nil tint → neutral fill).
    static func avatar(initial: String, tint: Color?) -> some View {
        let tc = SettingsManager.shared.activeColors
        return Text(initial)
            .font(AppFont.bold(15))
            .foregroundColor(tint != nil ? .white : tc.textPrimary)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint ?? tc.segBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tint != nil ? Color.white.opacity(0.22) : DesignSystem.Erewhon.line, lineWidth: 1)
                    .padding(3)
            )
    }

    /// Podium metals: gold, silver, bronze. nil off the podium or without data.
    /// Flat (Erewhon) uses the shared rank-metal tokens; pixel keeps its original hexes so
    /// pixel Home stays byte-identical (D7).
    static func podiumMetal(position: Int, hasData: Bool) -> Color? {
        guard hasData else { return nil }
        let isClean = SettingsManager.shared.isCleanUI
        switch position {
        case 1: return isClean ? DesignSystem.Erewhon.rankGold : DesignSystem.Colors.goldMid
        case 2: return isClean ? DesignSystem.Erewhon.rankSilver : Color(hex: "#9CA3AF") // silver
        case 3: return isClean ? DesignSystem.Erewhon.rankBronze : Color(hex: "#CD7F32") // bronze
        default: return nil
        }
    }
}
