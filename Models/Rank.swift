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
///
/// RAW VALUES ARE PERSISTED — DO NOT "TIDY" THEM. The top three cases pin raw values
/// to their pre-R7a spellings on purpose. `Rank.rawValue` is written into Firestore in
/// two places: the `public/stats.rank` projection (`UserProgress.rank`) and — worse —
/// the DETERMINISTIC feed-event doc id `feedEvents/rank_<rawValue>`, whose body is read
/// back through `Rank(rawValue:)` (FeedEventDTO). Feed events are immutable milestone
/// records that never re-emit, so changing a raw value silently orphans every already
/// published rank milestone (it decodes to nil and the row is dropped from the feed).
/// The same trap already cost this codebase the retired "bronze"/"silver" legacy arms
/// still special-cased in the rank-colour switches. Rename the CASE freely; the raw
/// value is a wire format. Retire the legacy strings in RR-2 behind a real migration.
enum Rank: String, Codable, CaseIterable {
    case stone
    case copper
    case iron
    case gold
    case platinum
    case diamond
    case sentinel = "rankVII"
    case prismatic = "rankVIII"
    case zenith = "rankIX"

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
    ///   sentinel 1800, prismatic 2100, zenith 2400.
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

    /// Display name for the rank ("Stone", "Sentinel", …).
    ///
    /// Derived from the CASE NAME, not `rawValue` — the top three raw values are pinned
    /// legacy wire strings (see the type doc), so `rawValue.capitalized` would render
    /// "Rankvii".
    var displayName: String {
        String(describing: self).capitalized
    }
}

/// A rank plus the tier (1…3) the user occupies within it. Used for RR-0b display.
struct RankTier {
    let rank: Rank
    let tier: Int          // 1...3
    var displayName: String { "\(rank.displayName) \(tier)" }
}
