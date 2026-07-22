//
//  ProfileViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Profile/Settings screen
///
/// Displays user stats (XP, level, rank, streaks) and profile settings.
/// Interacts with AppCoordinator for all business logic.
@Observable
final class ProfileViewModel {

    // MARK: - Properties

    /// The app coordinator (handles all business logic)
    private let coordinator: AppCoordinator

    /// Auth service — read-only, used to suppress false errors for new accounts
    /// and to read guest state for display name fallback logic.
    private var authService: any AuthService

    // MARK: - UI State

    /// Current user progress data
    var userProgress: UserProgress?

    /// Current daily goal data
    var currentGoal: DailyGoal?

    /// The user's completed health profile (nil if not yet set up or not found).
    var existingProfile: UserProfile?

    /// D3a preset avatar (icon id + color id), loaded from the profile record; nil ⇒
    /// initials fallback in the header. Updated directly on a successful in-place picker
    /// save (D8 — no full-page reload).
    var avatarIcon: String?
    var avatarColor: String?

    /// Loading state for UI
    var isLoading = false

    /// Error message to display (nil if no error)
    var errorMessage: String?

    // MARK: - D2 Profile Section State
    //
    // Populated in loadUserData()/refresh(); each degrades INDEPENDENTLY (D10) — a failure in
    // one of these sections never sets `errorMessage` and never blocks the page.

    /// "Meals Logged" tile (D5). `nil` renders "—" (load failed).
    var mealsLogged: Int?

    /// The user's guild for the Guild row (D6). `nil` hides the whole section — guest, no
    /// guild, or fetch failure (fail-to-hidden). Guest-gated BEFORE the fetch in loadUserData().
    var loadedGuild: GuildDTO?

    /// Goal Calendar state (D7). `calendarDays == nil` hides the section (load failed);
    /// otherwise the view maps it 1:1 using `calendarLeadingBlanks` for the grid offset.
    /// Regenerated on every load/refresh, never mutated in place.
    var calendarDays: [DayCellState]?
    var calendarLeadingBlanks: Int = 0
    var calendarDaysHit: Int = 0
    var calendarMonthTitle: String = ""
    var weekdayInitials: [String] = []

    // MARK: - Computed Properties for UI

    /// Current level based on total XP
    var currentLevel: Int {
        guard let progress = userProgress else { return 1 }
        // XP formula: 100 XP per level
        return (progress.totalXP / 100) + 1
    }

    /// Rank Journey card data (D3), derived purely from `userProgress.rr` via Rank.swift's
    /// existing API. `nil` before load — the journey card region participates in the page's
    /// loading state; there is no invented default RR and no force-unwrap. (D2 retired the
    /// header rank pill along with `currentRank` / `currentRankDisplay`; the journey card is
    /// rank's single home.)
    var rankJourney: RankJourney? { userProgress.map { RankJourney(rr: $0.rr) } }

    /// Duel record (D5), the SAME local source `publishMyStats` publishes for the wins
    /// leaderboard (`UserProgress.duelWins` / `.duelLosses` → UserProgressDTO → public/stats).
    /// Both counters exist locally, so the cell renders W–L. The Duel cell is guest-hidden at
    /// the view layer (D9); these stay a plain read of the already-loaded progress.
    var duelWins: Int? { userProgress?.duelWins }
    var duelLosses: Int? { userProgress?.duelLosses }

    /// Badge counter for the section header (D2). Own page counts unlocked records from
    /// `badgeProgressList` — NOT `publishedBadgeCount` (that is the friend-view concept).
    var earnedBadgeCount: Int { badgeProgressList.filter { $0.isUnlocked }.count }
    var totalBadgeCount: Int { BadgeDefinition.all.count }

    /// Formatted total XP (e.g., "1,250 XP")
    var totalXPText: String {
        guard let progress = userProgress else { return "0 XP" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: progress.totalXP)) ?? "0") XP"
    }

    /// Display name with fallback chain: UserProfile.displayName → Firebase Auth → "User"
    var displayName: String {
        if let name = existingProfile?.displayName, !name.isEmpty { return name }
        if let name = FirebaseAuthService.shared.currentUserDisplayName, !name.isEmpty { return name }
        return "User"
    }

    /// First character of displayName (uppercased), fallback "U"
    var userInitials: String {
        String(displayName.prefix(1)).uppercased()
    }

    // MARK: - XP Progress

    /// XP earned within the current level (0–99)
    var xpWithinLevel: Int {
        userProgress.map { $0.totalXP % 100 } ?? 0
    }

    /// XP remaining to reach the next level
    var xpToNextLevel: Int {
        userProgress.map { 100 - ($0.totalXP % 100) } ?? 100
    }

    /// Progress ratio within the current level (0.0–1.0)
    var levelProgress: Double {
        userProgress.map { Double($0.totalXP % 100) / 100.0 } ?? 0
    }

    /// Next level number
    var nextLevel: Int { currentLevel + 1 }

    // MARK: - Badge Progress

    /// All badge progress records for the current user.
    var badgeProgressList: [BadgeProgress] = []

    /// The user's unique @handle (nil if not yet claimed or guest).
    var username: String? = nil

    // MARK: - Initialization

    /// Initializes the ViewModel with an AppCoordinator and auth service.
    /// - Parameters:
    ///   - coordinator: The app coordinator for business logic.
    ///   - authService: Used to read isNewUser (suppresses false errors on brand-new accounts)
    ///                  and isGuest (for display name fallback).
    init(coordinator: AppCoordinator, authService: any AuthService) {
        self.coordinator = coordinator
        self.authService = authService
    }

    // MARK: - Public Methods

    /// Loads user progress and goal data
    ///
    /// Call this when the view appears or needs to refresh.
    func loadUserData() async {
        isLoading = true
        errorMessage = nil

        do {
            // S1: bootstrap default data BEFORE reading — mirrors what Home does via
            // getTodaysSummary(). Idempotent: no-op for returning users / when unauthenticated,
            // creates UserProgress + today's DailyGoal for new accounts, guest-safe internally.
            // Without it, a fresh account whose Profile loads before Home's bootstrap hits
            // userProgressNotFound, and the one-shot isNewUser suppression may already be consumed
            // (SMOKE-1 #3). A setupApp() throw is handled by the same catch below.
            try await coordinator.setupApp()
            userProgress = try await coordinator.getUserProgress()
            currentGoal = try await coordinator.getCurrentGoal()
            existingProfile = try await coordinator.getUserProfile()
            avatarIcon = existingProfile?.avatarIcon
            avatarColor = existingProfile?.avatarColor
            badgeProgressList = (try? await coordinator.getAllBadgeProgress()) ?? []
            username = await coordinator.currentUsername()

            // D2 sections — loaded in the same async flow but each degrades independently (D10):
            // a failure here degrades ONLY that section (meals → "—", guild → hidden,
            // calendar → hidden) and never touches errorMessage or the page.

            // Meals Logged (F1a): count query; nil on failure → "—".
            mealsLogged = try? await coordinator.countAllFoodEntries()

            // Guild row (D6/D9): guest guard is the FIRST executable line — guests never reach
            // the fetch. Any other outcome (no guild / fetch failure) also yields nil → hidden.
            if authService.isGuest {
                loadedGuild = nil
            } else {
                loadedGuild = await coordinator.myGuild()
            }

            // Goal Calendar (D7): local SwiftData; a throw hides the section (D10). Rebuilt from
            // scratch each load (never mutated in place); guests keep the calendar (local data).
            if let metDays = try? await coordinator.goalMetDaysForCurrentMonth() {
                rebuildCalendar(metDays: metDays)
            } else {
                calendarDays = nil
            }

            // First successful load for a new account — clear the new-user flag.
            if authService.isNewUser {
                authService.isNewUser = false
            }
        } catch {
            if authService.isNewUser {
                // Brand-new account: no data exists yet. Suppress the error and show
                // a clean empty state. This prevents false "unable to load" messages
                // immediately after account creation.
                errorMessage = nil
                authService.isNewUser = false
            } else {
                errorMessage = "Failed to load profile data: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    /// Refreshes the data (for pull-to-refresh)
    func refresh() async {
        await loadUserData()
    }

    /// D3a: persists the picked avatar via the coordinator and, on success, updates the VM's
    /// avatar state directly — no full-page reload (D8). Returns success for the picker's
    /// dismiss/retry contract. Works for guests (local-only).
    func saveAvatar(iconId: String, colorId: String) async -> Bool {
        let ok = await coordinator.updateAvatar(iconId: iconId, colorId: colorId)
        if ok {
            avatarIcon = iconId
            avatarColor = colorId
        }
        return ok
    }

    // MARK: - Goal Calendar assembly (D7)

    /// Rebuilds the Goal Calendar view state for the CURRENT month from its met-day set.
    /// All grid math runs here (off the render path) and is stored as a prebuilt array the
    /// view maps 1:1 — zero per-cell computation in the view. The month is derived from
    /// "today" at each call, so a refresh after midnight on the 1st renders the new month.
    /// Future days are never "met"; a past/today day absent from `metDays` is unmet; leading
    /// blanks align the 1st to `Calendar.current.firstWeekday` (never hardcode Sunday).
    private func rebuildCalendar(metDays: Set<Date>) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let monthInterval = calendar.dateInterval(of: .month, for: todayStart),
              let dayRange = calendar.range(of: .day, in: .month, for: todayStart) else {
            calendarDays = nil
            return
        }
        let firstOfMonth = monthInterval.start   // already a startOfDay
        let weekday = calendar.component(.weekday, from: firstOfMonth)      // 1…7
        calendarLeadingBlanks = ((weekday - calendar.firstWeekday) + 7) % 7

        var days: [DayCellState] = []
        var hit = 0
        for dayNum in dayRange {                 // 1…daysInMonth
            guard let dayStart = calendar.date(byAdding: .day, value: dayNum - 1, to: firstOfMonth) else { continue }
            let isToday = dayStart == todayStart
            let state: ProfileDayState
            if dayStart > todayStart {
                state = .future
            } else if metDays.contains(dayStart) {
                state = .met
                hit += 1
            } else {
                state = .unmet
            }
            days.append(DayCellState(dayNumber: dayNum, state: state, isToday: isToday))
        }
        calendarDays = days
        calendarDaysHit = hit

        // Header: month + year from today (D7). Weekday initials ordered from firstWeekday.
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale.current
        fmt.dateFormat = "LLLL yyyy"
        calendarMonthTitle = fmt.string(from: todayStart)

        let symbols = calendar.veryShortStandaloneWeekdaySymbols   // index 0 = Sunday
        let start = calendar.firstWeekday - 1                        // 0-based
        weekdayInitials = (0..<7).map { symbols[(start + $0) % 7] }
    }
}

// MARK: - Rank Journey (D3)

/// Rank Journey card view-data, a pure function of `rr` through Rank.swift's existing API
/// (no new math constants). Verified by a standalone TDD harness against Rank.swift.
struct RankJourney {
    let rr: Int

    var rank: Rank { Rank.getRank(from: rr) }
    private var tierInfo: RankTier { Rank.rankTier(from: rr) }
    var tier: Int { tierInfo.tier }

    /// Card title / caption-left: the current tier's name, e.g. "Copper 2".
    var tierTitle: String { tierInfo.displayName }

    /// Peak of the ladder: top rank, top tier — the bar + caption are replaced by one line.
    var isPeak: Bool { rank == .zenith && tier == Rank.tiersPerRank }

    /// Sub-line: "<rr> RR · Rank <i> of <count>" — `i` is the 1-based position of the current
    /// rank in `Rank.allCases`, `<count>` is `Rank.allCases.count` (no hardcoded 9).
    var rankIndex: Int { (Rank.allCases.firstIndex(of: rank) ?? 0) + 1 }
    var rankCount: Int { Rank.allCases.count }
    var subline: String { "\(rr) RR · Rank \(rankIndex) of \(rankCount)" }

    /// RR at which the current tier begins: `rank.rrThreshold + (tier − 1) * Rank.rrPerTier`.
    private var currentTierFloor: Int { rank.rrThreshold + (tier - 1) * Rank.rrPerTier }
    private var nextTierFloor: Int { currentTierFloor + Rank.rrPerTier }

    /// Progress through the current tier: `(rr − currentTierFloor) / Rank.rrPerTier`, clamped 0…1.
    var fill: Double {
        min(1, max(0, Double(rr - currentTierFloor) / Double(Rank.rrPerTier)))
    }

    /// RR still needed to reach the next tier.
    var remaining: Int { max(0, nextTierFloor - rr) }

    /// The next rank in ladder order (`Rank.allCases`), or nil at the top.
    private var nextRank: Rank? {
        let all = Rank.allCases
        guard let idx = all.firstIndex(of: rank), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    /// ASCENDING next-tier label: tier+1 in the same rank, or the NEXT rank's tier 1 when at
    /// tier 3 (Copper 2 → Copper 3 → Iron 1). Fixes the mockup's descending "Copper 1" error.
    var nextTierLabel: String {
        if tier < Rank.tiersPerRank {
            return "\(rank.displayName) \(tier + 1)"
        } else if let nr = nextRank {
            return "\(nr.displayName) 1"
        } else {
            return tierTitle   // zenith tier 3 = peak; caption is replaced upstream.
        }
    }

    /// Caption-right: "<remaining> RR to <next>".
    var captionRight: String { "\(remaining) RR to \(nextTierLabel)" }
}

// MARK: - Goal Calendar cell (D7)

/// A single day's paint state in the Goal Calendar grid.
enum ProfileDayState { case met, unmet, future }

/// Fixed shape for a Goal Calendar day cell (D7). The view maps `calendarDays` 1:1 to these.
struct DayCellState {
    let dayNumber: Int
    let state: ProfileDayState
    let isToday: Bool
}
