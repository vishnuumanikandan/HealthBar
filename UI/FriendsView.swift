//
//  FriendsView.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import SwiftUI

/// Friends screen (Friend System Phase 2): friends list, incoming/outgoing
/// requests, and add-by-username. Pushed from the "Friends" row in ProfileView.
///
/// Guests see only a sign-in card — no friend listeners, reads, or writes run
/// for guest sessions.
struct FriendsView: View {

    // MARK: - Segments

    private enum Segment: String, CaseIterable {
        case friends = "Friends"
        case requests = "Requests"
        case add = "Add"
        case activity = "Activity"
    }

    // MARK: - Properties

    @State private var viewModel: FriendsViewModel

    /// Friend activity feed (Friend System Phase 7) — owned here so the shared
    /// pull-to-refresh can await it. Fetch-on-view, in memory; not part of
    /// FriendsViewModel's 2s polling.
    @State private var activityViewModel: ActivityFeedViewModel

    /// Retained to construct the FriendProfileView sheet presented from rows.
    private let coordinator: AppCoordinator

    /// Read-only — used solely to gate the guest empty-state.
    private let authService: any AuthService

    /// Triggers the existing guest → signup path (provided by ProfileView).
    private let onCreateAccount: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var segment: Segment = .friends

    /// Friend pending removal — drives the confirm dialog.
    @State private var friendToRemove: FriendsViewModel.FriendRow? = nil

    /// Friend whose read-only profile sheet is open (Friend System Phase 4).
    @State private var profileFriend: FriendsViewModel.FriendRow? = nil

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: FriendsViewModel(coordinator: coordinator))
        self._activityViewModel = State(initialValue: ActivityFeedViewModel(coordinator: coordinator))
        self.coordinator = coordinator
        self.authService = authService
        self.onCreateAccount = onCreateAccount
    }

    // MARK: - Body

    var body: some View {
        // R3a: no internal NavigationStack — FriendsView is pushed onto Home's stack.
        // Title/toolbar and the lifecycle modifiers below attach to this root so the
        // pushed presentation shows the same chrome.
        ZStack {
            tc.primaryBackground
                .ignoresSafeArea()

            if authService.isGuest {
                guestCard
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Friends")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .task {
            // Guests start no observation — the listener never runs for them either.
            guard !authService.isGuest else { return }
            await viewModel.observeChanges()
        }
        .onChange(of: viewModel.shouldShowRequestsSegment) { _, flag in
            if flag {
                segment = .requests
                viewModel.shouldShowRequestsSegment = false
            }
        }
        .confirmationDialog(
            "Remove Friend?",
            isPresented: Binding(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove \(friendToRemove?.displayName ?? "Friend")", role: .destructive) {
                if let friend = friendToRemove {
                    Task { await viewModel.remove(friendUid: friend.id) }
                }
                friendToRemove = nil
            }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        } message: {
            Text("This removes the friendship for both of you.")
        }
        .sheet(item: $profileFriend) { friend in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: friend.id,
                username: friend.username,
                displayName: friend.displayName,
                onRemoved: { Task { await viewModel.load() } }
            )
        }
    }

    // MARK: - Guest State

    private var guestCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(AppFont.regular(44))
                .foregroundColor(tc.textTertiary)

            Text("Sign in to add friends")
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text("Friends are synced to your account. Create a free account to find people by username and send requests.")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)

            AppButton(
                title: "Create Account",
                style: .primary,
                action: { onCreateAccount() }
            )
        }
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Main Content

    private var content: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            segmentControl
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    switch segment {
                    case .friends: friendsSection
                    case .requests: requestsSection
                    case .add: addFriendSection
                    case .activity:
                        ActivityFeedSection(
                            viewModel: activityViewModel,
                            coordinator: coordinator,
                            authService: authService
                        )
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .refreshable {
                // The feed is fetch-on-view and lives outside FriendsViewModel's
                // polling, so refresh whichever data the active segment shows.
                if segment == .activity {
                    await activityViewModel.refresh()
                } else {
                    await viewModel.refresh()
                }
            }
            // R2 §5: reserve the tab bar's height so the bottom of each segment clears the
            // translucent bar (the TabView's safeAreaInset doesn't reach this ScrollView).
            .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
        }
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(Segment.allCases, id: \.self) { item in
                segmentButton(item)
            }
        }
    }

    private func segmentButton(_ item: Segment) -> some View {
        let isSelected = segment == item
        return Button {
            segment = item
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(item.rawValue)
                    .font(AppFont.bold(14))
                    .foregroundColor(isSelected ? .white : tc.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Unread-style count on the Requests segment when incoming > 0
                if item == .requests && !viewModel.incomingRequests.isEmpty {
                    Text("\(viewModel.incomingRequests.count)")
                        .font(AppFont.bold(11))
                        .foregroundColor(isSelected ? tc.primary : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white : DesignSystem.Colors.danger)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .adaptivePill(
                borderColor: isSelected ? tc.primaryDark : tc.primary.opacity(0.3),
                fillColor: isSelected ? tc.primary : tc.cardBackground
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Friends Segment

    private var friendsSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if let error = viewModel.actionError {
                inlineError(error)
            }

            if viewModel.friends.isEmpty {
                emptyCard(
                    icon: "person.2",
                    title: "No friends yet",
                    message: "Find someone by their @username in the Add tab."
                )
            } else {
                ForEach(viewModel.friends) { friend in
                    friendRow(friend)
                }
            }
        }
    }

    /// Detail-rich friend card (Friend System Phase 4): rank-tinted initials
    /// avatar, identity, and published level/streak/rank. Tapping opens the
    /// read-only profile sheet; removal lives in the long-press menu and the
    /// profile sheet, keeping the card itself one clean tap target.
    private func friendRow(_ friend: FriendsViewModel.FriendRow) -> some View {
        let accent = friend.rank.map(rankColor) ?? tc.primary
        return Button {
            profileFriend = friend
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accent.opacity(0.16))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accent.opacity(0.45), lineWidth: 1.5)
                    Text(initials(for: friend))
                        .font(AppFont.bold(16))
                        .foregroundColor(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayName.isEmpty ? "@\(friend.username)" : friend.displayName)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)

                    if !friend.displayName.isEmpty {
                        Text("@\(friend.username)")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }

                    if let level = friend.level, let streak = friend.currentStreak, let rank = friend.rank {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            statBadge(icon: "star.fill", text: "Lv \(level)", color: DesignSystem.Colors.growth)
                            statBadge(icon: "flame.fill", text: "\(streak)", color: DesignSystem.Colors.energy)
                            statBadge(icon: "shield.fill", text: Rank.displayString(rr: friend.rr, legacyRank: rank), color: rankColor(rank))
                        }
                        .padding(.top, 1)
                    } else {
                        Text("No stats shared yet")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textTertiary)
                            .padding(.top, 1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: accent.opacity(0.35), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                friendToRemove = friend
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        }
    }

    private func initials(for friend: FriendsViewModel.FriendRow) -> String {
        let name = friend.displayName.isEmpty ? friend.username : friend.displayName
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
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

    private func rankColor(_ rank: String) -> Color {
        switch rank {
        case Rank.stone.rawValue: return Color(hex: "#A8A29E")
        case Rank.copper.rawValue: return Color(hex: "#B87333")
        case Rank.iron.rawValue: return tc.textTertiary
        case Rank.gold.rawValue: return DesignSystem.Colors.goldMid
        case Rank.platinum.rawValue: return Color(hex: "#5EEAD4")
        case Rank.diamond.rawValue: return Color(hex: "#38BDF8")
        case Rank.rankVII.rawValue, Rank.rankVIII.rawValue, Rank.rankIX.rawValue:
            return Color(hex: "#38BDF8") // TODO: replace placeholder styling before public launch
        case "bronze": return Color(hex: "#CD7F32") // retired pre-RR-0a legacy string
        case "silver": return Color(hex: "#9CA3AF") // retired pre-RR-0a legacy string
        default: return tc.textTertiary
        }
    }

    // MARK: - Requests Segment

    private var requestsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if let error = viewModel.actionError {
                inlineError(error)
            }

            if viewModel.incomingRequests.isEmpty && viewModel.outgoingRequests.isEmpty {
                emptyCard(
                    icon: "envelope",
                    title: "No requests",
                    message: "Incoming and sent friend requests show up here."
                )
            }

            if !viewModel.incomingRequests.isEmpty {
                sectionHeader("Incoming")
                ForEach(viewModel.incomingRequests) { request in
                    incomingRequestRow(request)
                }
            }

            if !viewModel.outgoingRequests.isEmpty {
                sectionHeader("Sent")
                ForEach(viewModel.outgoingRequests) { request in
                    outgoingRequestRow(request)
                }
            }
        }
    }

    private func incomingRequestRow(_ request: FriendsViewModel.RequestRow) -> some View {
        let isBusy = viewModel.pendingActionUids.contains(request.id)
        return HStack(spacing: DesignSystem.Spacing.md) {
            identityLabel(displayName: request.displayName ?? "", username: request.username)

            Spacer()

            Button {
                Task { await viewModel.accept(fromUid: request.id) }
            } label: {
                Text("Accept")
                    .font(AppFont.bold(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(borderColor: tc.primaryDark, fillColor: tc.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)

            Button {
                Task { await viewModel.decline(fromUid: request.id) }
            } label: {
                Text("Decline")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private func outgoingRequestRow(_ request: FriendsViewModel.RequestRow) -> some View {
        let isBusy = viewModel.pendingActionUids.contains(request.id)
        return HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("@\(request.username)")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)

                Text("Pending")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.cancel(toUid: request.id) }
            } label: {
                Text("Cancel")
                    .font(AppFont.bold(13))
                    .foregroundColor(DesignSystem.Colors.danger)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(
                        borderColor: DesignSystem.Colors.danger.opacity(0.5),
                        fillColor: DesignSystem.Colors.danger.opacity(0.1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Add Friend Segment (full user directory)

    private var addFriendSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            AuthTextField(
                label: "All users",
                placeholder: "Filter by @username",
                text: $viewModel.searchInput
            )

            if let error = viewModel.searchError {
                inlineError(error)
            }

            if let message = viewModel.searchSuccessMessage {
                Text(message)
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.directoryError {
                inlineError(error)
            }

            if viewModel.directory.isEmpty {
                emptyCard(
                    icon: "person.3",
                    title: "No users found",
                    message: "Users who have claimed a username show up here."
                )
            } else if viewModel.filteredDirectory.isEmpty {
                emptyCard(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "No usernames match that filter."
                )
            } else {
                ForEach(viewModel.filteredDirectory) { row in
                    directoryRow(row)
                }
            }
        }
    }

    private func directoryRow(_ row: FriendsViewModel.DirectoryRow) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text("@\(row.username)")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            Spacer()

            directoryActionButton(row)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// Renders the action matching the locally classified relationship:
    /// none → Add, outgoingPending → Pending (disabled),
    /// incomingPending → Accept, friends → Friends (disabled).
    @ViewBuilder
    private func directoryActionButton(_ row: FriendsViewModel.DirectoryRow) -> some View {
        let isBusy = viewModel.pendingActionUids.contains(row.id)
        switch row.state {
        case .none:
            Button {
                Task { await viewModel.addFriend(row) }
            } label: {
                Text("Add")
                    .font(AppFont.bold(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(borderColor: tc.primaryDark, fillColor: tc.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)

        case .outgoingPending:
            Text("Pending")
                .font(AppFont.bold(13))
                .foregroundColor(tc.textTertiary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)

        case .incomingPending:
            Button {
                Task { await viewModel.acceptFromDirectory(row) }
            } label: {
                Text("Accept")
                    .font(AppFont.bold(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(borderColor: tc.primaryDark, fillColor: tc.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)

        case .friends:
            Text("Friends")
                .font(AppFont.bold(13))
                .foregroundColor(tc.textTertiary)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
    }

    // MARK: - Shared Pieces

    private func identityLabel(displayName: String, username: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(displayName.isEmpty ? "@\(username)" : displayName)
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            if !displayName.isEmpty {
                Text("@\(username)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.bold(16))
            .foregroundColor(tc.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.regular(36))
                .foregroundColor(tc.textTertiary)

            Text(title)
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)

            Text(message)
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
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
