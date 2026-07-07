//
//  DuelUIState.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import SwiftUI

/// A resolved-duel summary for the end-of-duel recap sheet (D1c). Captured at RR-claim
/// time in DataManager and presented from the Battle tab. Pure presentation state.
struct DuelResolutionSummary: Identifiable, Equatable {
    enum Outcome: Equatable { case won, lost, draw, forfeitLoss, forfeitWin }

    let duelId: String
    let opponentLabel: String
    let outcome: Outcome
    let rrDelta: Int
    let preRR: Int                // my rr immediately before applying the delta
    let postRR: Int               // my rr immediately after (floored at 0)
    let myScore: Double
    let theirScore: Double
    let league: Int
    let myDayScores: [Double]      // my side's per-day array at claim time
    let theirDayScores: [Double]   // opponent's per-day array at claim time

    var id: String { duelId }
}

/// A qualifying low-toxin meal logged mid-duel, awaiting the clean-log QTE sheet (D1d).
struct PendingCleanLogQTE: Identifiable, Equatable {
    let id = UUID()
    let mealName: String
}

/// Cross-tab duel presentation state (D1c).
///
/// Every tab constructs its own `AppCoordinator`/`DataManager`, so coordinator-held state
/// cannot cross tabs. This singleton carries the active-duel badge count, the unseen-changes
/// pulse flag, the end-of-duel recap queue, and the Home→Battle Arena deep link. It holds
/// ONLY presentation state — no Firestore types, no persistence of its own. Follows the
/// `BadgeToastQueue.shared` precedent (DataManager writes via `MainActor.run`; views read).
@Observable
@MainActor
final class DuelUIState {
    static let shared = DuelUIState()
    private init() {}

    var activeDuelCount: Int = 0
    var hasUnseenChanges: Bool = false
    private(set) var pendingResolutions: [DuelResolutionSummary] = []

    /// Home strip tap → Battle tab pushes the Arena for this duel. Consumed exactly once.
    var pendingArenaDuelId: String? = nil

    /// Set by DataManager when a qualifying low-toxin meal is logged mid-duel; ContentView
    /// presents the clean-log QTE sheet off it (root-level, covering every logging flow). One
    /// at a time — a second qualifying meal while one is pending is skipped (no queue).
    var pendingCleanLogQTE: PendingCleanLogQTE? = nil

    /// Queue a recap (FIFO, deduped by duelId, capped at 10 — drops the newest beyond cap).
    func enqueueResolution(_ s: DuelResolutionSummary) {
        guard !pendingResolutions.contains(where: { $0.duelId == s.duelId }) else { return }
        guard pendingResolutions.count < 10 else { return }
        pendingResolutions.append(s)
    }

    func dequeueResolution() {
        guard !pendingResolutions.isEmpty else { return }
        pendingResolutions.removeFirst()
    }

    /// Zero everything (guest / signed out).
    func reset() {
        activeDuelCount = 0
        hasUnseenChanges = false
        pendingResolutions.removeAll()
        pendingArenaDuelId = nil
        pendingCleanLogQTE = nil
    }
}
