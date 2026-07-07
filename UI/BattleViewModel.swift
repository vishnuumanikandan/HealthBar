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

    // MARK: - Load

    func load() async {
        isLoading = true
        duels = await coordinator.loadMyDuels()
        isLoading = false
        didLoadOnce = true
        // Viewing the Battle list clears the pulse + "since you looked" deltas. The recap
        // sheet (DuelUIState.pendingResolutions) supersedes the old claim toast (D1c/D4).
        await coordinator.markDuelsSeen(duels, isFullList: true)
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
