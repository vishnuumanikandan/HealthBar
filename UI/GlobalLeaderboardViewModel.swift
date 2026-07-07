//
//  GlobalLeaderboardViewModel.swift
//  HealthBar
//
//  Created by Claude on 7/6/26.
//

import Foundation

/// The metric a global-leaderboard board ranks by (D3). Seven boards total: RR is global
/// (one board), Wins/Streak are per-league (three each).
enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case rr = "RR"
    case wins = "Wins"
    case streak = "Streak"

    var id: String { rawValue }

    /// The Firestore `orderBy` field for a board. RR ignores league; Wins/Streak append the
    /// league number (matches the `GlobalLeaderboardDTO` field names).
    static func orderField(metric: LeaderboardMetric, league: Int) -> String {
        switch metric {
        case .rr: return "rr"
        case .wins: return "wins\(league)"
        case .streak: return "streak\(league)"
        }
    }
}

/// ViewModel for `GlobalLeaderboardView` (D3).
///
/// Fetch-on-view + pull-to-refresh; NO listeners (the guild-chat listener remains the app's
/// only one). Metric/league switches REFETCH the new `orderBy` field (unlike the guild board's
/// in-memory re-sort), then cache each fetched board in memory for the view's lifetime;
/// pull-to-refresh clears the cache. Rows are world-readable projections — self-reported,
/// eventually-consistent snapshots.
@Observable
@MainActor
final class GlobalLeaderboardViewModel {

    private let coordinator: AppCoordinator
    /// My uid — the self-detection key for the "You" highlight.
    private let myUid: String

    /// Bound by the pickers; a change triggers `boardChanged()`.
    var metric: LeaderboardMetric = .rr
    var league: Int = 1

    private(set) var rows: [GlobalLeaderboardDTO] = []
    private(set) var myEntry: GlobalLeaderboardDTO? = nil
    private(set) var myRRPosition: Int? = nil
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var loadError: String? = nil

    /// Cache keyed by `orderField` — each board fetched once per view lifetime; cleared on refresh.
    private var cache: [String: [GlobalLeaderboardDTO]] = [:]

    init(coordinator: AppCoordinator, myUid: String) {
        self.coordinator = coordinator
        self.myUid = myUid
    }

    // MARK: - Derived

    var currentField: String { LeaderboardMetric.orderField(metric: metric, league: league) }
    /// The league sub-picker is hidden on the RR board (RR is one number, not per-league).
    var showsLeaguePicker: Bool { metric != .rr }

    // MARK: - Loading

    func loadInitial() async {
        guard !hasLoaded else { return }
        await loadBoard(force: false)
        await loadMyRow()
    }

    /// Metric/league toggle changed — serve from cache when present, else fetch.
    func boardChanged() async {
        await loadBoard(force: false)
    }

    /// Pull-to-refresh: drop the cache and refetch the current board + my row.
    func refresh() async {
        cache.removeAll()
        await loadBoard(force: true)
        await loadMyRow()
    }

    private func loadBoard(force: Bool) async {
        let field = currentField
        if !force, let cached = cache[field] {
            rows = cached
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let result = await coordinator.fetchGlobalLeaderboard(metric: metric, league: league)
        rows = result
        cache[field] = result
        // An empty result is a genuine empty board (day one) — never an error (D6 / §6).
        loadError = nil
    }

    private func loadMyRow() async {
        let (entry, position) = await coordinator.fetchMyLeaderboardRow()
        myEntry = entry
        myRRPosition = position
    }

    // MARK: - Row helpers

    func isMe(_ row: GlobalLeaderboardDTO) -> Bool { row.id == myUid }

    /// The emphasized value for a row on the current board. RR → tier string (via the shared
    /// `Rank` helper); Wins/Streak → the count.
    func valueText(_ row: GlobalLeaderboardDTO) -> String {
        switch metric {
        case .rr: return Rank.rankTier(from: row.rr).displayName
        case .wins: return "\(row.wins(league: league))"
        case .streak: return "\(row.streak(league: league))"
        }
    }

    /// The caption under the value.
    func captionText(_ row: GlobalLeaderboardDTO) -> String {
        switch metric {
        case .rr: return "\(row.rr) RR"
        case .wins: return "wins"
        case .streak: return "win streak"
        }
    }
}
