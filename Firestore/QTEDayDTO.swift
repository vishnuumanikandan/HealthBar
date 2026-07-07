//
//  QTEDayDTO.swift
//  HealthBar
//
//  Created by Claude on 7/5/26.
//

import Foundation

/// Data Transfer Object for `QTEDay` cloud sync (D1d).
///
/// Firestore path: `users/{uid}/qteDays/{dateKey}` — the doc id is the `dateKey`, NOT the
/// UUID (which rides along as `localId` for round-tripping). `userId` is encoded in the path.
/// Field-wise MAX-WINS merge (points) + logical OR (played flags) lives in DataManager — points
/// are earn-only, so two-device play converges without loss.
struct QTEDayDTO: Codable {
    var localId: String        // QTEDay.id.uuidString
    var dateKey: String
    var sparkPoints: Int
    var sparkPlayed: Bool
    var cleanLogPoints: Int
    var macroGuessPoints: Int
    var macroGuessPlayed: Bool

    init(from day: QTEDay) {
        self.localId = day.id.uuidString
        self.dateKey = day.dateKey
        self.sparkPoints = day.sparkPoints
        self.sparkPlayed = day.sparkPlayed
        self.cleanLogPoints = day.cleanLogPoints
        self.macroGuessPoints = day.macroGuessPoints
        self.macroGuessPlayed = day.macroGuessPlayed
    }

    /// Cold-create a local row from a remote doc (used when no local row exists yet). Points
    /// clamped to their caps defensively.
    func toQTEDay(userId: String) -> QTEDay {
        QTEDay(
            id: UUID(uuidString: localId) ?? UUID(),
            userId: userId,
            dateKey: dateKey,
            sparkPoints: min(DuelConstants.sparkPointsCap, sparkPoints),
            sparkPlayed: sparkPlayed,
            cleanLogPoints: min(DuelConstants.cleanLogPointsCap, cleanLogPoints),
            macroGuessPoints: min(DuelConstants.macroGuessPointsCap, macroGuessPoints),
            macroGuessPlayed: macroGuessPlayed
        )
    }

    /// True if any synced field differs — lets the sync skip no-op uploads.
    func differsFrom(_ day: QTEDay) -> Bool {
        dateKey != day.dateKey
            || sparkPoints != day.sparkPoints
            || sparkPlayed != day.sparkPlayed
            || cleanLogPoints != day.cleanLogPoints
            || macroGuessPoints != day.macroGuessPoints
            || macroGuessPlayed != day.macroGuessPlayed
    }
}
