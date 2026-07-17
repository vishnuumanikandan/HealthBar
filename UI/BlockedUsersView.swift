//
//  BlockedUsersView.swift
//  HealthBar
//
//  Created by Claude on 7/16/26.
//

import SwiftUI

/// UGC-1b — Blocked Users management screen. A settings subscreen (pushed from AccountView)
/// listing everyone the current user has blocked, each with an Unblock action.
///
/// Names resolve from the world-readable `leaderboard/{uid}` projection via
/// `coordinator.blockedUsersDisplay()` (DataManager owns the resolution + the "Unknown player"
/// fallback for a uid with no leaderboard row — that row is still unblock-able because
/// everything keys on uid). Unblock does NOT restore any prior relationship (1a ruling); the
/// copy here makes no restoration claim.
@Observable
@MainActor
final class BlockedUsersViewModel {

    private let coordinator: AppCoordinator

    /// One resolved display row per blocked uid, name-sorted by DataManager.
    var rows: [BlockedUserRow] = []
    /// True once the first load finishes — separates "still loading" from "empty".
    var hasLoaded = false
    /// Uids with an in-flight unblock (disables that row's button).
    var pendingUnblockUids: Set<String> = []

    struct BlockedUserRow: Identifiable, Equatable {
        let id: String          // uid — the unblock key
        let username: String
        let displayName: String
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func load() async {
        let display = await coordinator.blockedUsersDisplay()
        rows = display.map { BlockedUserRow(id: $0.uid, username: $0.username, displayName: $0.displayName) }
        hasLoaded = true
    }

    /// Unblocks then reloads. The list is tiny (cap 500, usually a handful), so a full reload
    /// after each unblock is cheaper than local surgery — and it keeps `rows` authoritative.
    func unblock(_ uid: String) async {
        guard !pendingUnblockUids.contains(uid) else { return }
        pendingUnblockUids.insert(uid)
        defer { pendingUnblockUids.remove(uid) }
        try? await coordinator.unblockUser(uid)
        await load()
    }
}

struct BlockedUsersView: View {

    @State private var viewModel: BlockedUsersViewModel
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @Environment(\.dismiss) private var dismiss

    init(coordinator: AppCoordinator) {
        self._viewModel = State(initialValue: BlockedUsersViewModel(coordinator: coordinator))
    }

    // Presented as a sheet from AccountView (which is itself a sheet with no ambient
    // NavigationStack), so this wraps its own NavigationStack for the toolbar — matching
    // AccountView's password/delete sub-sheets.
    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        if !viewModel.hasLoaded {
                            ProgressView()
                                .padding(DesignSystem.Spacing.xl)
                        } else if viewModel.rows.isEmpty {
                            Text("No blocked users.")
                                .font(AppFont.regular(15))
                                .foregroundColor(tc.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(DesignSystem.Spacing.xl)
                        } else {
                            VStack(spacing: 0) {
                                let rows = viewModel.rows
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    blockedRow(row, isLast: index == rows.count - 1)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Blocked Users")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Done").font(AppFont.regular(16))
                            .foregroundColor(tc.primary)
                    }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Row

    private func blockedRow(_ row: BlockedUsersViewModel.BlockedUserRow, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.displayName.isEmpty ? "@\(row.username)" : row.displayName)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)

                    if !row.displayName.isEmpty && !row.username.isEmpty {
                        Text("@\(row.username)")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }
                }

                Spacer()

                Button {
                    Task { await viewModel.unblock(row.id) }
                } label: {
                    Text("Unblock")
                        .font(AppFont.bold(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .adaptivePill(borderColor: tc.primaryDark, fillColor: tc.primary)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.pendingUnblockUids.contains(row.id))
            }
            .padding(.vertical, 13)

            if !isLast {
                Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
            }
        }
    }
}
