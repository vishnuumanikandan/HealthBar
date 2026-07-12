//
//  FriendProfileView.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import SwiftUI

/// Read-only friend profile sheet (Friend System Phase 4): rank, level,
/// streaks, member-since, weekly adherence, and the badge grid — all rendered
/// from the friend's published `public/stats` projection.
///
/// Presented from FriendsView rows and LeaderboardView rows. While stats load,
/// the local Friend snapshot identity shows immediately; a friend who hasn't
/// published renders a "hasn't shared their stats yet" state, not an error.
struct FriendProfileView: View {

    // MARK: - Properties

    @State private var viewModel: FriendProfileViewModel

    /// Called after a successful removal, once the sheet has dismissed —
    /// lets the presenter refresh its list immediately.
    private let onRemoved: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @Environment(\.dismiss) private var dismiss

    @State private var showRemoveConfirm = false

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        friendUid: String,
        username: String,
        displayName: String,
        onRemoved: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: FriendProfileViewModel(
            coordinator: coordinator,
            friendUid: friendUid,
            username: username,
            displayName: displayName
        ))
        self.onRemoved = onRemoved
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        identityHeader

                        if viewModel.isLoading && !viewModel.hasLoaded {
                            loadingCard
                        } else if let error = viewModel.loadError {
                            errorCard(error)
                        } else if let stats = viewModel.stats {
                            statsContent(stats)
                        } else {
                            noStatsCard
                        }

                        // "You vs. them" — inline, below the profile content.
                        // Only appears once the friend's stats are loaded
                        // (canCompare gates on that); collapses on toggle.
                        comparisonSection

                        removeFriendSection
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.regular(20))
                            .foregroundColor(tc.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            "Remove Friend?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove \(viewModel.displayName.isEmpty ? "@\(viewModel.username)" : viewModel.displayName)", role: .destructive) {
                Task {
                    // Await completion — dismiss only on success; a failure
                    // keeps the sheet open with the error surfaced.
                    if await viewModel.removeFriend() {
                        dismiss()
                        onRemoved()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the friendship for both of you.")
        }
    }

    // MARK: - Identity Header

    /// The friend's accent color: their rank color once stats arrive, the
    /// theme primary while loading / unpublished. Tints the avatar, pill,
    /// and header border so each profile carries its owner's rank identity.
    private var accent: Color {
        guard let rank = viewModel.stats?.rank else { return tc.primary }
        return rankColor(rank)
    }

    private var initials: String {
        let name = viewModel.displayName.isEmpty ? viewModel.username : viewModel.displayName
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Always visible — identity comes from the local Friend snapshot until
    /// the published projection (if any) replaces it.
    private var identityHeader: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(accent.opacity(0.16))
                RoundedRectangle(cornerRadius: 18)
                    .stroke(accent.opacity(0.5), lineWidth: 2)
                Text(initials)
                    .font(AppFont.bold(26))
                    .foregroundColor(accent)
            }
            .frame(width: 68, height: 68)
            .shadow(color: accent.opacity(0.35), radius: 14, x: 0, y: 0)
            .padding(.bottom, DesignSystem.Spacing.xs)

            Text(viewModel.displayName.isEmpty ? "@\(viewModel.username)" : viewModel.displayName)
                .font(AppFont.bold(28))
                .foregroundColor(tc.textPrimary)
                .multilineTextAlignment(.center)

            if !viewModel.displayName.isEmpty {
                Text("@\(viewModel.username)")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }

            if let rankRaw = viewModel.stats?.rank {
                rankPill(rankRaw)
                    .padding(.top, 2)
            }

            if let joinedAt = viewModel.stats?.joinedAt {
                Text("Member since \(joinedAt.formatted(.dateTime.month(.abbreviated).year()))")
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textTertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.lg)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: accent.opacity(0.4), fillColor: tc.cardBackground)
    }

    private func rankPill(_ rankRaw: String) -> some View {
        let color = rankColor(rankRaw)
        let title = Rank.displayString(rr: viewModel.stats?.rr, legacyRank: rankRaw)
        return HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "shield.fill")
                .font(.system(size: 13))
                .foregroundColor(color)

            Text(title)
                .font(AppFont.bold(14))
                .foregroundColor(tc.textPrimary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 6)
        .adaptivePill(borderColor: color.opacity(0.55), fillColor: color.opacity(0.14))
    }

    // MARK: - Stats Content

    private func statsContent(_ stats: PublicStatsDTO) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            statRow(stats)
            weekCard(stats)
            badgesSection(stats)
        }
    }

    /// Level / current streak / longest streak as three equal tiles.
    private func statRow(_ stats: PublicStatsDTO) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            statTile(
                icon: "star.fill",
                iconColor: DesignSystem.Colors.growth,
                value: "\(stats.level)",
                label: "Level"
            )
            statTile(
                icon: "flame.fill",
                iconColor: DesignSystem.Colors.energy,
                value: "\(stats.currentStreak)",
                label: "Streak"
            )
            statTile(
                icon: "trophy.fill",
                iconColor: DesignSystem.Colors.goldMid,
                value: "\(stats.longestStreak ?? 0)",
                label: "Best"
            )
        }
    }

    private func statTile(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.regular(15))
                .foregroundColor(iconColor)

            Text(value)
                .font(AppFont.bold(28))
                .foregroundColor(tc.textPrimary)
                .monospacedDigit()

            Text(label)
                .font(AppFont.regular(11))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// Weekly adherence as a 7-segment meter — same metric as the leaderboard,
    /// rendered as filled day blocks instead of a text row.
    private func weekCard(_ stats: PublicStatsDTO) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("This week")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)

                Spacer()

                Text("\(stats.weeklyGoalsMet)/7 days · \(Int((stats.weeklyAdherence * 100).rounded()))%")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
                    .monospacedDigit()
            }

            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(0..<7, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day < stats.weeklyGoalsMet ? tc.primary : tc.primary.opacity(0.14))
                        .frame(height: 12)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Badges

    private func badgesSection(_ stats: PublicStatsDTO) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Badges")
                    .font(AppFont.bold(18))
                    .foregroundColor(tc.textPrimary)

                Spacer()

                // The published badgeCount is the source of truth — an unknown
                // (removed) badge ID is dropped from the grid but still counts.
                Text("\(viewModel.publishedBadgeCount)/\(viewModel.allBadges.count)")
                    .font(AppFont.bold(13))
                    .foregroundColor(DesignSystem.Colors.goldMid)
                    .monospacedDigit()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.sm) {
                ForEach(viewModel.allBadges) { badge in
                    let earned = viewModel.earnedBadgeIdSet.contains(badge.id)

                    VStack(spacing: DesignSystem.Spacing.xs) {
                        Text(earned ? badge.emoji : "🔒")
                            .font(AppFont.regular(earned ? 32 : 24))
                            .opacity(earned ? 1.0 : 0.3)
                            .frame(height: 38)

                        Text(badge.title)
                            .font(AppFont.regular(11))
                            .foregroundColor(earned ? tc.textPrimary : tc.textTertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .adaptiveCard(
                        borderColor: earned
                            ? DesignSystem.Colors.goldMid.opacity(0.55)
                            : tc.primary.opacity(0.18),
                        // Opaque mix, not alpha — pixelCard composites the
                        // fill over its border base, so alpha bleeds gold.
                        fillColor: earned
                            ? tc.cardBackground.mix(with: DesignSystem.Colors.goldMid, by: 0.10)
                            : tc.cardBackground
                    )
                }
            }
        }
    }

    // MARK: - Comparison (Friend System Phase 6)

    /// The inline "you vs. them" affordance. Rendered only when `canCompare`
    /// (friend stats loaded + not guest); when the friend hasn't published,
    /// `canCompare` is false and the affordance is hidden — `noStatsCard` above
    /// already explains why there's nothing to compare.
    @ViewBuilder
    private var comparisonSection: some View {
        if viewModel.canCompare {
            VStack(spacing: DesignSystem.Spacing.sm) {
                compareButton

                if let error = viewModel.compareError {
                    compareErrorRow(error)
                }

                if viewModel.showComparison,
                   let mine = viewModel.myStats,
                   let theirs = viewModel.stats {
                    StatComparisonView(mine: mine, theirs: theirs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.showComparison)
        }
    }

    private var compareButton: some View {
        Button {
            Task { await viewModel.toggleComparison() }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.isBuildingMine {
                    ProgressView()
                        .tint(tc.primary)
                } else {
                    Image(systemName: "chart.bar.xaxis")
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.primary)
                }

                Text(viewModel.showComparison ? "Hide comparison" : "Compare stats")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)

                Spacer()

                if !viewModel.isBuildingMine {
                    Image(systemName: viewModel.showComparison ? "chevron.up" : "chevron.down")
                        .font(AppFont.bold(12))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isBuildingMine)
    }

    private func compareErrorRow(_ message: String) -> some View {
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

    // MARK: - Loading / Empty / Error States

    private var loadingCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .tint(tc.primary)

            Text("Loading stats…")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var noStatsCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "chart.bar")
                .font(AppFont.regular(36))
                .foregroundColor(tc.textTertiary)

            Text("Nothing shared yet")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            Text("@\(viewModel.username) hasn't shared their stats yet.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(AppFont.regular(28))
                .foregroundColor(DesignSystem.Colors.danger)

            Text(message)
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)

            AppButton(
                title: "Retry",
                style: .secondary,
                action: {
                    Task { await viewModel.load() }
                }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: DesignSystem.Colors.danger.opacity(0.4), fillColor: tc.cardBackground)
    }

    // MARK: - Remove Friend

    /// Quiet text action — removal is rare, it shouldn't compete with the
    /// profile content. The confirmation dialog carries the destructive weight.
    private var removeFriendSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if let error = viewModel.removeError {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.danger)

                    Text(error)
                        .font(AppFont.regular(12))
                        .foregroundColor(DesignSystem.Colors.danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showRemoveConfirm = true
            } label: {
                Text(viewModel.isRemoving ? "Removing…" : "Remove Friend")
                    .font(AppFont.bold(13))
                    .foregroundColor(DesignSystem.Colors.danger.opacity(0.85))
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isRemoving)
        }
        .padding(.top, DesignSystem.Spacing.sm)
    }

    // MARK: - Colors

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
}
