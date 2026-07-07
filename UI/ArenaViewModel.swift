//
//  ArenaViewModel.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import Foundation

/// Drives the Arena — the signature single-duel view (D1c). Pure presentation over a
/// `DuelDTO`; refresh funnels through the coordinator's full `loadMyDuels()` lifecycle.
@Observable
@MainActor
final class ArenaViewModel {

    private let coordinator: AppCoordinator
    private let myUid: String

    private(set) var duel: DuelDTO
    /// True when the last refresh could not find this duel (deleted/canceled elsewhere).
    private(set) var isStale = false
    private(set) var inFlight = false
    var toastMessage: String?

    init(coordinator: AppCoordinator, myUid: String, duel: DuelDTO) {
        self.coordinator = coordinator
        self.myUid = myUid
        self.duel = duel
    }

    func refresh() async {
        let all = await coordinator.loadMyDuels()
        if let fresh = all.first(where: { $0.id == duel.id }) {
            duel = fresh
            isStale = false
        } else {
            isStale = true // keep last-known render; no pop, no alert
        }
        await coordinator.markDuelsSeen([duel], isFullList: false)
    }

    // MARK: - Rounding helper (rounded-int convention; never raw Double compare)

    private func tenths(_ v: Double) -> Int { Int((v * 10).rounded()) }

    // MARK: - Display

    var myLabel: String { "You" }
    var theirLabel: String { duel.opponentLabel(of: myUid) }
    var myScore: Double { duel.myScore(myUid) }
    var theirScore: Double { duel.theirScore(myUid) }
    var myScoreText: String { "\(Int(myScore.rounded()))" }
    var theirScoreText: String { "\(Int(theirScore.rounded()))" }
    var iAmLeading: Bool { tenths(myScore) > tenths(theirScore) }
    var league: Int { duel.league }
    func leagueLabel() -> String { "\(duel.league)-DAY" }

    var isActive: Bool { duel.statusEnum == .active }
    var isFinished: Bool { duel.statusEnum == .resolved || duel.statusEnum == .forfeited }
    var endAt: Date? { duel.endAt }
    var resolvedAt: Date? { duel.resolvedAt }

    /// Fill fraction of the tug-of-war bar. 0.5 at a rounded tie or 0–0; else my share of the
    /// total, clamped so neither side is ever fully pushed out.
    var barFraction: Double {
        let m = tenths(myScore), t = tenths(theirScore)
        if m == t { return 0.5 }               // covers 0–0 and any exact tie
        let total = myScore + theirScore
        guard total > 0 else { return 0.5 }
        return min(0.92, max(0.08, myScore / total))
    }

    /// Endgame: less than one duel-day remaining (reuse the constant — no magic 86_400).
    var isEndgame: Bool {
        guard isActive, let endAt = duel.endAt else { return false }
        return endAt.timeIntervalSinceNow < DuelConstants.secondsPerDay
    }

    // MARK: - Day timeline

    struct DayRow: Identifiable {
        enum State { case done, current, upcoming }
        let dayNumber: Int
        let myScore: Double?
        let theirScore: Double?
        let state: State
        var id: Int { dayNumber }

        /// true → I won the day, false → they did, nil → tie / incomplete (no marker).
        var myWins: Bool? {
            guard let m = myScore, let t = theirScore else { return nil }
            let mi = Int((m * 10).rounded()), ti = Int((t * 10).rounded())
            if mi == ti { return nil }
            return mi > ti
        }
    }

    var dayRows: [DayRow] {
        let myDays = duel.isChallenger(myUid) ? duel.resolvedChallengerDayScores : duel.resolvedOpponentDayScores
        let theirDays = duel.isChallenger(myUid) ? duel.resolvedOpponentDayScores : duel.resolvedChallengerDayScores
        let calendar = Calendar.current

        // Current duel-day index (same definition as updateMyDuelScores). -1 when finished
        // or acceptedAt missing → no `current` row.
        var currentIndex = -1
        if isActive, let acceptedAt = duel.acceptedAt {
            let day1 = calendar.startOfDay(for: acceptedAt)
            let today = calendar.startOfDay(for: Date())
            currentIndex = calendar.dateComponents([.day], from: day1, to: today).day ?? -1
        }

        return (0..<max(0, duel.league)).map { idx in
            let my = idx < myDays.count ? myDays[idx] : nil
            let their = idx < theirDays.count ? theirDays[idx] : nil
            let state: DayRow.State
            if isFinished || idx < currentIndex {
                state = .done
            } else if idx == currentIndex {
                state = .current
            } else {
                state = .upcoming
            }
            return DayRow(dayNumber: idx + 1, myScore: my, theirScore: their, state: state)
        }
    }

    // MARK: - Finished / projected

    /// Reuses the exact wording logic of BattleViewModel.finishedLabel (duplicated locally
    /// per the D1c spec — do not rename or change that method).
    var outcomeHeadline: String {
        switch duel.statusEnum {
        case .forfeited: return duel.forfeitedBy == myUid ? "Forfeit" : "Won"
        case .resolved:
            if duel.winnerUid == nil { return "Draw" }
            return duel.winnerUid == myUid ? "Won" : "Lost"
        default: return duel.status.capitalized
        }
    }

    var rrDeltaText: String? {
        guard isFinished, let delta = duel.myRRDelta(myUid) else { return nil }
        return delta >= 0 ? "+\(delta) RR" : "\(delta) RR"
    }

    var canRematch: Bool {
        guard isFinished, let resolvedAt = duel.resolvedAt else { return false }
        return Date() < resolvedAt.addingTimeInterval(DuelConstants.rematchWindow)
    }

    /// Projected RR — a preview of the deterministic resolution at the current leader, not a
    /// promise. Active duels only.
    var projectedRRText: String? {
        guard isActive else { return nil }
        let winner = DuelDTO.scoreWinner(challengerScore: duel.challengerScore, opponentScore: duel.opponentScore)
        if winner == .draw { return "Projected: draw · +\(DuelConstants.drawDelta(league: duel.league)) each" }
        let deltas = DuelDTO.resolveDeltas(duelId: duel.id ?? "", league: duel.league, winner: winner)
        let myDelta = duel.isChallenger(myUid) ? deltas.challenger : deltas.opponent
        let theirDelta = duel.isChallenger(myUid) ? deltas.opponent : deltas.challenger
        let mySign = myDelta >= 0 ? "+" : ""
        let theirSign = theirDelta >= 0 ? "+" : ""
        return "Projected: You \(mySign)\(myDelta) · \(theirLabel) \(theirSign)\(theirDelta)"
    }

    // MARK: - Actions (same shape as BattleViewModel)

    func forfeit() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            try await coordinator.forfeitDuel(duel)
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't forfeit."
        }
        await refresh()
    }

    func rematch() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            try await coordinator.rematch(duel)
            toastMessage = "Rematch sent"
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't send the rematch."
        }
        await refresh()
    }
}
