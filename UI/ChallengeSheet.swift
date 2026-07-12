//
//  ChallengeSheet.swift
//  HealthBar
//
//  Created by Claude on 7/3/26.
//

import SwiftUI

/// Direct-challenge composer (D1a): pick an opponent (friends / guild-mates) and a
/// league (1 / 3 / 5-day), then send. Send is disabled until BOTH are chosen —
/// validated by construction, not after tap. A duplicate pending challenge surfaces
/// inline. Success toasts, dismisses, and refreshes the Battle list via `onSent`.
struct ChallengeSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let coordinator: AppCoordinator
    /// D2: a friend to pre-select on open (from the matchup preview's Challenge CTA). Additive.
    private let preselected: DuelOpponentCandidate?
    private let onSent: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var candidates: [DuelOpponentCandidate] = []
    @State private var loadingPeople = true

    @State private var selectedOpponent: DuelOpponentCandidate?
    /// nil until the user picks — drives the "must choose a league" gate.
    @State private var selectedLeague: Int?

    /// D3: username filter for the EVERYONE (directory) section — shown only on long lists.
    @State private var directoryFilter = ""

    /// Per-league starting-path slot usage (D2.6), zero-filled for every league on load.
    @State private var usageByLeague: [Int: Int] = [:]

    @State private var isSending = false
    @State private var inlineError: String?

    init(coordinator: AppCoordinator, preselected: DuelOpponentCandidate? = nil, onSent: @escaping () -> Void = {}) {
        self.coordinator = coordinator
        self.preselected = preselected
        self.onSent = onSent
    }

    private var friends: [DuelOpponentCandidate] { candidates.filter { $0.source == .friend } }
    private var guildMates: [DuelOpponentCandidate] { candidates.filter { $0.source == .guild } }
    private var directoryPeople: [DuelOpponentCandidate] { candidates.filter { $0.source == .directory } }

    /// Directory rows after the username filter (leading-@ stripped, case-insensitive contains —
    /// the same normalization FriendsView uses). Empty query → the whole directory.
    private var filteredDirectory: [DuelOpponentCandidate] {
        let q = directoryFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let needle = q.hasPrefix("@") ? String(q.dropFirst()) : q
        guard !needle.isEmpty else { return directoryPeople }
        return directoryPeople.filter { $0.username.lowercased().contains(needle) }
    }

    /// Validate by construction: both selections required, not mid-send.
    private var canSend: Bool { selectedOpponent != nil && selectedLeague != nil && !isSending }

    // D2.6: per-league capacity (usageByLeague is zero-filled for every league on load).
    private func usage(_ league: Int) -> Int { usageByLeague[league] ?? 0 }
    private func cap(_ league: Int) -> Int { DuelConstants.maxConcurrentDuels(league: league) }
    private func isFull(_ league: Int) -> Bool { usage(league) >= cap(league) }
    private var allLeaguesFull: Bool { DuelConstants.leagues.allSatisfy { isFull($0) } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                if loadingPeople {
                    ProgressView().tint(tc.primary)
                } else if candidates.isEmpty {
                    emptyPeople
                } else {
                    form
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
    }

    // MARK: - Empty

    private var emptyPeople: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "person.2.slash")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text("Couldn't load people to challenge right now. Close and try again in a moment.")
                .font(AppFont.regular(15))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                opponentPicker
                leaguePicker

                if let inlineError {
                    Text(inlineError)
                        .font(AppFont.regular(13))
                        .foregroundColor(DesignSystem.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AppButton(
                    title: "Send Challenge",
                    style: .primary,
                    action: { Task { await send() } },
                    isLoading: isSending,
                    isDisabled: !canSend
                )
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Opponent picker

    private var opponentPicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Opponent")
                .font(AppFont.bold(15))
                .foregroundColor(tc.textPrimary)

            if !friends.isEmpty {
                pickerSection("Friends", friends)
            }
            if !guildMates.isEmpty {
                pickerSection("Guild", guildMates)
            }
            if !directoryPeople.isEmpty {
                everyoneSection
            }
        }
    }

    /// D3: everyone else in the public directory. A username filter appears once the section is
    /// long (~10+); the pending accept flow + respondBy expiry are the consent mechanism.
    private var everyoneSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("EVERYONE")
                .font(AppFont.regular(11))
                .foregroundColor(tc.textTertiary)

            if directoryPeople.count > 10 {
                directoryFilterField
            }

            let rows = filteredDirectory
            if rows.isEmpty {
                Text("No one matches that username.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    ForEach(rows) { person in
                        opponentRow(person)
                    }
                }
            }
        }
    }

    private var directoryFilterField: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textTertiary)
            TextField("Filter by @username", text: $directoryFilter)
                .font(AppFont.regular(14))
                .foregroundColor(tc.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: tc.primary.opacity(0.2), fillColor: tc.cardBackground)
    }

    private func pickerSection(_ title: String, _ people: [DuelOpponentCandidate]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title.uppercased())
                .font(AppFont.regular(11))
                .foregroundColor(tc.textTertiary)
            ForEach(people) { person in
                opponentRow(person)
            }
        }
    }

    private func opponentRow(_ person: DuelOpponentCandidate) -> some View {
        let isSelected = selectedOpponent == person
        return Button {
            selectedOpponent = person
            inlineError = nil
        } label: {
            HStack {
                Text(person.displayLabel)
                    .font(AppFont.regular(15))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(tc.primary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(
                borderColor: isSelected ? tc.primary : tc.primary.opacity(0.2),
                fillColor: tc.cardBackground,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - League picker

    private var leaguePicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("League")
                .font(AppFont.bold(15))
                .foregroundColor(tc.textPrimary)

            if allLeaguesFull {
                Text("All duel slots are full — finish a duel to start another.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(DuelConstants.leagues, id: \.self) { days in
                        leagueButton(days)
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
        }
    }

    private func leagueButton(_ days: Int) -> some View {
        let isSelected = selectedLeague == days
        let full = isFull(days)
        return Button {
            guard !full else { return }
            selectedLeague = days
            inlineError = nil
        } label: {
            Text("\(days)-Day")
                .font(AppFont.bold(14))
                .foregroundColor(isSelected ? .white : tc.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(isSelected ? tc.primary : tc.cardBackground)
                .overlay(
                    Capsule().stroke(tc.primary.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.5 : 1.0)
    }

    // MARK: - Actions

    private func loadPeople() async {
        async let people = coordinator.fetchChallengeablePeople()
        async let usage = coordinator.duelSlotUsageByLeague()
        candidates = await people
        usageByLeague = await usage
        // D2: pre-select the passed-in friend, matched by uid so the row's `==` selection holds.
        if let pre = preselected, selectedOpponent == nil,
           let match = candidates.first(where: { $0.uid == pre.uid }) {
            selectedOpponent = match
        }
        loadingPeople = false
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
