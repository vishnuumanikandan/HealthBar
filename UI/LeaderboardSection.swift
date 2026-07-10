//
//  LeaderboardSection.swift
//  HealthBar
//
//  Created by Claude on 6/11/26.
//

import SwiftUI

/// Embeddable, non-scrolling friend leaderboard (Friend System Phase 5).
///
/// Extracted from the standalone `LeaderboardView` so the ranking can live as
/// a section inside Home's existing `ScrollView`. Lays out a header plus a
/// `LazyVStack` of rows — NO `ScrollView`/`List` wrapper — so the whole Home
/// page scrolls as one.
///
/// All ranking/fetch logic stays in the injected `LeaderboardViewModel` (owned
/// by the parent); this view only renders that view model's state and presents
/// the per-friend read-only profile sheet (Phase 4). Guests never trigger a
/// fetch — the parent gates the load and this view renders the sign-in prompt.
struct LeaderboardSection: View {

    // MARK: - Properties

    /// Owned by the parent (HomeView). Held as a plain reference so the
    /// Observation framework still tracks the properties this view reads.
    let viewModel: LeaderboardViewModel

    /// Retained to construct the FriendProfileView sheet (Phase 4).
    private let coordinator: AppCoordinator

    /// Read-only — gates the guest state. Guests never trigger a fetch.
    private let authService: any AuthService

    /// Routes to the Friends tab for the no-friends CTA (HomeView selects the
    /// tab via the existing tab-bar mechanism).
    private let onAddFriends: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Friend whose read-only profile sheet is open (Friend System Phase 4).
    @State private var profileEntry: LeaderboardEntry? = nil

    /// Drives the one-shot staggered reveal of the ranking rows.
    @State private var revealed = false

    // MARK: - Init

    init(
        viewModel: LeaderboardViewModel,
        coordinator: AppCoordinator,
        authService: any AuthService,
        onAddFriends: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        self.authService = authService
        self.onAddFriends = onAddFriends
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            header

            // The header always shows; only the body below swaps between the
            // guest / loading / empty / error / ranking states — never a
            // full-screen takeover, so the dashboard above stays put.
            if authService.isGuest {
                guestCard
            } else if viewModel.isLoading && !viewModel.hasLoaded {
                loadingCard
            } else if let error = viewModel.loadError, !viewModel.hasFriendRows {
                // A failed first load with nothing to show: error + retry,
                // never the "add friends" prompt (which would read as success).
                errorCard(error)
            } else if !viewModel.hasFriendRows {
                // Loaded fine, but the only row is the current user.
                addFriendsCard
            } else {
                // A refresh that failed while old rows are still on screen keeps
                // the ranking and surfaces a quiet inline note above it.
                if let error = viewModel.loadError {
                    inlineError(error)
                }
                metricHeader
                rankingList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $profileEntry) { entry in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: entry.uid,
                username: entry.username,
                displayName: entry.displayName,
                onRemoved: { Task { await viewModel.refresh() } }
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if settings.isCleanUI {
            // Erewhon sec-head: title + right-aligned metric caption over a soft hairline.
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Leaderboard")
                        .font(AppFont.display(15))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    Text("Days on goal")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
                .padding(.bottom, 10)
                Rectangle()
                    .fill(DesignSystem.Erewhon.lineSoft)
                    .frame(height: 1)
            }
        } else {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(AppFont.regular(20))
                    .foregroundColor(DesignSystem.Colors.goldMid)

                Text("Leaderboard")
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)

                Spacer()
            }
        }
    }

    // MARK: - Ranking List

    private var rankingList: some View {
        // LazyVStack, never a nested ScrollView/List: the page scrolls as one. Hairline-separated
        // ladder rows (D5); the whole board still cascades in once, top rank first — 40ms steps
        // keep it under half a second even with a full friends list.
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.entries.enumerated()), id: \.element.uid) { index, entry in
                entryRow(entry, position: index + 1, isLast: index == viewModel.entries.count - 1)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 14)
                    .animation(
                        .easeOut(duration: 0.3).delay(Double(index) * 0.04),
                        value: revealed
                    )
            }
        }
        .onAppear { revealed = true }
    }

    // MARK: - Guest State

    private var guestCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)

            Text("Sign in to compete")
                .font(AppFont.bold(18))
                .foregroundColor(tc.textPrimary)

            Text("The leaderboard ranks you and your friends by weekly goal adherence. Create a free account to join.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Loading / Error States

    private var loadingCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .tint(tc.primary)

            Text("Summoning the rankings…")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            inlineError(message)

            AppButton(
                title: "Retry",
                style: .secondary,
                action: { Task { await viewModel.refresh() } }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// One-line explainer of the primary metric so the numbers read instantly.
    private var metricHeader: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "target")
                .font(AppFont.regular(14))
                .foregroundColor(tc.primary)

            Text("Ranked by days all goals were hit this week")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Empty state when the user has no friends yet — routes to the Friends tab.
    /// Shown in place of the ranking, never as a lone "#1 You" row.
    private var addFriendsCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "person.2")
                .font(AppFont.regular(36))
                .foregroundColor(tc.textTertiary)

            Text("Add friends to compete")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            Text("Your weekly goal adherence ranks against your friends' here.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)

            AppButton(
                title: "Add Friends",
                style: .primary,
                action: { onAddFriends() }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Entry Row

    /// Friend rows open the read-only profile sheet; the current-user row
    /// stays inert (own profile lives in the Profile tab).
    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry, position: Int, isLast: Bool) -> some View {
        if entry.isCurrentUser {
            entryRowContent(entry, position: position, isLast: isLast)
        } else {
            Button {
                profileEntry = entry
            } label: {
                entryRowContent(entry, position: position, isLast: isLast)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Mockup `.lrow`: rank chip · rank-tinted avatar · name (+ you-pill) & tier/level sub-line ·
    /// days-on-goal figure with the dashed 7-pip strip. The you-row gets a full-row accent
    /// highlight (replacing the old tinted fill); podium chips carry the metal; other rows are
    /// hairline-separated (D5).
    @ViewBuilder
    private func entryRowContent(_ entry: LeaderboardEntry, position: Int, isLast: Bool) -> some View {
        let metal = metalColor(position, hasData: entry.hasData)
        let row = HStack(alignment: .center, spacing: 13) {
            rankChip(position, hasData: entry.hasData, metal: metal)
            avatar(initial: initial(for: entry), tint: entry.hasData ? erewhonRankMetal(forRR: entry.rr) : nil)
            who(entry)
            Spacer(minLength: DesignSystem.Spacing.sm)
            adherenceColumn(entry)
        }
        .padding(.vertical, 13)
        .opacity(entry.hasData ? 1.0 : 0.7)

        if entry.isCurrentUser {
            // Full-row accent highlight (mockup `.is-you`) — replaces the old tinted fill.
            row
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(tc.cardBackground.mix(with: tc.primary, by: 0.09)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tc.primary.opacity(0.4), lineWidth: 1.5))
        } else {
            VStack(spacing: 0) {
                row.padding(.horizontal, 4)
                if !isLast {
                    Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
                }
            }
        }
    }

    /// Mockup `.pos`: a small rounded-square rank chip. Podium chips are metal-filled (white
    /// numeral); off-podium chips are neutral. Crown kept above #1 (where it lives today).
    private func rankChip(_ position: Int, hasData: Bool, metal: Color?) -> some View {
        VStack(spacing: 1) {
            if hasData && position == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(metal ?? DesignSystem.Colors.goldMid)
            }
            Text(hasData ? "\(position)" : "–")
                .font(AppFont.display(15))
                .foregroundColor(metal != nil ? .white : (hasData ? tc.textSecondary : tc.textTertiary))
                .monospacedDigit()
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(metal ?? tc.segBackground))
        }
        .frame(width: 30)
    }

    /// Mockup `.av`: 38×38 rounded-square initials avatar, rank-tinted (nil tint → neutral fill).
    private func avatar(initial: String, tint: Color?) -> some View {
        Text(initial)
            .font(AppFont.bold(15))
            .foregroundColor(tint != nil ? .white : tc.textPrimary)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint ?? tc.segBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tint != nil ? Color.white.opacity(0.22) : DesignSystem.Erewhon.line, lineWidth: 1)
                    .padding(3)
            )
    }

    /// Name (+ you-pill) and the tier/level sub-line.
    private func who(_ entry: LeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(entry.displayName.isEmpty ? "@\(entry.username)" : entry.displayName)
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                if entry.isCurrentUser { youPill }
            }
            if let sub = subline(entry) {
                Text(sub)
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Mockup `.you` pill: accent-tinted "YOU".
    private var youPill: some View {
        Text("You")
            .font(AppFont.bold(9))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundColor(tc.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(tc.primary.opacity(0.13)))
    }

    /// Sub-line: "Tier · Lv N" for published rows (tier omitted when rr is unpublished — no
    /// invented tier); plain @username for no-data rows (no invented tier/level).
    private func subline(_ entry: LeaderboardEntry) -> String? {
        guard entry.hasData else {
            return entry.displayName.isEmpty ? nil : "@\(entry.username)"
        }
        let tier = entry.rr.map { Rank.rankTier(from: $0).displayName }
        return [tier, "Lv \(entry.level)"].compactMap { $0 }.joined(separator: " · ")
    }

    /// First initial for the avatar (display name, else username).
    private func initial(for entry: LeaderboardEntry) -> String {
        let name = entry.displayName.isEmpty ? entry.username : entry.displayName
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    /// Days-on-goal figure (display) with the dashed 7-pip strip; a dash for no-data rows.
    private func adherenceColumn(_ entry: LeaderboardEntry) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            if entry.hasData {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.weeklyGoalsMet)")
                        .font(AppFont.display(18))
                        .foregroundColor(tc.textPrimary)
                    Text("/7")
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textTertiary)
                }
                pips(on: entry.weeklyGoalsMet)
            } else {
                Text("–")
                    .font(AppFont.display(18))
                    .foregroundColor(tc.textTertiary)
                Text("no data yet")
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
            }
        }
    }

    /// Mockup `.pips`: seven 7×3 pips, the first `count` filled with the accent.
    private func pips(on count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < count ? tc.primary : tc.segBackground)
                    .frame(width: 7, height: 3)
            }
        }
    }

    // MARK: - Colors

    /// Podium metals: gold, silver, bronze. nil off the podium or without data.
    /// Flat (Erewhon) uses the shared rank-metal tokens; pixel keeps its original hexes so
    /// pixel Home stays byte-identical (D7).
    private func metalColor(_ position: Int, hasData: Bool) -> Color? {
        guard hasData else { return nil }
        let isClean = settings.isCleanUI
        switch position {
        case 1: return isClean ? DesignSystem.Erewhon.rankGold : DesignSystem.Colors.goldMid
        case 2: return isClean ? DesignSystem.Erewhon.rankSilver : Color(hex: "#9CA3AF") // silver
        case 3: return isClean ? DesignSystem.Erewhon.rankBronze : Color(hex: "#CD7F32") // bronze
        default: return nil
        }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.danger)

            Text(message)
                .font(AppFont.regular(12))
                .foregroundColor(DesignSystem.Colors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rank-tier avatar metal from `rr`, using the Erewhon rank-metal tokens (never hardcoded
/// hexes). `nil` → neutral fill. Only four metal tokens exist pre-R5/R6, so the top tiers
/// share `rankGold`; this is a decorative wash, not a precise per-rank ladder colour.
fileprivate func erewhonRankMetal(forRR rr: Int?) -> Color? {
    guard let rr else { return nil }
    switch Rank.getRank(from: rr) {
    case .stone: return nil
    case .copper: return DesignSystem.Erewhon.rankBronze
    case .iron: return DesignSystem.Erewhon.rankIron
    case .gold, .rankVII, .rankVIII, .rankIX: return DesignSystem.Erewhon.rankGold
    case .platinum, .diamond: return DesignSystem.Erewhon.rankSilver
    }
}
