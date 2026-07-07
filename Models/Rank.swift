//
//  Rank.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Represents user rank tiers derived from **RR (Ranked Rating)**.
///
/// Rank is an identity signal earned through ranked play — NOT from XP.
/// It is a pure function of `rr` (`Rank.getRank(from: rr)`); `totalXP` drives
/// `currentLevel` only. Never reintroduce an XP→rank derivation.
///
/// The ladder spans 9 ranks, each 3 tiers of `rrPerTier` RR (300 RR per rank).
enum Rank: String, Codable, CaseIterable {
    case stone
    case copper
    case iron
    case gold
    case platinum
    case diamond
    case rankVII    // TODO: rename
    case rankVIII   // TODO: rename
    case rankIX     // TODO: rename

    // MARK: - Tuning Constants

    /// Change these to rebalance the entire ladder in one place — no magic numbers elsewhere.

    /// RR every new (and migrated) user starts at — Copper 2.
    static let startingRR = 450
    /// RR span of a single tier.
    static let rrPerTier = 100
    /// Tiers per rank. A rank therefore spans `rrPerTier * tiersPerRank` (= 300 RR).
    static let tiersPerRank = 3

    /// Base RR at which this rank begins.
    ///
    /// Derived from declaration order so a rebalance is a one-line constant edit:
    ///   stone 0, copper 300, iron 600, gold 900, platinum 1200, diamond 1500,
    ///   rankVII 1800, rankVIII 2100, rankIX 2400.
    var rrThreshold: Int {
        let index = Rank.allCases.firstIndex(of: self) ?? 0
        return index * Rank.rrPerTier * Rank.tiersPerRank
    }

    /// Calculates the appropriate rank from a Ranked Rating.
    /// - Parameter rr: User's RR (rank derives from RR only, never from XP).
    /// - Returns: The highest rank whose threshold is met; `.stone` for any `rr`
    ///   below Copper (including 0 or negative).
    static func getRank(from rr: Int) -> Rank {
        // Iterate highest → lowest; return the first rank whose threshold is met.
        for rank in Rank.allCases.reversed() where rank.rrThreshold <= rr {
            return rank
        }
        return .stone
    }

    /// Tier within a rank, `rrPerTier` RR each. E.g. for Copper (300–599):
    ///   RR 300–399 → Copper 1, RR 400–499 → Copper 2, RR 500–599 → Copper 3
    /// - Parameter rr: User's RR.
    /// - Returns: The rank plus its tier, clamped to 1…3 (the top rank caps at tier 3).
    static func rankTier(from rr: Int) -> RankTier {
        let r = Rank.getRank(from: rr)
        let tier = min(Rank.tiersPerRank, max(1, (rr - r.rrThreshold) / Rank.rrPerTier + 1))
        return RankTier(rank: r, tier: tier)
    }

    /// Display name for the rank.
    var displayName: String {
        switch self {
        case .stone, .copper, .iron, .gold, .platinum, .diamond:
            return rawValue.capitalized
        case .rankVII:
            return "Rank VII"
        case .rankVIII:
            return "Rank VIII"
        case .rankIX:
            return "Rank IX"
        }
    }
}

/// A rank plus the tier (1…3) the user occupies within it. Used for RR-0b display.
struct RankTier {
    let rank: Rank
    let tier: Int          // 1...3
    var displayName: String { "\(rank.displayName) \(tier)" }
}
