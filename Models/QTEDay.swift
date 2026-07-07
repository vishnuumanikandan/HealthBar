//
//  QTEDay.swift
//  HealthBar
//
//  Created by Claude on 7/5/26.
//

import Foundation
import SwiftData

/// One day's Quick-Time-Event earnings (D1d), keyed by the user's LOCAL calendar date.
/// Points are earn-only and feed the duel day-score's `qteBonus` term (shared cap
/// `DuelConstants.qteBonusCap`). One row per user per day; synced to
/// `users/{uid}/qteDays/{dateKey}` so recomputed duel scores don't flap between devices.
@Model
final class QTEDay {
    var id: UUID
    /// Scopes to the authenticated user (inline default = lightweight migration).
    var userId: String = "legacy"
    /// "yyyy-MM-dd" in the user's LOCAL calendar — the deterministic Firestore doc id.
    var dateKey: String = ""

    var sparkPoints: Int = 0            // 0…sparkPointsCap
    var sparkPlayed: Bool = false       // one attempt/day regardless of outcome
    var cleanLogPoints: Int = 0         // 0…cleanLogPointsCap
    var macroGuessPoints: Int = 0       // 0…macroGuessPointsCap
    var macroGuessPlayed: Bool = false  // one attempt/day regardless of outcome

    init(
        id: UUID = UUID(),
        userId: String = "legacy",
        dateKey: String = "",
        sparkPoints: Int = 0,
        sparkPlayed: Bool = false,
        cleanLogPoints: Int = 0,
        macroGuessPoints: Int = 0,
        macroGuessPlayed: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.dateKey = dateKey
        self.sparkPoints = sparkPoints
        self.sparkPlayed = sparkPlayed
        self.cleanLogPoints = cleanLogPoints
        self.macroGuessPoints = macroGuessPoints
        self.macroGuessPlayed = macroGuessPlayed
    }

    /// Capped daily total (≤ `qteBonusCap`; belt-and-braces — the three caps already sum to 10).
    var totalPoints: Int {
        min(Int(DuelConstants.qteBonusCap), sparkPoints + cleanLogPoints + macroGuessPoints)
    }

    /// The local-calendar date key ("yyyy-MM-dd"). The ONLY place a formatter is built —
    /// all call sites use this.
    static func dateKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
