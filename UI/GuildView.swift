//
//  GuildView.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import SwiftUI
import UIKit

/// Guild screen (Guilds Prompt G1): create or join a guild, then view the roster
/// and (as owner) manage requests, members, settings, and disband. Presented as a
/// sheet from the "Guild" row in ProfileView.
///
/// Guests see only a sign-in card — no guild reads or writes run for guests.
struct GuildView: View {

    // MARK: - Properties

    @State private var viewModel: GuildViewModel

    /// Retained to build the CreateGuildSheet, EditGuildSettingsSheet, and
    /// FriendProfileView presented from this screen.
    private let coordinator: AppCoordinator

    /// Read-only — gates the guest sign-in card.
    private let authService: any AuthService

    /// Triggers the existing guest → signup path (provided by ProfileView).
    private let onCreateAccount: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var showingCreate = false

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: GuildViewModel(coordinator: coordinator))
        self.coordinator = coordinator
        self.authService = authService
        self.onCreateAccount = onCreateAccount
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground
                    .ignoresSafeArea()

                if authService.isGuest {
                    guestCard
                } else {
                    switch viewModel.stage {
                    case .loading:
                        ProgressView()
                            .scaleEffect(1.4)
                    case .notInGuild:
                        notInGuildContent
                    case .inGuild:
                        GuildDetailView(viewModel: viewModel, coordinator: coordinator)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // R7c §4/§5: no nav-bar title on the tab root (the in-content head is the header), and
            // the "Done" button is gone — it dismissed the pre-R6b Profile SHEET mount and did
            // nothing at all in the tab mount. Nothing else lived in this toolbar, so the empty bar
            // is hidden. Pushed destinations (chat, roster, leaderboard) keep their own bars.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCreate) {
                CreateGuildSheet(coordinator: coordinator) {
                    Task { await viewModel.load() }
                }
            }
        }
        .task {
            guard !authService.isGuest else { return }
            await viewModel.load()
        }
    }

    // MARK: - Guest State

    private var guestCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "person.3.fill")
                .font(AppFont.regular(44))
                .foregroundColor(tc.textTertiary)

            Text("Sign in to join a guild")
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text("Guilds are synced to your account. Create a free account to start or join a guild with friends.")
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

    // MARK: - Not In A Guild

    private var joinCodeBinding: Binding<String> {
        Binding(get: { viewModel.joinCode }, set: { viewModel.joinCode = $0 })
    }

    private var directorySearchBinding: Binding<String> {
        Binding(get: { viewModel.directorySearch }, set: { viewModel.directorySearch = $0 })
    }

    private var notInGuildContent: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Intro
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(AppFont.regular(44))
                        .foregroundColor(tc.primary)
                    Text("Join the guild life")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                    Text("Team up with others. Create your own guild or join one with its code.")
                        .font(AppFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.lg)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)

                // Create
                AppButton(
                    title: "Create a Guild",
                    style: .primary,
                    action: { showingCreate = true },
                    icon: "plus"
                )

                // Pending request banner (session-local)
                if let pending = viewModel.pendingRequestCode {
                    pendingRequestCard(code: pending)
                }

                // Join with code
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Join with a Code")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)

                    AuthTextField(
                        label: "Guild code",
                        placeholder: "e.g. K7P29QXM",
                        text: joinCodeBinding
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)

                    if let error = viewModel.joinError {
                        inlineError(error)
                    }

                    AppButton(
                        title: "Join",
                        style: .secondary,
                        action: { Task { await viewModel.join() } },
                        isLoading: viewModel.isJoining,
                        isDisabled: viewModel.joinCode.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)

                // Browse (R7d)
                directorySection
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Directory (R7d)

    /// The browsable directory of joinable guilds. `private` guilds are absent by
    /// construction — the rules' `list` clause excludes them, so they never reach the client.
    private var directorySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("OPEN GUILDS")
                .font(AppFont.display(14))
                .foregroundColor(tc.textSecondary)

            AuthTextField(
                label: "Browse",
                placeholder: "Search guilds",
                text: directorySearchBinding
            )
            .autocorrectionDisabled(true)

            if let error = viewModel.directoryError {
                inlineError(error)
            }

            directoryBody
        }
    }

    @ViewBuilder
    private var directoryBody: some View {
        if viewModel.isLoadingDirectory {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        } else if viewModel.filteredGuildDirectory.isEmpty {
            Text(viewModel.guildDirectory.isEmpty ? "No open guilds yet" : "No guilds match that search")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        } else {
            // One card, hairline-separated rows (the R4b ladder-row anatomy) — the directory
            // is one list, not a stack of per-guild cards.
            VStack(spacing: 0) {
                let rows = viewModel.filteredGuildDirectory
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    directoryRow(row, isLast: index == rows.count - 1)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
    }

    private func directoryRow(_ row: GuildViewModel.GuildDirectoryRow, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)

                    if let description = row.description, !description.isEmpty {
                        Text(description)
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    policyPill(row.joinPolicy)
                }

                Spacer(minLength: DesignSystem.Spacing.sm)

                directoryAction(row)
            }
            .padding(.vertical, DesignSystem.Spacing.md)

            if !isLast {
                Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
            }
        }
    }

    /// Join (open) · Request (request-policy) · Requested (this session's pending request).
    /// Every action is gated on the single `isJoining` flag — one join at a time.
    @ViewBuilder
    private func directoryAction(_ row: GuildViewModel.GuildDirectoryRow) -> some View {
        if row.id == viewModel.pendingRequestCode {
            Text("Requested")
                .font(AppFont.bold(13))
                .foregroundColor(tc.textTertiary)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        } else {
            Button {
                Task { await viewModel.joinFromDirectory(row) }
            } label: {
                Text(row.isRequestPolicy ? "Request" : "Join")
                    .font(AppFont.bold(13))
                    .foregroundColor(row.isRequestPolicy ? tc.textSecondary : .white)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(
                        borderColor: row.isRequestPolicy ? tc.primary.opacity(0.3) : tc.primaryDark,
                        fillColor: row.isRequestPolicy ? tc.cardBackground : tc.primary
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isJoining)
            .opacity(viewModel.isJoining ? 0.5 : 1.0)
        }
    }

    /// The in-guild header badge's style, on a directory row. (`inlineError` is likewise
    /// mirrored across these two structs — the file's existing convention.)
    ///
    /// Exhaustive over the three policies. `private` cannot appear here (the rules' `list`
    /// clause excludes it), but it is mapped rather than folded into a default that would
    /// silently label it "Request".
    private func policyPill(_ joinPolicy: String) -> some View {
        let icon: String
        let label: String
        switch joinPolicy {
        case "open":     icon = "lock.open.fill";  label = "Open"
        case "private":  icon = "lock.fill";       label = "Private"
        default:         icon = "hand.raised.fill"; label = "Request"
        }
        return HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(AppFont.bold(11))
        }
        .foregroundColor(tc.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.primary.opacity(0.08))
    }

    private func pendingRequestCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "hourglass")
                    .foregroundColor(tc.primary)
                Text("Request sent")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
            }
            Text("Your request to join \(code) is waiting for the owner's approval.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)

            Button {
                Task { await viewModel.cancelPendingRequest() }
            } label: {
                Text("Cancel request")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
    }

    // MARK: - Shared Pieces

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

// MARK: - Guild Detail View

/// The in-guild experience: header, owner-only pending requests, roster, and
/// member/owner actions. Shares the parent's GuildViewModel.
struct GuildDetailView: View {

    let viewModel: GuildViewModel
    let coordinator: AppCoordinator

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Action confirmations / sheets
    @State private var showLeaveConfirm = false
    @State private var showDisbandConfirm = false
    @State private var memberToKick: GuildViewModel.MemberRow? = nil
    @State private var profileMember: GuildViewModel.MemberRow? = nil
    @State private var showingEdit = false
    @State private var didCopyCode = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                if let guild = viewModel.guild {
                    headerCard(guild)
                }

                leaderboardLink

                chatLink

                if let error = viewModel.actionError {
                    inlineError(error)
                }

                // Owner: pending requests (request-policy guilds only).
                if viewModel.isOwner && !viewModel.requests.isEmpty {
                    requestsSection
                }

                rosterSection

                actionsSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            "Leave Guild?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Guild", role: .destructive) {
                Task { await viewModel.leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need the code (or a new request) to rejoin.")
        }
        .confirmationDialog(
            "Disband Guild?",
            isPresented: $showDisbandConfirm,
            titleVisibility: .visible
        ) {
            Button("Disband Guild", role: .destructive) {
                Task { await viewModel.disband() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the guild for everyone. This can't be undone.")
        }
        .confirmationDialog(
            "Remove Member?",
            isPresented: Binding(
                get: { memberToKick != nil },
                set: { if !$0 { memberToKick = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove \(memberToKick?.title ?? "Member")", role: .destructive) {
                if let member = memberToKick {
                    Task { await viewModel.kick(member) }
                }
                memberToKick = nil
            }
            Button("Cancel", role: .cancel) { memberToKick = nil }
        } message: {
            Text("They'll be removed from the guild and can rejoin later.")
        }
        .sheet(item: $profileMember) { member in
            FriendProfileView(
                coordinator: coordinator,
                friendUid: member.id,
                username: member.username,
                displayName: member.displayName
            )
        }
        .sheet(isPresented: $showingEdit) {
            if let guild = viewModel.guild {
                EditGuildSettingsSheet(coordinator: coordinator, guild: guild) {
                    Task { await viewModel.load() }
                }
            }
        }
    }

    // MARK: - Header

    private func headerCard(_ guild: GuildDTO) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text(guild.name)
                .font(AppFont.bold(24))
                .foregroundColor(tc.textPrimary)
                .multilineTextAlignment(.center)

            // Join policy + member count. R7d: exhaustive over the three policies — the
            // binary ternary this replaced would have labelled a `private` guild
            // "Request to join", which is the one thing it isn't.
            HStack(spacing: DesignSystem.Spacing.sm) {
                metaPill(icon: policyIcon(guild.joinPolicy), text: policyLabel(guild.joinPolicy))
                metaPill(
                    icon: "person.2.fill",
                    text: "\(viewModel.memberCount) member\(viewModel.memberCount == 1 ? "" : "s")"
                )
            }

            if let description = guild.description, !description.isEmpty {
                Text(description)
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Code with copy + share
            if let code = guild.id {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Invite code")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(code)
                            .font(AppFont.bold(20))
                            .foregroundColor(tc.textPrimary)
                            .tracking(2)

                        Button {
                            UIPasteboard.general.string = code
                            withAnimation { didCopyCode = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { didCopyCode = false }
                            }
                        } label: {
                            Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                                .font(AppFont.bold(14))
                                .foregroundColor(tc.primary)
                        }
                        .buttonStyle(PlainButtonStyle())

                        ShareLink(item: "Join my HealthBar guild \"\(guild.name)\" with code \(code)") {
                            Image(systemName: "square.and.arrow.up")
                                .font(AppFont.bold(14))
                                .foregroundColor(tc.primary)
                        }
                    }
                    if didCopyCode {
                        Text("Copied!")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.primary)
                    }
                }
                .padding(.top, DesignSystem.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
    }

    private func policyIcon(_ joinPolicy: String) -> String {
        switch joinPolicy {
        case "open":    return "lock.open.fill"
        case "private": return "lock.fill"
        default:        return "hand.raised.fill"
        }
    }

    private func policyLabel(_ joinPolicy: String) -> String {
        switch joinPolicy {
        case "open":    return "Open"
        case "private": return "Private"
        default:        return "Request to join"
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppFont.bold(11))
        }
        .foregroundColor(tc.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .adaptivePill(borderColor: tc.primary.opacity(0.3), fillColor: tc.primary.opacity(0.08))
    }

    // MARK: - Leaderboard Entry

    private var leaderboardLink: some View {
        NavigationLink {
            GuildLeaderboardView(coordinator: coordinator)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "trophy.fill")
                    .font(AppFont.bold(18))
                    .foregroundColor(DesignSystem.Colors.goldMid)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboard")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    Text("Rank members by adherence, XP, or level")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: DesignSystem.Colors.goldMid.opacity(0.4), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var chatLink: some View {
        NavigationLink {
            GuildChatView(coordinator: coordinator, code: viewModel.guild?.id ?? "", isOwner: viewModel.isOwner)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(AppFont.bold(18))
                    .foregroundColor(tc.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    Text("Talk with your guild in real time")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Requests (owner)

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("Pending Requests")
            ForEach(viewModel.requests) { request in
                requestRow(request)
            }
        }
    }

    private func requestRow(_ request: GuildViewModel.RequestRow) -> some View {
        let isBusy = viewModel.pendingActionUids.contains(request.id)
        return HStack(spacing: DesignSystem.Spacing.md) {
            identityLabel(displayName: request.displayName, username: request.username)

            Spacer()

            Button {
                Task { await viewModel.approve(request) }
            } label: {
                Text("Approve")
                    .font(AppFont.bold(13))
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .adaptivePill(borderColor: tc.primaryDark, fillColor: tc.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)

            Button {
                Task { await viewModel.deny(request) }
            } label: {
                Text("Deny")
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

    // MARK: - Roster

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionHeader("Members")
            ForEach(viewModel.members) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: GuildViewModel.MemberRow) -> some View {
        let tappable = member.isFriend && !member.isMe
        let canKick = viewModel.isOwner && !member.isMe && !member.isOwnerRole
        return Button {
            if tappable { profileMember = member }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tc.primary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tc.primary.opacity(0.45), lineWidth: 1.5)
                    Text(initials(for: member))
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.primary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(member.title)
                            .font(AppFont.bold(16))
                            .foregroundColor(tc.textPrimary)
                            .lineLimit(1)
                        if member.isMe {
                            tag("You", color: tc.textTertiary)
                        }
                    }
                    if !member.displayName.isEmpty {
                        Text("@\(member.username)")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }
                }

                Spacer()

                if member.isOwnerRole {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                        Text("Owner")
                            .font(AppFont.bold(10))
                    }
                    .foregroundColor(DesignSystem.Colors.goldMid)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .adaptivePill(borderColor: DesignSystem.Colors.goldMid.opacity(0.5),
                                  fillColor: DesignSystem.Colors.goldMid.opacity(0.12))
                } else if tappable {
                    Image(systemName: "chevron.right")
                        .font(AppFont.bold(13))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!tappable && !canKick)
        .contextMenu {
            if canKick {
                Button(role: .destructive) {
                    memberToKick = member
                } label: {
                    Label("Remove from Guild", systemImage: "person.badge.minus")
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if viewModel.isOwner {
                AppButton(
                    title: "Edit Settings",
                    style: .secondary,
                    action: { showingEdit = true },
                    icon: "slider.horizontal.3"
                )
                Button {
                    showDisbandConfirm = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        if viewModel.isActing { ProgressView().scaleEffect(0.8) }
                        Text("Disband Guild")
                            .font(AppFont.bold(16))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(
                        borderColor: DesignSystem.Colors.danger.opacity(0.5),
                        fillColor: DesignSystem.Colors.danger.opacity(0.08)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isActing)
            } else {
                Button {
                    showLeaveConfirm = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        if viewModel.isActing { ProgressView().scaleEffect(0.8) }
                        Text("Leave Guild")
                            .font(AppFont.bold(16))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignSystem.Spacing.md)
                    .adaptiveCard(
                        borderColor: DesignSystem.Colors.danger.opacity(0.5),
                        fillColor: DesignSystem.Colors.danger.opacity(0.08)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isActing)
            }
        }
        .padding(.top, DesignSystem.Spacing.sm)
    }

    // MARK: - Shared Pieces

    private func initials(for member: GuildViewModel.MemberRow) -> String {
        let name = member.displayName.isEmpty ? member.username : member.displayName
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFont.bold(9))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

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
