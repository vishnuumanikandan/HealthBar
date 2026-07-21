//
//  GuildLeaderboardView.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import SwiftUI

/// Guild leaderboard (Guilds Prompt G2): ranks the current user's guild-mates by
/// a selectable metric (Adherence / XP / Level). Pushed from GuildDetailView.
///
/// Reuses the friend-leaderboard `LeaderboardEntry`; the metric toggle re-sorts
/// in memory (no refetch). NAV-1b: every non-self guild-mate opens their read-only
/// profile, friend or not; only the current-user row is inline-only.
struct GuildLeaderboardView: View {

    // MARK: - Properties

    @State private var viewModel: GuildLeaderboardViewModel

    /// Retained to build the FriendProfileView sheet.
    private let coordinator: AppCoordinator

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Friend whose read-only profile sheet is open.
    @State private var profileEntry: LeaderboardEntry? = nil

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: GuildLeaderboardViewModel(coordinator: coordinator))
        self.coordinator = coordinator
    }

    private var metricBinding: Binding<GuildMetric> {
        Binding(get: { viewModel.metric }, set: { viewModel.metric = $0 })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            tc.primaryBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    metricPicker

                    if viewModel.isLoading && !viewModel.hasLoaded {
                        loadingCard
                    } else {
                        if let error = viewModel.loadError {
                            inlineError(error)
                        }
                        rankingBox
                        if viewModel.isSoloGuild {
                            inviteHint
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .refreshable { await viewModel.refresh() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Leaderboard")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .task {
            await viewModel.refresh()
        }
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

    // MARK: - Metric Toggle

    private var metricPicker: some View {
        Picker("Metric", selection: metricBinding) {
            ForEach(GuildMetric.allCases) { metric in
                Text(metric.rawValue).tag(metric)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Ranking List

    /// LB-PAGE-1: the ranking wrapped in the compact, internally-scrolling box (no pager — guild
    /// data is already fully fetched). The outer `ScrollView` + `refreshable` remain, so
    /// pull-to-refresh still works from outside the box. Rows are NOT restyled.
    private var rankingBox: some View {
        // LB-PAGE-1: deliberate nested-scroll exception (user ruling; Clash-style boxed board). Revisit if it fights the outer scroll. DO NOT replace with outer scrolling.
        ScrollView {
            rankingList
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .frame(height: DesignSystem.Metrics.leaderboardBoxHeightCompact)
        .background(RoundedRectangle(cornerRadius: 16).fill(tc.primaryBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var rankingList: some View {
        LazyVStack(spacing: DesignSystem.Spacing.md) {
            ForEach(Array(viewModel.sortedEntries.enumerated()), id: \.element.uid) { index, entry in
                entryRow(entry, position: index + 1)
            }
        }
    }

    /// NAV-1b: every non-self row opens the read-only profile sheet, friend or not;
    /// only the current-user row is inert (inline-only).
    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry, position: Int) -> some View {
        if !entry.isCurrentUser {
            Button {
                profileEntry = entry
            } label: {
                entryRowContent(entry, position: position, tappable: true)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            entryRowContent(entry, position: position, tappable: false)
        }
    }

    private func entryRowContent(_ entry: LeaderboardEntry, position: Int, tappable: Bool) -> some View {
        let metal = metalColor(position, hasData: entry.hasData)
        return HStack(spacing: DesignSystem.Spacing.md) {
            rankNumeral(position, hasData: entry.hasData, metal: metal)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(entry.displayName.isEmpty ? "@\(entry.username)" : entry.displayName)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)

                    if entry.isCurrentUser {
                        Text("You")
                            .font(AppFont.bold(10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tc.primary))
                    }
                }

                if !entry.displayName.isEmpty && !entry.username.isEmpty {
                    Text("@\(entry.username)")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textSecondary)
                }

                if entry.hasData {
                    secondaryBadges(entry)
                        .padding(.top, 1)
                }
            }

            Spacer()

            scoreColumn(entry)

            if tappable {
                Image(systemName: "chevron.right")
                    .font(AppFont.bold(12))
                    .foregroundColor(tc.textTertiary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: metal?.opacity(0.85)
                ?? (entry.isCurrentUser ? tc.primary : tc.primary.opacity(0.3)),
            fillColor: metal.map { tc.cardBackground.mix(with: $0, by: 0.16) }
                ?? (entry.isCurrentUser
                    ? tc.cardBackground.mix(with: tc.primary, by: 0.10)
                    : tc.cardBackground),
            // R6c: preserve retired heuristic — accent border only on own row without a rank-metal
            isSelected: metal == nil && entry.isCurrentUser
        )
        .overlay {
            if let metal, settings.isCleanUI {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(metal.opacity(0.55), lineWidth: 1.5)
            }
        }
        .opacity(entry.hasData ? 1.0 : 0.7)
    }

    /// Big position numeral; metal on the podium, crown over #1, dash for no-data.
    private func rankNumeral(_ position: Int, hasData: Bool, metal: Color?) -> some View {
        VStack(spacing: 1) {
            if hasData && position == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundColor(metal ?? DesignSystem.Colors.goldMid)
            }
            Text(hasData ? "\(position)" : "–")
                .font(AppFont.bold(hasData && position <= 3 ? 26 : 17))
                .foregroundColor(metal ?? (hasData ? tc.textSecondary : tc.textTertiary))
                .monospacedDigit()
        }
        .frame(width: 40)
    }

    /// The selected metric, emphasized. No-data rows show "no data yet".
    @ViewBuilder
    private func scoreColumn(_ entry: LeaderboardEntry) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if entry.hasData {
                switch viewModel.metric {
                case .rank:
                    Text(entry.displayRank)
                        .font(AppFont.bold(18))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    if let rr = entry.rr {
                        Text("\(rr) RR")
                            .font(AppFont.regular(10))
                            .foregroundColor(tc.textSecondary)
                            .monospacedDigit()
                    } else {
                        Text("rank")
                            .font(AppFont.regular(10))
                            .foregroundColor(tc.textSecondary)
                    }
                case .adherence:
                    Text("\(entry.weeklyGoalsMet)/7")
                        .font(AppFont.bold(22))
                        .foregroundColor(tc.textPrimary)
                        .monospacedDigit()
                    Text("days on goal")
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textSecondary)
                case .xp:
                    Text("\(entry.totalXP)")
                        .font(AppFont.bold(22))
                        .foregroundColor(tc.textPrimary)
                        .monospacedDigit()
                    Text("total XP")
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textSecondary)
                case .level:
                    Text("Lv \(entry.level)")
                        .font(AppFont.bold(22))
                        .foregroundColor(tc.textPrimary)
                        .monospacedDigit()
                    Text("level")
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textSecondary)
                }
            } else {
                Text("–")
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textTertiary)
                Text("no data yet")
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
            }
        }
    }

    /// The two non-selected metrics plus the rank, as small badges.
    @ViewBuilder
    private func secondaryBadges(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if viewModel.metric != .level {
                statBadge(icon: "star.fill", text: "Lv \(entry.level)", color: DesignSystem.Colors.growth)
            }
            if viewModel.metric != .xp {
                statBadge(icon: "bolt.fill", text: xpText(entry.totalXP), color: DesignSystem.Colors.energy)
            }
            if viewModel.metric != .adherence {
                statBadge(icon: "target", text: "\(entry.weeklyGoalsMet)/7", color: tc.primary)
            }
            // D3: the rank shield duplicates the score column on the Rank metric — hide it there.
            if viewModel.metric != .rank {
                statBadge(icon: "shield.fill", text: entry.displayRank, color: rankColor(entry.rank))
            }
        }
    }

    private func statBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(text)
                .font(AppFont.bold(10))
                .foregroundColor(tc.textSecondary)
        }
    }

    // MARK: - States

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

    private var inviteHint: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "person.badge.plus")
                .font(AppFont.regular(32))
                .foregroundColor(tc.textTertiary)
            Text("Invite members with your guild code")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Helpers

    private func xpText(_ xp: Int) -> String {
        xp >= 1000 ? String(format: "%.1fk", Double(xp) / 1000) : "\(xp)"
    }

    private func metalColor(_ position: Int, hasData: Bool) -> Color? {
        guard hasData else { return nil }
        switch position {
        case 1: return DesignSystem.Colors.goldMid
        case 2: return Color(hex: "#9CA3AF") // silver
        case 3: return Color(hex: "#CD7F32") // bronze
        default: return nil
        }
    }

    private func rankColor(_ rank: String) -> Color {
        switch rank {
        case Rank.stone.rawValue: return Color(hex: "#A8A29E")
        case Rank.copper.rawValue: return Color(hex: "#B87333")
        case Rank.iron.rawValue: return tc.textTertiary
        case Rank.gold.rawValue: return DesignSystem.Colors.goldMid
        case Rank.platinum.rawValue: return Color(hex: "#5EEAD4")
        case Rank.diamond.rawValue: return Color(hex: "#38BDF8")
        case Rank.sentinel.rawValue, Rank.prismatic.rawValue, Rank.zenith.rawValue:
            return Color(hex: "#38BDF8") // TODO: replace placeholder styling before public launch
        case "bronze": return Color(hex: "#CD7F32") // retired pre-RR-0a legacy string
        case "silver": return Color(hex: "#9CA3AF") // retired pre-RR-0a legacy string
        default: return tc.textTertiary
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
