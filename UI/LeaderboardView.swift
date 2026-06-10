//
//  LeaderboardView.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import SwiftUI

/// RETIRED (Friend System Phase 5): the friend leaderboard now lives as
/// `LeaderboardSection` embedded on the Home screen. This standalone screen is
/// no longer pushed or presented anywhere — it survives only as a thin
/// scrolling wrapper around `LeaderboardSection` so any lingering reference or
/// preview keeps compiling. All ranking/fetch logic stays in
/// `LeaderboardViewModel`; the row rendering moved verbatim into the section.
struct LeaderboardView: View {

    // MARK: - Properties

    @State private var viewModel: LeaderboardViewModel

    /// Retained to construct the FriendProfileView sheet (via the section).
    private let coordinator: AppCoordinator

    /// Read-only — gates the guest state and the load trigger.
    private let authService: any AuthService

    /// Forwarded to the section's no-friends CTA.
    private let onAddFriends: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onAddFriends: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: LeaderboardViewModel(coordinator: coordinator))
        self.coordinator = coordinator
        self.authService = authService
        self.onAddFriends = onAddFriends
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LeaderboardSection(
                viewModel: viewModel,
                coordinator: coordinator,
                authService: authService,
                onAddFriends: onAddFriends
            )
            .padding(DesignSystem.Spacing.lg)
        }
        .background(tc.primaryBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Guests fetch nothing — the same no-Firestore rule as the section.
            guard !authService.isGuest else { return }
            await viewModel.refresh()
        }
    }
}
