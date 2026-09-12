//
//  WaterDay.swift
//  HealthBar
//
//  Created by Claude on 8/29/26.
//

import Foundation
import SwiftData

/// Every water-domain number, named once (WATER-1 D1).
///
/// No water value — in executable logic OR in user-facing copy — may be restated as a
/// literal anywhere else. UI strings interpolate these (e.g. `"ml (\(mlPerCup) per cup)"`).
///
/// Storage is **cups-canonical forever** (D2): `WaterDay.cupCount` and
/// `DailyGoal.waterGoalCups` are integer cups, and millilitres exist only as a render-time
/// conversion. There is no stored ml value anywhere.
enum WaterConstants {

    // MARK: - The table (D1)

    /// Millilitres in one cup. Display-only: taps always add exactly one *cup*.
    static let mlPerCup = 250

    /// Goal used when `DailyGoal.waterGoalCups` is nil ("never set").
    static let defaultGoalCups = 8

    /// Lower bound of an editable/displayed goal.
    static let minGoalCups = 1

    /// Upper bound of an editable/displayed goal.
    static let maxGoalCups = 35

    // MARK: - Vessel geometry (D12/D13)

    /// One quantisation unit, in points. The mockup's pixel grid scaled to the 87 pt
    /// vessel: 8 × 29 units at 3 pt = 24 × 87.
    static let unitSize: CGFloat = 3

    /// Whole units of inner well available to the fill — the mockup's `h - 2`, i.e. the
    /// 29-unit column less the one-unit inset at each end. 27 units × 3 pt = 81 pt of
    /// well inside an 87 pt vessel.
    static let wellUnits = 27

    /// Vessel height: the macro **bar run** exactly (bar 1's top edge to bar 3's bottom
    /// edge), so switching water on does not change the food hero's height and the column
    /// reads as a fourth track. Must stay equal to `unitSize × (wellUnits + 2)`.
    static let vesselHeight: CGFloat = 87

    /// Vessel width and corner radius (mockup `.wtube`).
    static let vesselWidth: CGFloat = 22
    static let vesselRadius: CGFloat = 7

    /// Corner add-button diameter. Named here because TWO sites must agree on it: the disc
    /// itself and the splash burst, whose ripple and crown geometry is expressed in disc
    /// radii. A literal at each site would drift the moment one of them changed.
    static let buttonDiameter: CGFloat = 52

    /// Stepped crest profile, period 8 — how many whole units the water rises in each
    /// column. Drift is expressed by rotating the index, never by a sub-unit translate,
    /// so every frame lands on the grid (the mockup's `steps(8)`, which is load-bearing).
    static let crestProfile = [0, 0, 1, 1, 1, 0, 0, 0]

    /// One stepped wave frame, in seconds (mockup: one period-8 cycle over 2.4 s).
    static let waveStepSeconds: Double = 0.3

    // MARK: - Derived values (the only sites that combine the table)

    /// Display clamp, applied on every read of a stored goal (D9).
    static func clampedGoal(_ cups: Int) -> Int {
        max(minGoalCups, min(maxGoalCups, cups))
    }

    /// Resolves a stored goal for display/edit: nil means "never set" → the default,
    /// and any out-of-range value from any source is display-clamped (D7/D11).
    static func resolvedGoal(_ stored: Int?) -> Int {
        clampedGoal(stored ?? defaultGoalCups)
    }

    /// Render-time cups → millilitres (D2). Never persisted.
    static func milliliters(cups: Int) -> Int {
        cups * mlPerCup
    }

    /// Quantised fill: `floor(wellUnits × min(count, goal) / goal)` whole units (D13).
    /// The waterline therefore never settles on a fractional unit.
    ///
    /// Consequence of the ruled `floor` at the goal's upper bound: with a 35-cup goal the
    /// first cup is `floor(27/35) == 0` units, so it moves the count but not the fill.
    static func filledUnits(count: Int, goal: Int) -> Int {
        let safeGoal = max(1, goal)
        let capped = max(0, min(count, safeGoal))
        return wellUnits * capped / safeGoal   // Int division == floor for non-negatives
    }
}

/// One local calendar day's water count — LOCAL-ONLY, by design (D6).
///
/// There is no DTO, no Firestore path and no sync for this model: today's cups do not
/// survive a reinstall. The *goal* (`DailyGoal.waterGoalCups`) does, because it rides the
/// existing DailyGoal sync. That asymmetry is deliberate — see the CLAUDE.md lesson.
///
/// Identity is logically `(userId, day)`, but that is NOT encoded in `id`: `id` is
/// SwiftData identity only, never a deterministic day key.
///
/// Daily reset is bucketing, not a job (D16): a new local day simply has no row until the
/// first tap. Nothing observes midnight.
@Model
final class WaterDay {

    /// SwiftData identity only. Never a deterministic day key.
    var id: UUID

    /// The day this count belongs to, bucketed to `startOfDay` in the user's LOCAL
    /// calendar/timezone. Deliberate contrast with `aiUsage`, which is UTC by design:
    /// water rolls over when the user's day does.
    var date: Date

    /// Cups logged on `date`. Cups-canonical (D2) — never millilitres.
    var cupCount: Int

    /// Scopes this record to a user. The `"legacy"` default exists solely for SwiftData
    /// model compatibility; every newly created row explicitly stamps `currentUserId`
    /// (guests resolve to `"guest"`), so no new row ever carries `"legacy"`.
    var userId: String = "legacy"

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        cupCount: Int = 0,
        userId: String = "legacy"
    ) {
        self.id = id
        self.date = date
        self.cupCount = cupCount
        self.userId = userId
    }
}
