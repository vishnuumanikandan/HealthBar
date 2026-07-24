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
            // TUT-1b visitGuild detection (member mode, Decision 4/5) — a load that resolves to
            // the in-guild stage means the member is viewing GuildDetailView's memberBody.
            // Non-members land on the directory and complete via the spectator path instead.
            if case .inGuild = viewModel.stage,
               TutorialProgress.shared.shouldAttempt(TutorialCatalog.visitGuildId) {
                Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.visitGuildId) }
            }
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

            if let confirmation = viewModel.reportConfirmation {
                Text(confirmation)
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            // GUILD-UI-1 (D4): the info area navigates to the spectator page; the Join/Request
            // button is a SIBLING (not nested), so each consumes its own tap — the established
            // buttonStyle-isolation resolution of the Button-inside-link conflict. The spectator's
            // onJoin routes back through this VM's join core (single in-flight flag preserved).
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                NavigationLink {
                    GuildDetailView(coordinator: coordinator, spectatorCode: row.id,
                                    onJoin: { await viewModel.joinFromDirectory(row) })
                } label: {
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
                        }

                        Spacer(minLength: DesignSystem.Spacing.sm)

                        // D5: policyPill → right-aligned stacked POLICY micro-label + "N members".
                        directoryMicroLabels(row)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                directoryAction(row)
            }
            .padding(.vertical, DesignSystem.Spacing.md)
            .contextMenu {
                // UGC-1b: Report Guild (D5 `.guild`) — reportedUid is the owner's uid.
                Button {
                    Task {
                        await viewModel.reportGuild(ownerUid: row.ownerUid, code: row.id,
                                                    name: row.name, description: row.description)
                    }
                } label: {
                    Label("Report Guild", systemImage: "flag")
                }
            }

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

    /// GUILD-UI-1 (D4/D5): the directory row's right-side stack — a tracked-uppercase POLICY
    /// micro-label over an "N members" line (from `GuildDirectoryRow.memberCount`), replacing the
    /// swept-away capsule `policyPill`. Exhaustive over the three policies — `private` cannot appear
    /// here (the rules' `list` clause excludes it) but is mapped, never folded into a "Request"
    /// default (R7d lesson). A `nil` count (legacy pre-backfill doc) is UNKNOWN, never 0, so the
    /// count line is OMITTED entirely rather than rendered as "0 members".
    private func directoryMicroLabels(_ row: GuildViewModel.GuildDirectoryRow) -> some View {
        let word: String
        switch row.joinPolicy {
        case "open":    word = "Open"
        case "private": word = "Private"
        default:        word = "Request"
        }
        return VStack(alignment: .trailing, spacing: 2) {
            Text(word)
                .font(AppFont.bold(9.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(tc.textTertiary)
            if let count = row.memberCount {
                Text("\(count) member\(count == 1 ? "" : "s")")
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textSecondary)
            }
        }
        .fixedSize()
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

    /// The shared tab ViewModel — MEMBER mode only. Implicitly-unwrapped because spectator mode
    /// (GUILD-UI-1 D1) MUST NOT instantiate any member-only ViewModel state: it is `nil` there and
    /// the spectator body never touches it (the member arms below are unchanged, still reading
    /// `viewModel` directly). Read only inside the `!isSpectator` execution path.
    private let viewModel: GuildViewModel!
    let coordinator: AppCoordinator

    // MARK: - Spectator mode (GUILD-UI-1 D1) — lightweight @State, no ViewModel.

    /// Non-nil ⇒ spectator mode: a read-only page for the guild with this code. `nil` ⇒ member mode.
    private let spectatorCode: String?
    /// Wired by the directory presenter to the tab VM's `joinFromDirectory` core (D3). `nil` in
    /// member mode AND for the D7 own-guild entry (read-only, no join button).
    private let onSpectatorJoin: (() async -> Void)?

    private var isSpectator: Bool { spectatorCode != nil }

    @State private var spectatorGuild: GuildDTO? = nil
    @State private var spectatorMembers: [GuildViewModel.MemberRow] = []
    @State private var spectatorLoading = true
    /// Set when the guild doc can't be read (disbanded mid-view, or a pre-deploy permission-deny).
    @State private var spectatorUnavailable = false
    /// Local button-disable flag while the wired join runs; the single in-flight guard itself lives
    /// in the tab VM's `performJoin` (D3) — this only greys the spectator button during the await.
    @State private var spectatorJoining = false

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Action confirmations / sheets
    @State private var showLeaveConfirm = false
    @State private var showDisbandConfirm = false
    @State private var memberToKick: GuildViewModel.MemberRow? = nil
    @State private var profileMember: GuildViewModel.MemberRow? = nil
    @State private var showingEdit = false
    @State private var didCopyCode = false

    // MARK: - Init

    /// Member mode — the in-guild experience over the shared tab ViewModel. Signature unchanged.
    init(viewModel: GuildViewModel, coordinator: AppCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        self.spectatorCode = nil
        self.onSpectatorJoin = nil
    }

    /// Spectator mode (D1) — a read-only page for a guild the viewer is NOT in. No member-only
    /// ViewModel is instantiated; loaded state is fetched once in `.task` via existing fetch shapes.
    /// `onJoin` (nil for the D7 own-guild entry) routes a Join/Request tap to the tab VM's join core.
    init(coordinator: AppCoordinator, spectatorCode: String, onJoin: (() async -> Void)? = nil) {
        self.viewModel = nil
        self.coordinator = coordinator
        self.spectatorCode = spectatorCode
        self.onSpectatorJoin = onJoin
    }

    // MARK: - Body

    @ViewBuilder
    var body: some View {
        if isSpectator {
            spectatorBody
        } else {
            memberBody
        }
    }

    // MARK: - Member Body

    private var memberBody: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                if let guild = viewModel.guild {
                    headerCard(guild, memberCount: viewModel.memberCount, isSpectator: false)
                }

                leaderboardLink

                chatLink

                if let error = viewModel.actionError {
                    inlineError(error)
                }

                if let confirmation = viewModel.reportConfirmation {
                    Text(confirmation)
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
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
        // OCCLUSION-1 D2 (scroll anatomy): this detail screen is pushed inside the Guilds
        // tab's NavigationStack, which the TabView's `.safeAreaInset` tab bar does NOT reach,
        // so the actions at the end (Leave / Disband) render behind the bar and are
        // untappable (known since R7d). Add bottom scroll-content margin of the shared token
        // so the last button clears the bar. Applied on this screen, not globally.
        .contentMargins(.bottom, DesignSystem.Metrics.tabBarHeight, for: .scrollContent)
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
                displayName: member.displayName,
                onRemoved: { Task { await viewModel.load() } }
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

    // MARK: - Spectator Body (GUILD-UI-1 D1/D2/D3)

    /// A read-only page for a guild the viewer is NOT in: name · meta line · description · roster,
    /// plus a Join/Request action (D3). No member-only ViewModel, no invite code / requests /
    /// settings / leave / disband / chat / guild-leaderboard (D2). State is the lightweight @State
    /// above, fetched once in `.task` via existing fetch shapes (D1).
    private var spectatorBody: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                if spectatorLoading {
                    // D1: reuse the guild tab's ProgressView loading treatment.
                    ProgressView()
                        .scaleEffect(1.4)
                        .padding(.top, 60)
                } else if spectatorUnavailable || spectatorGuild == nil {
                    spectatorUnavailableCard
                } else if let guild = spectatorGuild {
                    headerCard(guild, memberCount: spectatorMembers.count, isSpectator: true)

                    spectatorJoinAction(guild)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        sectionHeader("Members")
                        // Spectator rows reuse the SAME builder — kick disabled everywhere (D2).
                        rosterBox(spectatorMembers) { _ in false }
                    }
                    // TODO-spectator-leaderboard: the guild leaderboard is my-guild-bound (its VM
                    // reads the current user's own guild), so it is hidden for spectators (D2).
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        // Same bottom clearance as the member page: the spectator page is pushed inside the Guilds
        // tab's NavigationStack, under the safeAreaInset tab bar (harmless when shown as the D7 sheet).
        .contentMargins(.bottom, DesignSystem.Metrics.tabBarHeight, for: .scrollContent)
        .refreshable { await loadSpectator() }
        .task { await loadSpectator() }
        .sheet(item: $profileMember) { member in
            // NAV-1b: roster rows keep their profile tap gating; a removal reloads the spectator roster.
            FriendProfileView(
                coordinator: coordinator,
                friendUid: member.id,
                username: member.username,
                displayName: member.displayName,
                onRemoved: { Task { await loadSpectator() } }
            )
        }
    }

    /// The spectator Join/Request action (D3), routed to the tab VM's join core via `onSpectatorJoin`.
    /// Absent when there is no join closure (the D7 own-guild read-only entry) and for `private`
    /// guilds (join-by-code stays the code-entry path — the fetched policy decides, per the edge case).
    @ViewBuilder
    private func spectatorJoinAction(_ guild: GuildDTO) -> some View {
        if onSpectatorJoin != nil, guild.joinPolicy != "private" {
            AppButton(
                title: guild.joinPolicy == "request" ? "Request to Join" : "Join Guild",
                style: guild.joinPolicy == "request" ? .secondary : .primary,
                action: { Task { await performSpectatorJoin() } },
                isLoading: spectatorJoining,
                isDisabled: spectatorJoining
            )
        }
    }

    private var spectatorUnavailableCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "shield.slash")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text("This guild is no longer available.")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
                .multilineTextAlignment(.center)
            AppButton(title: "Go Back", style: .secondary, action: { dismiss() })
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        .padding(.top, 40)
    }

    /// Routes the spectator's Join/Request tap through the tab VM's join core (`onSpectatorJoin`),
    /// then dismisses back so the tab's normal reload shows the resulting stage — the in-guild page
    /// on an open join, or the not-in-guild "Request sent" banner via the VM's session-local state
    /// (D3). The single in-flight guard lives in the VM's `performJoin`; `spectatorJoining` only
    /// greys the button during the await.
    private func performSpectatorJoin() async {
        guard let onSpectatorJoin, !spectatorJoining else { return }
        spectatorJoining = true
        await onSpectatorJoin()
        spectatorJoining = false
        dismiss()
    }

    /// Fetches the spectator guild doc + roster ONCE per presentation via the existing fetch shapes
    /// (`coordinator.guild(code:)` + `guildMembers(code:)`); no new fetch shapes, no listeners (D1).
    /// nil guild ⇒ the "no longer available" state (disbanded, or a pre-deploy permission-deny).
    private func loadSpectator() async {
        guard let code = spectatorCode else { return }
        if spectatorGuild == nil { spectatorLoading = true }
        spectatorUnavailable = false
        guard let g = await coordinator.guild(code: code) else {
            spectatorLoading = false
            spectatorUnavailable = true
            return
        }
        spectatorGuild = g
        // TUT-1b visitGuild detection (spectator mode, Decision 4/5) — a successfully fetched
        // guild = "checked out a guild." Reached only past the unavailable early-return above.
        if TutorialProgress.shared.shouldAttempt(TutorialCatalog.visitGuildId) {
            Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.visitGuildId) }
        }
        let me = coordinator.currentUserId
        // Same DTO → row mapping + sort as GuildViewModel.load() (owner first, then title).
        spectatorMembers = (await coordinator.guildMembers(code: code))
            .map { dto in
                GuildViewModel.MemberRow(
                    id: dto.uid,
                    username: dto.username,
                    displayName: dto.displayName,
                    role: dto.role,
                    isMe: dto.uid == me,
                    isFriend: coordinator.friendshipState(with: dto.uid) == .friends,
                    avatarIcon: dto.avatarIcon,
                    avatarColor: dto.avatarColor
                )
            }
            .sorted { a, b in
                if a.isOwnerRole != b.isOwnerRole { return a.isOwnerRole }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        spectatorLoading = false
    }

    // MARK: - Header

    /// The guild header — shared by member mode (`isSpectator: false`) and spectator mode
    /// (D2: name · meta line · description only). `memberCount` is the roster count (the tab VM's
    /// in member mode, the fetched spectator roster's in spectator mode — same meaning). The
    /// invite-code block and the Report overflow are member-only and gated off in spectator mode.
    private func headerCard(_ guild: GuildDTO, memberCount: Int, isSpectator: Bool) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text(guild.name)
                .font(AppFont.bold(24))
                .foregroundColor(tc.textPrimary)
                .multilineTextAlignment(.center)

            // GUILD-UI-1 (D5): the two capsule metaPills → ONE hairline-flanked, tracked-uppercase
            // meta line ("OPEN · 2 MEMBERS"). Exhaustive over the three policies (the R7d lesson).
            metaLine(policy: guild.joinPolicy, count: memberCount)

            if let description = guild.description, !description.isEmpty {
                Text(description)
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Code with copy + share — member-only (D2: spectators don't see the invite code).
            if !isSpectator, let code = guild.id {
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

                        ShareLink(item: "Join my Overheal guild \"\(guild.name)\" with code \(code)") {
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
        .overlay(alignment: .topTrailing) {
            // UGC-1b: Report Guild overflow (the nav bar is hidden here, so a header affordance
            // replaces a toolbar menu). Hidden for the owner — self-reports are rules-rejected
            // and meaningless. Theme-tinted ellipsis; no new visual language.
            // UGC-1b-FIX: the ellipsis carries an accessibilityLabel so VoiceOver / UI automation
            // can identify it (it was an unlabeled button — the reason SMOKE-3 "couldn't find"
            // the affordance, which does render for a non-owner member).
            // GUILD-UI-1 (D2): Report is member machinery — absent in spectator mode (the directory
            // row carries its own Report affordance). `!isSpectator` short-circuits before the
            // `viewModel` access, keeping the IUO safe.
            if !isSpectator && !viewModel.isOwner {
                Menu {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.reportGuild(ownerUid: guild.ownerUid, code: guild.id ?? "",
                                                        name: guild.name, description: guild.description)
                        }
                    } label: {
                        Label("Report Guild", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textTertiary)
                        .padding(DesignSystem.Spacing.md)
                        .accessibilityLabel("Guild options")
                }
            }
        }
    }

    /// Short policy word for the tracked-uppercase meta line + spectator/directory micro-labels.
    /// Exhaustive over the three policies (R7d lesson — never fold `private` into a "Request"
    /// default). `textCase(.uppercase)` at the render site supplies the casing.
    private func policyWord(_ joinPolicy: String) -> String {
        switch joinPolicy {
        case "open":    return "Open"
        case "private": return "Private"
        default:        return "Request"
        }
    }

    /// GUILD-UI-1 (D5): the de-capsuled header meta line — a hairline rule, tracked-uppercase
    /// "POLICY · N MEMBERS" text, a hairline rule. Typography mirrors the ProfileView section-label
    /// / ArenaView league-subline family (AppFont.bold ~10.5pt, tracking, uppercase, textSecondary).
    private func metaLine(policy: String, count: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Rectangle().fill(DesignSystem.Erewhon.line).frame(height: 1).frame(maxWidth: 64)
            Text("\(policyWord(policy)) · \(count) member\(count == 1 ? "" : "s")")
                .font(AppFont.bold(10.5))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundColor(tc.textSecondary)
                .fixedSize()
            Rectangle().fill(DesignSystem.Erewhon.line).frame(height: 1).frame(maxWidth: 64)
        }
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
            // D3b: leading preset avatar over the shared standings initials fallback (38pt).
            AvatarView(iconId: request.avatarIcon, colorId: request.avatarColor, size: 38) {
                StandingsPieces.avatar(initial: initials(displayName: request.displayName, username: request.username), tint: nil)
            }
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
            // GUILD-UI-1 (D6): the roster in the boxed, internally-scrolling board. Only the owner
            // (member mode) can kick, so canKick is computed per row at the member call site — the
            // shared row builder itself never reads the ViewModel (so spectator mode reuses it).
            rosterBox(viewModel.members) { m in
                viewModel.isOwner && !m.isMe && !m.isOwnerRole
            }
        }
    }

    /// GUILD-UI-1 (D6): the members list inside an internally-scrolling box (member AND spectator
    /// mode). Box language mirrors GuildLeaderboardView's LB-PAGE board (RoundedRectangle(16) +
    /// Erewhon.line stroke, `leaderboardBoxHeightCompact`; rows are NOT restyled). The list is
    /// UNPAGINATED, PERMANENTLY: the fetch is bounded by the 40-member GUILD-CAP hard cap, so it can
    /// never exceed one screen's worth of data (no member-pagination TODO exists to delete).
    /// `canKick` is supplied by the caller so this builder is ViewModel-free and mode-agnostic.
    private func rosterBox(_ members: [GuildViewModel.MemberRow],
                           canKick: @escaping (GuildViewModel.MemberRow) -> Bool) -> some View {
        // LB-PAGE-1: deliberate nested-scroll exception (user ruling; Clash-style boxed board). Revisit if it fights the outer scroll. DO NOT replace with outer scrolling.
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(members) { member in
                    memberRow(member, canKick: canKick(member))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .frame(height: DesignSystem.Metrics.leaderboardBoxHeightCompact)
        .background(RoundedRectangle(cornerRadius: 16).fill(tc.primaryBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func memberRow(_ member: GuildViewModel.MemberRow, canKick: Bool) -> some View {
        // NAV-1b: every non-self guild-mate opens their profile, friend or not.
        let tappable = !member.isMe
        return Button {
            if tappable { profileMember = member }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                // D3b: preset avatar over the existing 44pt tinted-initials fallback (byte-preserved).
                AvatarView(iconId: member.avatarIcon, colorId: member.avatarColor, size: 44) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tc.primary.opacity(0.16))
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(tc.primary.opacity(0.45), lineWidth: 1.5)
                        Text(initials(for: member))
                            .font(AppFont.bold(16))
                            .foregroundColor(tc.primary)
                    }
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
                    // GUILD-UI-1 (D5): the OWNER capsule → a keyline tag in the role colour (gold).
                    tag("Owner", color: DesignSystem.Colors.goldMid)
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
        initials(displayName: member.displayName, username: member.username)
    }

    /// Shared initials builder — used by the member row and the join-request row's avatar fallback.
    private func initials(displayName: String, username: String) -> String {
        let name = displayName.isEmpty ? username : displayName
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// GUILD-UI-1 (D5): the OWNER/YOU role tags — rewritten in place from a filled capsule to a
    /// KEYLINE tag: a 2pt left rule + tracked-uppercase text in the role colour, no background shape
    /// (mockup `.keytag`). Same name, same call sites (the member row's "You" and "Owner").
    private func tag(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 2, height: 11)
            Text(text)
                .font(AppFont.bold(9))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundColor(color)
        }
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
