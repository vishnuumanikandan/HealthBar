//
//  BattleViewModel.swift
//  HealthBar
//
//  Created by Claude on 7/3/26.
//

import Foundation

/// Drives the Battle tab (D1a): loads the user's duels, buckets them into
/// explicitly-sorted sections, and runs accept/decline/cancel with a per-row
/// in-flight flag. Fetch-on-view + pull-to-refresh; no listeners; in memory only.
/// Guests never construct a live one (the Battle tab shows the sign-in card).
@Observable
@MainActor
final class BattleViewModel {

    private let coordinator: AppCoordinator
    /// My Firebase uid — the bucketing key (challenger vs opponent).
    private let myUid: String

    /// All my duels, newest first (already lazily-expired by the coordinator).
    private(set) var duels: [DuelDTO] = []
    private(set) var isLoading = false
    private(set) var didLoadOnce = false

    /// duelIds currently mutating — disables that row's buttons and blocks double-taps.
    private(set) var inFlightDuelIds: Set<String> = []

    /// Transient banner shown when an action loses a race (permission-denied).
    var toastMessage: String?

    init(coordinator: AppCoordinator, myUid: String) {
        self.coordinator = coordinator
        self.myUid = myUid
    }

    // MARK: - Sections (each explicitly sorted per spec)

    /// Incoming pending challenges (opponent == me), most urgent (respondBy) first.
    var incoming: [DuelDTO] {
        let matches = duels.filter { $0.statusEnum == .pending && $0.opponentUid == myUid }
        return matches.sorted { (a: DuelDTO, b: DuelDTO) in a.respondBy < b.respondBy }
    }

    /// Outgoing pending challenges (challenger == me), most urgent (respondBy) first.
    var outgoing: [DuelDTO] {
        let matches = duels.filter { $0.statusEnum == .pending && $0.challengerUid == myUid }
        return matches.sorted { (a: DuelDTO, b: DuelDTO) in a.respondBy < b.respondBy }
    }

    /// Active duels, ending soonest (endAt) first.
    var active: [DuelDTO] {
        let matches = duels.filter { $0.statusEnum == .active }
        return matches.sorted { (a: DuelDTO, b: DuelDTO) in
            (a.endAt ?? Date.distantFuture) < (b.endAt ?? Date.distantFuture)
        }
    }

    /// Finished duels (declined / expired / resolved / forfeited), newest first.
    var finished: [DuelDTO] {
        let matches = duels.filter {
            switch $0.statusEnum {
            case .declined, .expired, .resolved, .forfeited: return true
            default: return false
            }
        }
        return matches.sorted { (a: DuelDTO, b: DuelDTO) in
            (a.createdAt ?? Date.distantPast) > (b.createdAt ?? Date.distantPast)
        }
    }

    /// True once loaded and there is nothing in any section.
    var isEmpty: Bool {
        incoming.isEmpty && outgoing.isEmpty && active.isEmpty && finished.isEmpty
    }

    // MARK: - Display helpers

    /// The counterparty's label relative to me (display name, else `@username`).
    func counterpartLabel(_ duel: DuelDTO) -> String { duel.opponentLabel(of: myUid) }

    /// Live score line ("You 30 — 15 Them"), rounded to whole points.
    func scoreLine(_ duel: DuelDTO) -> String {
        let mine = duel.myScore(myUid)
        let theirs = duel.theirScore(myUid)
        return "You \(Int(mine.rounded())) — \(Int(theirs.rounded())) \(counterpartLabel(duel))"
    }

    /// True when I lead the active duel (drives a subtle highlight).
    func iAmLeading(_ duel: DuelDTO) -> Bool {
        Int((duel.myScore(myUid) * 10).rounded()) > Int((duel.theirScore(myUid) * 10).rounded())
    }

    /// Outcome label for a finished duel, from MY perspective.
    func finishedLabel(_ duel: DuelDTO) -> String {
        switch duel.statusEnum {
        case .declined:  return "Declined"
        case .expired:   return "Expired"
        case .forfeited: return duel.forfeitedBy == myUid ? "Forfeit" : "Won"
        case .resolved:
            if duel.winnerUid == nil { return "Draw" }
            return duel.winnerUid == myUid ? "Won" : "Lost"
        default:         return duel.status.capitalized
        }
    }

    /// My signed RR delta for a resolved/forfeited duel ("+27" / "−18"), else nil.
    func rrDeltaText(_ duel: DuelDTO) -> String? {
        guard duel.statusEnum == .resolved || duel.statusEnum == .forfeited,
              let delta = duel.myRRDelta(myUid) else { return nil }
        return delta >= 0 ? "+\(delta) RR" : "\(delta) RR"
    }

    /// True while the 24h rematch window is open on a resolved/forfeited duel.
    func canRematch(_ duel: DuelDTO) -> Bool {
        guard duel.statusEnum == .resolved || duel.statusEnum == .forfeited,
              let resolvedAt = duel.resolvedAt else { return false }
        return Date() < resolvedAt.addingTimeInterval(DuelConstants.rematchWindow)
    }

    func isInFlight(_ duel: DuelDTO) -> Bool {
        guard let id = duel.id else { return false }
        return inFlightDuelIds.contains(id)
    }

    /// Accept-path cap gate (D2.6): accepting an incoming challenge makes it active, so it's
    /// blocked once my ACTIVES in that league hit the cap. Computed from the already-loaded
    /// (post-lifecycle) `duels`. Incoming/outgoing pendings never count here.
    func canAccept(_ duel: DuelDTO) -> Bool {
        let active = duels.filter { $0.statusEnum == .active && $0.league == duel.league }.count
        return active < DuelConstants.maxConcurrentDuels(league: duel.league)
    }

    // MARK: - D7: duel-history record (additive; pure derivation, testable without a coordinator)

    /// Win/Loss/Draw record + net RR over the finished duels. Classification follows the exact
    /// `finishedLabel` semantics — a forfeit BY ME counts as a loss; declined/expired are excluded
    /// from the record — and `netRR` sums `myRRDelta` over resolved+forfeited duels only.
    struct DuelHistoryStats: Equatable {
        var wins = 0
        var losses = 0
        var draws = 0
        var netRR = 0

        /// "W–L–D" — a display figure (D7).
        var recordText: String { "\(wins)–\(losses)–\(draws)" }
        /// Signed net RR ("+27 RR" / "-18 RR") — same sign convention as `rrDeltaText`.
        var netRRText: String { netRR >= 0 ? "+\(netRR) RR" : "\(netRR) RR" }
    }

    /// Pure derivation (no coordinator dependency → unit-testable in isolation). Mirrors
    /// `finishedLabel`'s win/loss/draw rules exactly (verified by a standalone matrix).
    static func historyStats(from finished: [DuelDTO], myUid: String) -> DuelHistoryStats {
        var s = DuelHistoryStats()
        for duel in finished {
            switch duel.statusEnum {
            case .resolved:
                if duel.winnerUid == nil { s.draws += 1 }
                else if duel.winnerUid == myUid { s.wins += 1 }
                else { s.losses += 1 }
            case .forfeited:
                if duel.forfeitedBy == myUid { s.losses += 1 } else { s.wins += 1 }
            default:
                break // declined / expired / unknown → excluded from the record
            }
            if duel.statusEnum == .resolved || duel.statusEnum == .forfeited {
                s.netRR += duel.myRRDelta(myUid) ?? 0
            }
        }
        return s
    }

    /// My record over the currently-loaded finished duels (D7).
    var historyStats: DuelHistoryStats { BattleViewModel.historyStats(from: finished, myUid: myUid) }

    // MARK: - D2: matchup preview (fills the featured slot when there is no active duel)

    /// A featured-slot matchup snapshot: me vs one random friend who has published stats, or a
    /// clearly-labelled SAMPLE when there are none. Held in VM state so a SwiftUI body
    /// re-evaluation never rerolls (the roll happens once per `loadMatchupPreview` run).
    struct MatchupPreview: Equatable {
        /// True for the no-friends SAMPLE card (fictional opponent, fixed values — never a real user).
        let isSample: Bool
        let opponentName: String
        let myInitial: String
        let theirInitial: String
        /// rr per side (drives the metal avatar tint). Mine always exists; theirs is nil when the
        /// friend hasn't published rr → neutral avatar + "—" on the RR row (nil ≠ zero).
        let myRR: Int?
        let theirRR: Int?
        let myDays: Int
        let theirDays: Int
        let myStreak: Int
        let theirStreak: Int
        /// The friend to pre-select in ChallengeSheet; nil for the SAMPLE card.
        let candidate: DuelOpponentCandidate?
    }

    private(set) var matchupPreview: MatchupPreview?

    /// Obviously-fictional opponents for the no-friends SAMPLE card. Never mistakable for a real user.
    private static let sampleOpponents = ["Sir Reginald", "Captain Nova", "Baroness Vex", "Coach Titan"]

    /// Loads the matchup preview (D2). Guest-safe via the coordinator's own guest gates (they return
    /// empty). Re-rolls the random friend once per call — each appear/refresh — and holds the result
    /// in `matchupPreview`; a SwiftUI body re-evaluation never rerolls.
    func loadMatchupPreview() async {
        // me + friends with weeklyGoalsMet.
        let entries = await coordinator.loadLeaderboard()
        // Candidate friends: published stats only (`hasData`), never me. Plain UI randomness.
        let published = entries.filter { !$0.isCurrentUser && $0.hasData }
        guard let pick = published.randomElement() else {
            matchupPreview = BattleViewModel.sampleMatchup()
            return
        }
        // Per-side level/streak/rr: the friend from published stats, me from my own progress.
        let friendStats = await coordinator.fetchFriendStats()
        let myProgress = try? await coordinator.getUserProgress()
        let theirStats = friendStats[pick.uid]
        let name = pick.displayName.isEmpty ? "@\(pick.username)" : pick.displayName
        matchupPreview = MatchupPreview(
            isSample: false,
            opponentName: name,
            myInitial: "Y",
            theirInitial: BattleViewModel.initialLetter(name),
            myRR: myProgress?.rr,
            theirRR: theirStats?.rr,
            myDays: entries.first(where: { $0.isCurrentUser })?.weeklyGoalsMet ?? 0,
            theirDays: pick.weeklyGoalsMet,
            myStreak: myProgress?.currentStreak ?? 0,
            theirStreak: theirStats?.currentStreak ?? 0,
            candidate: DuelOpponentCandidate(uid: pick.uid, username: pick.username,
                                             displayName: pick.displayName, source: .friend)
        )
    }

    /// Fixed-value SAMPLE card (no real friends). Fictional opponent; every figure is a constant.
    private static func sampleMatchup() -> MatchupPreview {
        let name = sampleOpponents.randomElement() ?? "Sir Reginald"
        return MatchupPreview(
            isSample: true, opponentName: name, myInitial: "Y", theirInitial: initialLetter(name),
            myRR: 500, theirRR: 620, myDays: 4, theirDays: 5, myStreak: 6, theirStreak: 9,
            candidate: nil
        )
    }

    /// First letter for an initials avatar, stripping a leading "@" from `@handle` labels.
    private static func initialLetter(_ label: String) -> String {
        let trimmed = label.hasPrefix("@") ? String(label.dropFirst()) : label
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        duels = await coordinator.loadMyDuels()
        isLoading = false
        didLoadOnce = true
        // Viewing the Battle list clears the pulse + "since you looked" deltas. The recap
        // sheet (DuelUIState.pendingResolutions) supersedes the old claim toast (D1c/D4).
        await coordinator.markDuelsSeen(duels, isFullList: true)
        // R4c §1: the matchup preview fills the featured slot only when there is no active duel
        // (the active-duel featured card wins). Re-rolls once per load (each appear / refresh).
        if active.isEmpty { await loadMatchupPreview() }
        else { matchupPreview = nil }
    }

    // MARK: - Actions

    func accept(_ duel: DuelDTO) async {
        await mutate(duel) { [coordinator] in try await coordinator.acceptChallenge(duel) }
    }

    func decline(_ duel: DuelDTO) async {
        await mutate(duel) { [coordinator] in try await coordinator.declineChallenge(duel) }
    }

    func cancel(_ duel: DuelDTO) async {
        await mutate(duel) { [coordinator] in try await coordinator.cancelChallenge(duel) }
    }

    /// Shared accept/decline/cancel wrapper: per-row in-flight flag, then reload on
    /// success; on failure (usually a lost race → permission-denied) surface a toast
    /// and still reload so the row snaps to the server truth.
    private func mutate(_ duel: DuelDTO, _ op: @escaping () async throws -> Void) async {
        guard let id = duel.id, !inFlightDuelIds.contains(id) else { return }
        inFlightDuelIds.insert(id)
        defer { inFlightDuelIds.remove(id) }
        do {
            try await op()
        } catch {
            // D2.6: an at-capacity accept (stale-list race past the UI gate) shows the capacity
            // message; every other failure keeps the generic lost-race message.
            if let duelError = error as? DuelError, case .leagueAtCapacity = duelError {
                toastMessage = duelError.errorDescription
            } else {
                toastMessage = "Challenge no longer available"
            }
        }
        await load()
    }

    // MARK: - D1b actions

    func forfeit(_ duel: DuelDTO) async {
        guard let id = duel.id, !inFlightDuelIds.contains(id) else { return }
        inFlightDuelIds.insert(id)
        defer { inFlightDuelIds.remove(id) }
        do {
            try await coordinator.forfeitDuel(duel)
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't forfeit."
        }
        await load() // the forfeit's RR claim surfaces its own outcome toast
    }

    func rematch(_ duel: DuelDTO) async {
        guard let id = duel.id, !inFlightDuelIds.contains(id) else { return }
        inFlightDuelIds.insert(id)
        defer { inFlightDuelIds.remove(id) }
        do {
            try await coordinator.rematch(duel)
            toastMessage = "Rematch sent"
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't send the rematch."
        }
        await load()
    }
}
