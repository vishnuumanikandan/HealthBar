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

/// ViewModel for `BattleStandingsBlock` (the retired `GlobalLeaderboardView` still renders it too).
///
/// Fetch-on-view + pull-to-refresh; NO listeners (the guild-chat listener remains the app's only
/// one). LB-PAGE-1: the Battle board is server-cursor PAGINATED (10 rows/page). Each board caches
/// its fetched pages (`BoardPages`) for the view's lifetime — prev/next between cached pages is
/// instant, only an uncached forward page hits the network; pull-to-refresh clears every board's
/// pages. Metric/league switches reset to page 1 of the new board (cache-served when warm). Rows
/// are world-readable projections — self-reported, eventually-consistent snapshots.
@Observable
@MainActor
final class GlobalLeaderboardViewModel {

    private let coordinator: AppCoordinator
    /// My uid — the self-detection key for the "You" highlight.
    private let myUid: String

    /// Bound by the pickers; a change triggers `boardChanged()`.
    var metric: LeaderboardMetric = .rr
    var league: Int = 1

    /// Always the currently DISPLAYED page's rows.
    private(set) var rows: [GlobalLeaderboardDTO] = []
    private(set) var myEntry: GlobalLeaderboardDTO? = nil
    /// My server-truth standing on the CURRENT board (count aggregation), reloaded on board switch.
    private(set) var myBoardPosition: Int? = nil
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 0-based index of the displayed page within the current board's cached pages.
    private(set) var pageIndex: Int = 0
    /// True only while an uncached forward page is being fetched (drives the tapped `›` spinner
    /// and gates re-entrant pager taps).
    private(set) var isPageLoading = false
    var loadError: String? = nil

    /// One fetched page: its rows plus the cursor that fetches the NEXT page after it. The cursor
    /// travels WITH the page it was derived from — no parallel arrays, nothing to misalign.
    private struct Page {
        let rows: [GlobalLeaderboardDTO]
        let nextCursor: LeaderboardCursor?
    }

    /// A board's accumulated pages + whether the tail has been reached. `exhausted` is keyed on the
    /// RAW fetched count (`fetchedCount < leaderboardPageLength`), not the displayed count.
    ///
    /// LB-PAGE-1 LEDGER (board mutates between page fetches): the projections are self-reported and
    /// eventually consistent, so between two page fetches a player who moved may appear on two
    /// cached pages or be skipped at a page boundary. Accepted — the board is a live snapshot, not a
    /// transactional read.
    private struct BoardPages {
        var pages: [Page]
        var exhausted: Bool
    }

    /// Per-board page cache, keyed by `orderField`. Cleared on `refresh()`.
    private var cache: [String: BoardPages] = [:]

    /// M8: monotonic token bumped on every load entry point (first-page load, page fetch, prev,
    /// board switch, refresh). Only the latest invocation may touch rendered state — a rapid board
    /// switch (or tap) mid page-fetch invalidates the older in-flight fetch. A counter (not a field
    /// comparison) is required: a user can switch away and back to the SAME board while an
    /// intermediate fetch is still pending.
    private var loadGeneration: Int = 0

    init(coordinator: AppCoordinator, myUid: String) {
        self.coordinator = coordinator
        self.myUid = myUid
    }

    // MARK: - Derived

    var currentField: String { LeaderboardMetric.orderField(metric: metric, league: league) }
    /// The league sub-picker is hidden on the RR board (RR is one number, not per-league).
    var showsLeaguePicker: Bool { metric != .rr }

    /// `‹` is live only past page 1. (Matches the TDD'd `canGoPrev`.)
    var canGoPrev: Bool { pageIndex > 0 }

    /// `›` is live when the board isn't exhausted OR a cached page exists beyond the current one
    /// (e.g. after paging back). (Matches the TDD'd `canGoNext`.)
    var canGoNext: Bool {
        let board = cache[currentField]
        let count = board?.pages.count ?? 0
        let exhausted = board?.exhausted ?? false
        return !exhausted || pageIndex + 1 < count
    }

    /// The 1-based rank of the FIRST row on the currently displayed page.
    ///
    /// LB-PAGE-1 REQUIRED LEDGER: numbering is cumulative over the DISPLAYED row counts of all
    /// earlier cached pages, so it depends on which earlier pages were fetched and how many rows the
    /// UGC-1b blocked filter removed from them. It can therefore DISAGREE with the server-truth `#N`
    /// aggregation shown in the footer whenever blocked players exist — the accepted extension of
    /// the existing rrPosition skew ledger entry. (Matches the TDD'd `pageStartPosition`.)
    var currentPageStartPosition: Int {
        guard let board = cache[currentField] else { return 1 }
        return board.pages.prefix(pageIndex).reduce(0) { $0 + $1.rows.count } + 1
    }

    // MARK: - Loading

    func loadInitial() async {
        guard !hasLoaded else { return }
        await loadFirstPage(force: false)
        await loadMyRow()
    }

    /// Metric/league toggle changed — reset to page 1 of the new board (cache-served when warm) and
    /// reload my per-board standing.
    func boardChanged() async {
        await loadFirstPage(force: false)
        await loadMyRow()
    }

    /// Pull-to-refresh: drop every board's pages and refetch page 1 of the current board + my row.
    func refresh() async {
        cache.removeAll()
        await loadFirstPage(force: true)
        await loadMyRow()
    }

    /// Loads (or cache-serves) page 1 of the current board and resets pager state to it.
    private func loadFirstPage(force: Bool) async {
        // Bump the generation on EVERY invocation (before the cache check) so even a synchronous
        // cache hit invalidates any older in-flight fetch, and reset pager state to page 1.
        loadGeneration += 1
        let generation = loadGeneration
        let field = currentField
        pageIndex = 0
        isPageLoading = false
        // Serve the cached page 1 when warm (unless forced).
        if !force, let board = cache[field], let first = board.pages.first {
            rows = first.rows
            isLoading = false
            hasLoaded = true
            loadError = nil
            return
        }
        isLoading = true
        let result = await coordinator.fetchGlobalLeaderboardPage(metric: metric, league: league, after: nil)
        // Cache under the FETCHED field's key unconditionally — valid for that key even if the user
        // has since switched away. Exhaustion is keyed on the RAW fetched count.
        cache[field] = BoardPages(
            pages: [Page(rows: result.rows, nextCursor: result.nextCursor)],
            exhausted: result.fetchedCount < DuelConstants.leaderboardPageLength
        )
        // Only the latest invocation may touch rendered state; a stale completion (a board switch
        // that landed while this fetch was in flight) must never overwrite the newer board.
        guard generation == loadGeneration else { return }
        rows = result.rows
        pageIndex = 0
        isLoading = false
        hasLoaded = true
        // An empty result is a genuine empty board (day one) — never an error.
        loadError = nil
    }

    /// Advance one page: serve from cache when the next page is already cached, else fetch it with
    /// the CURRENT page's cursor. A fetch of fewer than a full page marks the board exhausted; a
    /// fetch of zero raw rows stays put (renders no empty page). The current rows persist during the
    /// fetch (no blank flash).
    func nextPage() async {
        guard canGoNext, !isPageLoading else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let field = currentField
        guard let board = cache[field] else { return }
        // Cached forward page — instant.
        if pageIndex + 1 < board.pages.count {
            pageIndex += 1
            rows = board.pages[pageIndex].rows
            return
        }
        // Uncached — fetch with the current page's cursor (nil cursor ⇒ nothing more to fetch).
        guard let cursor = board.pages[pageIndex].nextCursor else {
            cache[field]?.exhausted = true
            return
        }
        isPageLoading = true
        let result = await coordinator.fetchGlobalLeaderboardPage(metric: metric, league: league, after: cursor)
        // A board switch (or refresh) landed mid-fetch — discard. `isPageLoading` was already reset
        // by the newer `loadFirstPage`, so no stuck spinner.
        guard generation == loadGeneration else { return }
        isPageLoading = false
        // Exhaustion is keyed on the RAW (pre-filter) fetched count — a blocked-filtered page under
        // a full page is NOT exhaustion.
        guard result.fetchedCount > 0 else {
            cache[field]?.exhausted = true
            return
        }
        cache[field]?.pages.append(Page(rows: result.rows, nextCursor: result.nextCursor))
        if result.fetchedCount < DuelConstants.leaderboardPageLength {
            cache[field]?.exhausted = true
        }
        pageIndex += 1
        rows = result.rows
    }

    /// Step back one page — always cache-served. Bumps the generation to invalidate any in-flight
    /// forward fetch (belt-and-suspenders; `isPageLoading` also gates re-entrant taps).
    func prevPage() async {
        guard canGoPrev, !isPageLoading else { return }
        loadGeneration += 1
        pageIndex -= 1
        if let board = cache[currentField], pageIndex < board.pages.count {
            rows = board.pages[pageIndex].rows
        }
    }

    private func loadMyRow() async {
        let generation = loadGeneration
        let (entry, position) = await coordinator.fetchMyLeaderboardRow(metric: metric, league: league)
        // A board switch landed mid-fetch — its own loadMyRow owns the position now.
        guard generation == loadGeneration else { return }
        myEntry = entry
        myBoardPosition = position
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
