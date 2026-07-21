//
//  ChallengeSheet.swift
//  HealthBar
//
//  Created by Claude on 7/3/26.
//

import SwiftUI

/// The challenge lobby (C1): pick an opponent and a league (1 / 3 / 5-day), then send.
///
/// Opponents come from three surfaces — my friends (RIVALS) and guild-mates (GUILD) as
/// horizontal card carousels, plus everyone else via the RR-proximity "NEARBY RANKS"
/// stream (paginated around my RR from the world-readable `leaderboard/{uid}` projection)
/// and an exact `@handle` search. Send is disabled until BOTH an opponent and a league are
/// chosen — validated by construction, not after tap. A duplicate pending challenge (or an
/// at-capacity league) surfaces inline. Success toasts, dismisses, and refreshes the Battle
/// list via `onSent`.
///
/// The sheet owns its pagination + search state directly in `@State` (no ViewModel); the
/// DataManager exposes a pure paged fetch (`fetchNearbyRanked`) and the merge/ordering logic.
struct ChallengeSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let coordinator: AppCoordinator
    /// D2: a friend to pre-select on open (from the matchup preview's Challenge CTA). Additive.
    private let preselected: DuelOpponentCandidate?
    private let onSent: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Friends (RIVALS) + guild-mates (GUILD) — each lives in its own section.
    @State private var candidates: [DuelOpponentCandidate] = []
    @State private var loadingPeople = true
    /// True only on a genuine load failure (guest / no identity) — NOT an authentically empty
    /// world, which shows the search field + the empty-stream caption instead.
    @State private var loadFailed = false

    // NEARBY RANKS stream (C1). Two cursors on plain `rr` — one paging up from my RR, one down.
    @State private var myRR = 0
    @State private var nearbyRows: [DuelOpponentCandidate] = []
    @State private var upCursor: (rr: Int, uid: String)?
    @State private var downCursor: (rr: Int, uid: String)?
    @State private var isExhausted = false
    @State private var loadingMore = false
    @State private var loadMoreTask: Task<Void, Never>?

    // Exact @handle search (C1) — replaces the old contains-filter.
    @State private var searchText = ""
    @State private var searchResult: DuelOpponentCandidate?
    @State private var searchPhase: SearchPhase = .idle
    @State private var searchTask: Task<Void, Never>?

    // Selection + send.
    @State private var selectedOpponent: DuelOpponentCandidate?
    /// nil until the user picks — drives the "must choose a league" gate.
    @State private var selectedLeague: Int?
    /// Per-league starting-path slot usage (D2.6), zero-filled for every league on load.
    @State private var usageByLeague: [Int: Int] = [:]
    @State private var isSending = false
    @State private var inlineError: String?

    /// NAV-1b: candidate whose read-only profile sheet is open (long-press "View
    /// Profile"). Independent of `selectedOpponent` — viewing never changes selection.
    @State private var profilePerson: DuelOpponentCandidate?

    private enum SearchPhase: Equatable { case idle, searching, result, noMatch }

    init(coordinator: AppCoordinator, preselected: DuelOpponentCandidate? = nil, onSent: @escaping () -> Void = {}) {
        self.coordinator = coordinator
        self.preselected = preselected
        self.onSent = onSent
    }

    private var friends: [DuelOpponentCandidate] { candidates.filter { $0.source == .friend } }
    private var guildMates: [DuelOpponentCandidate] { candidates.filter { $0.source == .guild } }

    /// Validate by construction: both selections required, not mid-send.
    private var canSend: Bool { selectedOpponent != nil && selectedLeague != nil && !isSending }

    /// Friends + guild-mates are excluded from the stream (they have their own sections); the
    /// fetch also drops my own uid. Their cursors still advance past excluded rows.
    private func currentExclusions() -> Set<String> { Set(candidates.map { $0.uid }) }

    // D2.6: per-league capacity (usageByLeague is zero-filled for every league on load).
    private func usage(_ league: Int) -> Int { usageByLeague[league] ?? 0 }
    private func cap(_ league: Int) -> Int { DuelConstants.maxConcurrentDuels(league: league) }
    private func isFull(_ league: Int) -> Bool { usage(league) >= cap(league) }
    private var allLeaguesFull: Bool { DuelConstants.leagues.allSatisfy { isFull($0) } }

    private var sendTitle: String {
        if let opponent = selectedOpponent { return "Challenge \(opponent.displayLabel)" }
        return "Send Challenge"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                if loadingPeople {
                    ProgressView().tint(tc.primary)
                } else if loadFailed {
                    emptyPeople
                } else {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                                searchField
                                if searchPhase != .idle { searchResultArea }
                                if !friends.isEmpty { carousel("RIVALS", friends) }
                                if !guildMates.isEmpty { carousel("GUILD", guildMates) }
                                nearbySection
                            }
                            .padding(DesignSystem.Spacing.lg)
                        }
                        bottomDock
                    }
                }
            }
            .navigationTitle("New Duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
        .task { await loadPeople() }
        .onDisappear {
            // Cancel any in-flight page load / search so no stale write lands after dismissal.
            searchTask?.cancel()
            loadMoreTask?.cancel()
        }
        // NAV-1b: long-press "View Profile" → read-only profile sheet, stacked above the
        // lobby. Selection state is untouched; a block drops the person on return via loadPeople.
        .sheet(item: $profilePerson) { person in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: person.uid,
                username: person.username,
                displayName: person.displayName,
                onRemoved: { Task { await loadPeople() } }
            )
        }
    }

    // MARK: - Couldn't-load empty state (load failure only)

    private var emptyPeople: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "person.2.slash")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text("Couldn't load the challenge lobby right now. Close and try again in a moment.")
                .font(AppFont.regular(15))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textTertiary)
            TextField("Find by @username", text: $searchText)
                .font(AppFont.regular(15))
                .foregroundColor(tc.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { runSearch(immediate: true) }
            if !searchText.isEmpty {
                Button {
                    searchText = ""   // onChange resets the phase + clears the result
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.2), fillColor: tc.cardBackground)
        .onChange(of: searchText) { _, _ in runSearch(immediate: false) }
    }

    @ViewBuilder
    private var searchResultArea: some View {
        switch searchPhase {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView().tint(tc.primary)
                Text("Searching…")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .result:
            if let result = searchResult { opponentRow(result) }
        case .noMatch:
            Text("No one has that username.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - RIVALS / GUILD carousels

    private func carousel(_ title: String, _ people: [DuelOpponentCandidate]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(AppFont.display(15))
                .foregroundColor(tc.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(people) { opponentCard($0) }
                }
                .padding(.vertical, 3)   // room for the selection stroke / check overlay
            }
        }
    }

    private func opponentCard(_ person: DuelOpponentCandidate) -> some View {
        let isSelected = selectedOpponent == person
        return Button {
            select(person)
        } label: {
            VStack(spacing: DesignSystem.Spacing.sm) {
                StandingsPieces.avatar(initial: initial(person),
                                       tint: DesignSystem.Erewhon.rankMetal(forRR: person.rr))
                Text(person.displayLabel)
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let rr = person.rr {
                    HStack(spacing: 4) {
                        RankPlaque(rank: Rank.getRank(from: rr), size: 16)
                        Text("\(rr)")
                            .font(AppFont.display(17))
                            .foregroundColor(tc.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: 100)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .adaptiveCard(borderColor: isSelected ? tc.primary : tc.primary.opacity(0.2),
                          fillColor: tc.cardBackground,
                          isSelected: isSelected)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.primary)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        // NAV-1b: long-press to view the profile; tap still selects.
        .contextMenu {
            Button {
                profilePerson = person
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
        }
    }

    // MARK: - NEARBY RANKS stream

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEARBY RANKS")
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textSecondary)
                Spacer()
                Text("YOU: \(myRR) RR")
                    .font(AppFont.display(15))
                    .foregroundColor(tc.primary)
            }

            if !nearbyRows.isEmpty {
                LazyVStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(nearbyRows) { opponentRow($0) }
                }
            } else if isExhausted {
                Text("No ranked players nearby yet.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

            if !isExhausted {
                loadMoreButton
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            loadMore()
        } label: {
            HStack {
                Spacer()
                if loadingMore {
                    ProgressView().tint(tc.primary)
                } else {
                    Text("Load more")
                        .font(AppFont.bold(14))
                        .foregroundColor(tc.primary)
                }
                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(loadingMore)
    }

    /// Shared by the stream AND the pinned search-result row (the "same row component").
    private func opponentRow(_ person: DuelOpponentCandidate) -> some View {
        let isSelected = selectedOpponent == person
        return Button {
            select(person)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                StandingsPieces.avatar(initial: initial(person),
                                       tint: DesignSystem.Erewhon.rankMetal(forRR: person.rr))
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayLabel)
                        .font(AppFont.bold(15))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    // A ranked directory row carries a real displayName → show the @handle under
                    // it. An unranked hit's label IS "@handle", so skip the duplicate line.
                    if !person.displayName.isEmpty {
                        Text("@\(person.username)")
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DesignSystem.Spacing.sm)
                if let rr = person.rr {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 5) {
                            RankPlaque(rank: Rank.getRank(from: rr), size: 18)
                            Text("\(rr)")
                                .font(AppFont.display(18))
                                .foregroundColor(tc.textPrimary)
                                .monospacedDigit()
                        }
                        deltaCaption(rr: rr)
                    }
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.primary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(borderColor: isSelected ? tc.primary : tc.primary.opacity(0.2),
                          fillColor: tc.cardBackground,
                          isSelected: isSelected)
        }
        .buttonStyle(.plain)
        // NAV-1b: long-press to view the profile; tap still selects.
        .contextMenu {
            Button {
                profilePerson = person
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
        }
    }

    /// `+N vs you` / `−N vs you` / `even` (N = rr − myRR). Positive → secondary; negative or
    /// even → tertiary (rank derives from `rr` only — never a local table).
    @ViewBuilder
    private func deltaCaption(rr: Int) -> some View {
        let delta = rr - myRR
        let text = delta > 0 ? "+\(delta) vs you" : (delta < 0 ? "−\(abs(delta)) vs you" : "even")
        Text(text)
            .font(AppFont.regular(11))
            .foregroundColor(delta > 0 ? tc.textSecondary : tc.textTertiary)
    }

    // MARK: - Bottom dock (league pills + send)

    private var bottomDock: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if allLeaguesFull {
                Text("All duel slots are full — finish a duel to start another.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(DuelConstants.leagues, id: \.self) { days in
                        leaguePill(days)
                    }
                }
                // Captions only for full leagues (D2.6).
                ForEach(DuelConstants.leagues.filter { isFull($0) }, id: \.self) { days in
                    Text("\(days)-day full (\(usage(days))/\(cap(days)))")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let inlineError {
                Text(inlineError)
                    .font(AppFont.regular(13))
                    .foregroundColor(DesignSystem.Colors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            AppButton(
                title: sendTitle,
                style: .primary,
                action: { Task { await send() } },
                isLoading: isSending,
                isDisabled: !canSend,
                icon: "flag.2.crossed.fill"
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .background(tc.primaryBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignSystem.Erewhon.line).frame(height: 1)
        }
    }

    /// R2 selection convention (MatchmakingSheet's exemplar): accent fill selected / surface +
    /// hairline unselected. Replaces the sheet's pre-R6c hardcoded `.white` + manual `Capsule`.
    private func leaguePill(_ days: Int) -> some View {
        let isSelected = selectedLeague == days
        let full = isFull(days)
        return Button {
            guard !full else { return }
            selectedLeague = days
            inlineError = nil
        } label: {
            Text("\(days)-Day")
                .font(AppFont.bold(14))
                .foregroundColor(isSelected ? DesignSystem.Erewhon.onAccent : tc.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .adaptivePill(borderColor: isSelected ? tc.primary : DesignSystem.Erewhon.line,
                              fillColor: isSelected ? tc.primary : tc.cardBackground,
                              isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.5 : 1.0)
    }

    // MARK: - Helpers

    /// First letter for the metal avatar — from the display name, else the username (never the
    /// "@" of a bare-handle label).
    private func initial(_ person: DuelOpponentCandidate) -> String {
        let base = person.displayName.isEmpty ? person.username : person.displayName
        return String(base.first.map(String.init) ?? "?").uppercased()
    }

    private func select(_ person: DuelOpponentCandidate) {
        selectedOpponent = person
        inlineError = nil
    }

    // MARK: - Actions

    private func loadPeople() async {
        // Establish identity + my RR first. A guest / missing progress is the only genuine
        // "couldn't load" — an authentically empty world still shows the search + empty caption.
        let progress = try? await coordinator.getUserProgress()
        guard !coordinator.isGuest, let progress else {
            loadFailed = true
            loadingPeople = false
            return
        }
        myRR = max(0, progress.rr)

        async let peopleTask = coordinator.fetchChallengeablePeople()
        async let usageTask = coordinator.duelSlotUsageByLeague()
        candidates = await peopleTask
        usageByLeague = await usageTask

        // D2: pre-select the passed-in friend, matched by uid so the row's `==` selection holds.
        if let pre = preselected, selectedOpponent == nil,
           let match = candidates.first(where: { $0.uid == pre.uid }) {
            selectedOpponent = match
        }

        // First proximity page (both directions from my RR), excluding my friends + guild-mates.
        let page = await coordinator.fetchNearbyRanked(
            myRR: myRR, upCursor: nil, downCursor: nil, isFirstPage: true, excluding: currentExclusions())
        if Task.isCancelled { return }
        nearbyRows = page.rows
        upCursor = page.upCursor
        downCursor = page.downCursor
        isExhausted = page.isExhausted
        loadingPeople = false
    }

    /// Appends the next proximity page. Guarded by `loadingMore` so only one page is ever
    /// in flight (rapid taps are ignored). The cursor guarantees no duplicates across pages.
    private func loadMore() {
        guard !loadingMore, !isExhausted else { return }
        loadingMore = true
        loadMoreTask = Task {
            let page = await coordinator.fetchNearbyRanked(
                myRR: myRR, upCursor: upCursor, downCursor: downCursor,
                isFirstPage: false, excluding: currentExclusions())
            if Task.isCancelled { return }
            nearbyRows.append(contentsOf: page.rows)
            upCursor = page.upCursor
            downCursor = page.downCursor
            isExhausted = page.isExhausted
            loadingMore = false
        }
    }

    /// Exact `@handle` lookup. Each keystroke debounces 400ms; a submit fires immediately. The
    /// previous in-flight lookup is cancelled so the latest query always wins; searching never
    /// touches the stream's pagination state.
    private func runSearch(immediate: Bool) {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchPhase = .idle
            searchResult = nil
            return
        }
        searchPhase = .searching
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
            }
            let result = await coordinator.lookupChallengeCandidate(handle: query)
            if Task.isCancelled { return }
            searchResult = result
            searchPhase = (result == nil) ? .noMatch : .result
        }
    }

    private func send() async {
        guard let opponent = selectedOpponent, let league = selectedLeague else { return }
        isSending = true
        inlineError = nil
        do {
            try await coordinator.sendChallenge(to: opponent, league: league)
            isSending = false
            onSent()
            dismiss()
        } catch {
            isSending = false
            inlineError = (error as? DuelError)?.errorDescription ?? "Couldn't send the challenge."
        }
    }
}
