//
//  ActivityFeedSection.swift
//  HealthBar
//
//  Created by Claude on 6/11/26.
//

import SwiftUI

/// View model for the friend activity feed (Friend System Phase 7/8).
///
/// Holds the merged feed and the owner's milestone receipts IN MEMORY only —
/// fetched through the coordinator on segment appearance and on pull-to-refresh,
/// never persisted. No listeners; staleness between refreshes is acceptable
/// (same fetch-on-view model as the leaderboard). Owned by FriendsView so the
/// shared pull-to-refresh can await it.
@Observable
@MainActor
final class ActivityFeedViewModel {

    private let coordinator: AppCoordinator

    /// Merged, display-ready friend rows (unresolved events already dropped by
    /// the coordinator), newest first, with cheer state populated.
    var items: [FeedItem] = []

    /// The owner's own recent events with cheers received (Phase 8). Empty ⇒
    /// the "Your milestones" strip is hidden.
    var myMilestones: [OwnEventItem] = []

    var isLoading: Bool = false

    /// True once any load has finished — separates "still loading" from
    /// "loaded and there's simply no activity."
    private(set) var hasLoaded: Bool = false

    /// Per-row cheer writes in flight, keyed on the COMPOSITE FeedItem identity
    /// (`friendUid + "_" + eventId`) — never the eventId alone, since two friends
    /// at the same milestone share a deterministic event id. Serializes taps.
    var cheerInFlight: Set<String> = []

    /// Brief inline error from a failed cheer/uncheer write; the item state is
    /// left unchanged (never optimistic-before-write).
    var cheerError: String? = nil

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Loads the friends' feed and the owner's milestone strip CONCURRENTLY —
    /// neither blocks the other. An empty result is a valid state, never an error.
    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        async let feed = coordinator.loadActivityFeed()
        async let mine = coordinator.loadMyMilestones()
        items = await feed
        myMilestones = await mine
    }

    /// Cheer / uncheer a friend's event. Serialized per row by `cheerInFlight`.
    /// The in-memory item flips ONLY after the write succeeds (never optimistic);
    /// on failure the state is unchanged and a brief inline error is shown.
    func toggleCheer(_ item: FeedItem) async {
        guard !cheerInFlight.contains(item.id) else { return }
        cheerInFlight.insert(item.id)
        cheerError = nil
        defer { cheerInFlight.remove(item.id) }

        // TESTING ONLY — the placeholder friend isn't a real Firestore friend, so
        // a real cheer write would be permission-denied. Toggle locally so the
        // demo stays interactive. Grep "PlaceholderFriend" to remove.
        if item.friendUid == PlaceholderFriend.uid {
            applyCheer(itemId: item.id, nowCheered: !item.didCheer)
            return
        }

        do {
            if item.didCheer {
                try await coordinator.uncheer(ownerUid: item.friendUid, eventId: item.eventId)
                applyCheer(itemId: item.id, nowCheered: false)
            } else {
                try await coordinator.cheer(ownerUid: item.friendUid, eventId: item.eventId)
                applyCheer(itemId: item.id, nowCheered: true)
            }
        } catch {
            cheerError = "Couldn't update your cheer. Try again."
        }
    }

    /// Applies a confirmed cheer result to the in-memory item, idempotently
    /// (re-finds by id after the await, guards against double-applying).
    private func applyCheer(itemId: String, nowCheered: Bool) {
        guard let i = items.firstIndex(where: { $0.id == itemId }) else { return }
        if nowCheered && !items[i].didCheer {
            items[i].didCheer = true
            items[i].cheerCount += 1
        } else if !nowCheered && items[i].didCheer {
            items[i].didCheer = false
            items[i].cheerCount = max(0, items[i].cheerCount - 1)
        }
    }
}

/// The friend activity feed, rendered as the Activity segment inside the Friends
/// tab's existing scroll container — a `LazyVStack` of event rows, NO nested
/// scroll (same rule as the Home leaderboard section).
///
/// Pinned at the top is the owner's "Your milestones" receipts strip (Phase 8),
/// hidden entirely when they have no events. Each friend row carries a 💪 cheer
/// button and, below the event, who has cheered. Tapping the row body opens the
/// friend's read-only profile (Phase 4). Guests never reach this (the whole tab
/// is gated upstream) and never trigger a fetch.
struct ActivityFeedSection: View {

    /// Owned by FriendsView; held as a plain reference so Observation still
    /// tracks the properties this view reads.
    let viewModel: ActivityFeedViewModel

    /// Retained to construct the FriendProfileView sheet (Phase 4).
    private let coordinator: AppCoordinator

    /// Read-only — guests never fetch (the tab is already gated upstream).
    private let authService: any AuthService

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Friend whose profile sheet is open, keyed by the tapped event's row.
    @State private var selectedFriend: FeedItem? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    init(viewModel: ActivityFeedViewModel, coordinator: AppCoordinator, authService: any AuthService) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        self.authService = authService
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Owner receipts strip — pinned above the friends feed, hidden when
            // the owner has no events.
            if !viewModel.myMilestones.isEmpty {
                milestonesStrip
            }

            if let error = viewModel.cheerError {
                inlineError(error)
            }

            if viewModel.isLoading && !viewModel.hasLoaded {
                loadingCard
            } else if viewModel.items.isEmpty {
                emptyCard
            } else {
                // LazyVStack, never a nested ScrollView/List: the page scrolls as one.
                LazyVStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.items) { item in
                        row(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fires once per segment appearance (the view only exists while the
        // Activity segment is selected); cancels on disappear.
        .task {
            guard !authService.isGuest else { return }
            await viewModel.refresh()
        }
        .sheet(item: $selectedFriend) { item in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: item.friendUid,
                username: item.username,
                displayName: item.displayName
            )
        }
    }

    // MARK: - "Your milestones" strip (owner receipts)

    private var milestonesStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Your milestones")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            ForEach(viewModel.myMilestones) { own in
                ownRow(own)
            }
        }
    }

    /// Owner's own event: resolved text + time + cheer receipts. No cheer
    /// button — self-cheer is impossible.
    private func ownRow(_ own: OwnEventItem) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            emojiTile(own.emoji)

            VStack(alignment: .leading, spacing: 3) {
                Text(own.resolvedText.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Milestone")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(2)

                secondaryLine(date: own.createdAt, cheerCount: own.cheerCount, names: own.recentCheererNames)
            }

            Spacer(minLength: DesignSystem.Spacing.sm)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.35), fillColor: tc.cardBackground)
    }

    // MARK: - Friend feed row

    private func row(_ item: FeedItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Tapping the row body opens the friend's profile (Phase 4).
            Button {
                selectedFriend = item
            } label: {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    emojiTile(item.emoji)

                    VStack(alignment: .leading, spacing: 3) {
                        // "Name <did something>" — name bold, action regular.
                        (
                            Text(item.name)
                                .font(AppFont.bold(15))
                                .foregroundColor(tc.textPrimary)
                            + Text(" \(item.resolvedText ?? "")")
                                .font(AppFont.regular(15))
                                .foregroundColor(tc.textSecondary)
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                        secondaryLine(date: item.createdAt, cheerCount: item.cheerCount, names: item.recentCheererNames)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())

            cheerButton(item)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// Trailing 💪 button: filled when the viewer has cheered; count hidden at 0;
    /// disabled (spinner) while its own write is in flight.
    private func cheerButton(_ item: FeedItem) -> some View {
        let inFlight = viewModel.cheerInFlight.contains(item.id)
        return Button {
            Task { await viewModel.toggleCheer(item) }
        } label: {
            HStack(spacing: 4) {
                if inFlight {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(item.didCheer ? .white : tc.primary)
                } else {
                    Text("💪")
                        .font(AppFont.regular(14))
                        .opacity(item.didCheer ? 1 : 0.5)
                }

                if item.cheerCount > 0 {
                    Text("\(item.cheerCount)")
                        .font(AppFont.bold(13))
                        .foregroundColor(item.didCheer ? .white : tc.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .adaptivePill(
                borderColor: item.didCheer ? tc.primaryDark : tc.primary.opacity(0.3),
                fillColor: item.didCheer ? tc.primary : tc.cardBackground
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(inFlight)
    }

    // MARK: - Shared pieces

    private func emojiTile(_ emoji: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(tc.primary.opacity(0.12))
            Text(emoji)
                .font(AppFont.regular(22))
        }
        .frame(width: 44, height: 44)
    }

    /// "2h ago" plus, when cheered, "· 💪 Sam and 2 others".
    private func secondaryLine(date: Date, cheerCount: Int, names: [String]) -> some View {
        HStack(spacing: 4) {
            Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                .font(AppFont.regular(11))
                .foregroundColor(tc.textTertiary)

            if cheerCount > 0, !names.isEmpty {
                Text("· 💪 \(cheererSummary(names: names, total: cheerCount))")
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textSecondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
    }

    /// "Sam", "Sam and 1 other", "Sam, Priya and 3 others" — names from the
    /// snapshots, total from the (authoritative) cheer count.
    private func cheererSummary(names: [String], total: Int) -> String {
        guard let first = names.first else { return "\(total)" }
        let remainder = total - 1
        if remainder <= 0 { return first }
        return "\(first) and \(remainder) other\(remainder == 1 ? "" : "s")"
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

    // MARK: - Loading / Empty States

    private var loadingCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .tint(tc.primary)

            Text("Loading activity…")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.xl)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var emptyCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(AppFont.regular(36))
                .foregroundColor(tc.textTertiary)

            Text("No activity yet")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            Text("Your friends' milestones will show up here.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }
}
