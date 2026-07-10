//
//  MatchmakingSheet.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import SwiftUI

/// Ranked matchmaking queue (D2): pick a league, enter the queue, and poll for a compatible
/// opponent near your RR. A match creates an immediately-active duel (no accept phase) and hands
/// it back to the Battle tab, which pushes the Arena.
///
/// Polling, not listeners (the guild-chat listener remains the app's only one): the sheet loops
/// `coordinator.pollQueue` every `queuePollInterval` inside a cancellation-safe `.task` while the
/// searching state is presented. ALL queue I/O stops when the sheet dismisses — the `.task` is
/// cancelled and `leaveQueue()` runs in `onDisappear`, so cleanup survives cancellation.
struct MatchmakingSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let coordinator: AppCoordinator
    /// My Firebase uid — picks the counterpart label on the matched duel.
    private let myUid: String
    /// Called once with the matched duel just before the sheet dismisses.
    private let onMatched: (DuelDTO) -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    private enum Phase: Equatable { case pickLeague, searching, matched }
    @State private var phase: Phase = .pickLeague

    /// nil until the user picks — drives the "must choose a league" gate.
    @State private var selectedLeague: Int?
    /// Per-league starting-path slot usage (D2.6), zero-filled on load; refreshed each time
    /// the pick-league step appears (including after an at-capacity bounce-back).
    @State private var usageByLeague: [Int: Int] = [:]
    /// Enqueue time held in the sheet (NOT the ticket) — drives the elapsed timer and the RR
    /// band schedule; reset on every re-entry.
    @State private var startedAt: Date?
    /// Current RR band, refreshed each poll (flavor text only).
    @State private var currentBand: Int = DuelConstants.queueBands.first ?? 100
    @State private var matchedDuel: DuelDTO?
    @State private var errorText: String?
    @State private var pulse = false
    /// Guards against a double onMatched/dismiss.
    @State private var didFinish = false

    // MARK: - Init

    init(coordinator: AppCoordinator, myUid: String, onMatched: @escaping (DuelDTO) -> Void) {
        self.coordinator = coordinator
        self.myUid = myUid
        self.onMatched = onMatched
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                switch phase {
                case .pickLeague: pickLeagueView
                case .searching:  searchingView
                case .matched:    matchedView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ranked Match")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                if phase == .pickLeague {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(tc.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(false)
        // Any dismissal (swipe / cancel / matched) reaps my ticket. Matched already deleted it
        // in-protocol, so this is a harmless no-op delete of a missing doc.
        .onDisappear { Task { await coordinator.leaveQueue() } }
    }

    // MARK: - Pick league

    // D2.6: per-league capacity (usageByLeague is zero-filled for every league on load).
    private func usage(_ league: Int) -> Int { usageByLeague[league] ?? 0 }
    private func cap(_ league: Int) -> Int { DuelConstants.maxConcurrentDuels(league: league) }
    private func isFull(_ league: Int) -> Bool { usage(league) >= cap(league) }
    private var allLeaguesFull: Bool { DuelConstants.leagues.allSatisfy { isFull($0) } }

    private func loadUsage() async { usageByLeague = await coordinator.duelSlotUsageByLeague() }

    private var pickLeagueView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
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
                    ForEach(DuelConstants.leagues.filter { isFull($0) }, id: \.self) { days in
                        Text("\(days)-day full (\(usage(days))/\(cap(days)))")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Text("You'll be matched with a player near your RR.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)

                if let errorText {
                    Text(errorText)
                        .font(AppFont.regular(13))
                        .foregroundColor(DesignSystem.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AppButton(
                    title: "Enter Queue",
                    style: .primary,
                    action: { enterQueue() },
                    isDisabled: selectedLeague == nil
                )
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .task { await loadUsage() }
    }

    private func leagueButton(_ days: Int) -> some View {
        let isSelected = selectedLeague == days
        let full = isFull(days)
        return Button {
            guard !full else { return }
            selectedLeague = days
            errorText = nil
        } label: {
            Text("\(days)-Day")
                .font(AppFont.bold(14))
                .foregroundColor(isSelected ? DesignSystem.Erewhon.onAccent : tc.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                // R2 selection convention: accent fill selected / surface + hairline unselected.
                .adaptivePill(borderColor: isSelected ? tc.primary : DesignSystem.Erewhon.line,
                              fillColor: isSelected ? tc.primary : tc.cardBackground)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.5 : 1.0)
    }

    // MARK: - Searching

    private var searchingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: "flag.2.crossed.fill")
                .font(AppFont.regular(56))
                .foregroundColor(tc.primary)
                .opacity(pulse ? 0.4 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            if let startedAt {
                HStack(spacing: 4) {
                    // "Searching…" is a word (Hanken); the timer is a figure (display, D6).
                    Text("Searching…").font(AppFont.bold(16))
                    Text(startedAt, style: .timer).font(AppFont.display(16))
                }
                .foregroundColor(tc.textPrimary)
            }

            Text("±\(currentBand) RR")
                .font(AppFont.regular(11))
                .foregroundColor(tc.textTertiary)

            Spacer()

            AppButton(title: "Cancel", style: .secondary, action: { dismiss() })
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await runSearch() }
    }

    // MARK: - Matched

    private var matchedView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Spacer()

            Image(systemName: "flag.2.crossed.fill")
                .font(AppFont.regular(56))
                .foregroundColor(tc.primary)

            Text("Matched!")
                .font(AppFont.display(22))
                .foregroundColor(tc.textPrimary)

            if let duel = matchedDuel {
                Text(duel.opponentLabel(of: myUid))
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
                Text("\(duel.league)-Day Ranked Duel")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(1))   // brief flash
            finishMatch()
        }
    }

    // MARK: - Actions

    private func enterQueue() {
        guard selectedLeague != nil else { return }
        startedAt = Date()
        currentBand = DuelConstants.queueBand(forElapsed: 0)
        errorText = nil
        withAnimation { phase = .searching }
    }

    /// Enqueue, then poll every `queuePollInterval` until matched or cancelled. Runs inside the
    /// searching view's `.task`, so leaving that state (match / dismiss) cancels it.
    private func runSearch() async {
        guard let league = selectedLeague, let start = startedAt else { return }
        do {
            try await coordinator.joinQueue(league: league)
        } catch {
            errorText = (error as? DuelError)?.errorDescription ?? "Couldn't enter the queue."
            withAnimation { phase = .pickLeague }
            return
        }

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            currentBand = DuelConstants.queueBand(forElapsed: elapsed)
            do {
                if let duel = try await coordinator.pollQueue(league: league, elapsed: elapsed) {
                    matchedDuel = duel
                    withAnimation { phase = .matched }   // matchedView's .task handles the timed dismiss
                    return
                }
            } catch {
                // D2.6: a challenge accepted against me mid-queue filled my last slot → leave the
                // queue (delete my live ticket so I'm not matchable while at cap) and bounce to the
                // league picker with the capacity message. Other errors are transient (keep polling).
                if let duelError = error as? DuelError, case .leagueAtCapacity = duelError {
                    await coordinator.leaveQueue()
                    errorText = duelError.errorDescription
                    withAnimation { phase = .pickLeague }
                    return
                }
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(DuelConstants.queuePollInterval))
        }
    }

    private func finishMatch() {
        guard !didFinish, let duel = matchedDuel else { return }
        didFinish = true
        onMatched(duel)
        dismiss()
    }
}
