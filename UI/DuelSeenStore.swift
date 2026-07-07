//
//  DuelSeenStore.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import Foundation

/// A per-duel "last seen" snapshot from MY perspective (D1c).
struct DuelSeenSnapshot: Codable, Equatable {
    var theirScore: Double   // opponent's total, from my perspective, at last seen
    var status: String       // DuelStatus raw value at last seen
}

/// A thin value-type helper over UserDefaults, keyed per uid. Not a manager/service — it
/// holds no state beyond UserDefaults and touches no other layer. Per-device throwaway UI
/// state (never SwiftData/Firestore); per-device divergence is acceptable. Powers the Battle
/// badge pulse and the Home strip's "since you looked" delta chip.
struct DuelSeenStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func storageKey(_ uid: String) -> String { "duelSeenSnapshots_\(uid)" }

    private func roundedTenths(_ v: Double) -> Int { Int((v * 10).rounded()) }

    private func snapshot(of duel: DuelDTO, myUid: String) -> DuelSeenSnapshot {
        DuelSeenSnapshot(theirScore: duel.theirScore(myUid), status: duel.status)
    }

    /// Stored snapshots keyed by duelId. Decode failure ⇒ empty store (never throws/crashes).
    func snapshots(uid: String) -> [String: DuelSeenSnapshot] {
        guard let data = defaults.data(forKey: storageKey(uid)),
              let map = try? JSONDecoder().decode([String: DuelSeenSnapshot].self, from: data) else {
            return [:]
        }
        return map
    }

    private func save(_ map: [String: DuelSeenSnapshot], uid: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey(uid))
    }

    /// Replace the store with exactly these duels' snapshots (prunes stale ids). Callers pass
    /// FULL fetched lists. NO-OP when empty: `loadMyDuels` swallows fetch failures into `[]`,
    /// and an empty replace would wipe the store and make everything pulse on the next good
    /// load. A genuinely zero-duel user loses nothing — stale snapshots are harmless.
    func markSeen(_ duels: [DuelDTO], myUid: String) {
        guard !duels.isEmpty else { return }
        var map: [String: DuelSeenSnapshot] = [:]
        for duel in duels {
            guard let id = duel.id else { continue }
            map[id] = snapshot(of: duel, myUid: myUid)
        }
        save(map, uid: myUid)
    }

    /// Single-duel upsert, no pruning — used by the Arena.
    func markSeen(_ duel: DuelDTO, myUid: String) {
        guard let id = duel.id else { return }
        var map = snapshots(uid: myUid)
        map[id] = snapshot(of: duel, myUid: myUid)
        save(map, uid: myUid)
    }

    /// True if ANY duel (non-nil id) has an unseen change worth pulsing the badge for:
    /// a new incoming challenge, an active duel with no snapshot or moved opponent score, or
    /// a resolved/forfeited duel with no snapshot or a changed status. Declined/expired and
    /// outgoing pendings never count.
    func hasUnseenChanges(in duels: [DuelDTO], myUid: String) -> Bool {
        let seen = snapshots(uid: myUid)
        for duel in duels {
            guard let id = duel.id else { continue }
            let snap = seen[id]
            switch duel.statusEnum {
            case .pending:
                if duel.isPendingOnMe(myUid) && snap == nil { return true }
            case .active:
                if snap == nil { return true }
                if roundedTenths(duel.theirScore(myUid)) != roundedTenths(snap!.theirScore) { return true }
            case .resolved, .forfeited:
                if snap == nil || snap!.status != duel.status { return true }
            default:
                break
            }
        }
        return false
    }

    /// For an ACTIVE duel: opponent's movement since last seen (rounded-int different), else nil.
    func deltaSinceSeen(for duel: DuelDTO, myUid: String) -> Double? {
        guard duel.statusEnum == .active, let id = duel.id,
              let snap = snapshots(uid: myUid)[id] else { return nil }
        let current = duel.theirScore(myUid)
        guard roundedTenths(current) != roundedTenths(snap.theirScore) else { return nil }
        return current - snap.theirScore
    }
}
