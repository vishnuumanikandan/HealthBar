//
//  FriendPickerSheet.swift
//  HealthBar
//
//  Created by Claude on 6/12/26.
//

import SwiftUI

/// Picks a friend to share a meal/recipe with (Friend System Phase 9).
///
/// Lists the local friends (Prompt 2 `fetchFriends()`), sorted by display name.
/// Tapping a friend runs the caller-provided `share` closure with that friend's
/// uid, with a per-row in-flight flag; on success a brief toast then dismiss; on
/// failure an inline error and the sheet stays open. Guests never reach this
/// (the share action is hidden for them).
struct FriendPickerSheet: View {

    private let coordinator: AppCoordinator

    /// The meal/recipe name, shown in the header and the success toast.
    private let itemName: String

    /// Performs the actual share to the chosen friend's uid. Throws to surface
    /// an inline error.
    private let share: (_ friendUid: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Value snapshot of a friend — never carry @Model references into the view.
    private struct Row: Identifiable {
        let id: String          // friendUid
        let displayName: String
        let username: String
        var name: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    @State private var rows: [Row] = []
    @State private var isLoading = true
    @State private var inFlight: Set<String> = []
    @State private var errorMessage: String? = nil
    @State private var sharedWithName: String? = nil

    init(coordinator: AppCoordinator, itemName: String, share: @escaping (String) async throws -> Void) {
        self.coordinator = coordinator
        self.itemName = itemName
        self.share = share
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()
                content

                if let name = sharedWithName {
                    successToast(name)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Share to friend")
                        .font(AppFont.bold(18))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.primary)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(tc.primary)
        } else if rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Sharing “\(itemName)”")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        inlineError(errorMessage)
                    }

                    ForEach(rows) { row in
                        friendRow(row)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }

    private func friendRow(_ row: Row) -> some View {
        let busy = inFlight.contains(row.id)
        return Button {
            Task { await pick(row) }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tc.primary.opacity(0.14))
                    Text(initials(row))
                        .font(AppFont.bold(15))
                        .foregroundColor(tc.primary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(AppFont.bold(15))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    if !row.displayName.isEmpty {
                        Text("@\(row.username)")
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }
                }

                Spacer()

                if busy {
                    ProgressView().controlSize(.small).tint(tc.primary)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.primary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(busy || sharedWithName != nil)
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "person.2")
                .font(AppFont.regular(40))
                .foregroundColor(tc.textTertiary)
            Text("Add friends to share")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
            Text("You can share meals and recipes once you've added a friend.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.xl)
    }

    private func successToast(_ name: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(tc.primary)
                Text("Shared with \(name)")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.5), fillColor: tc.cardBackground)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func initials(_ row: Row) -> String {
        let source = row.displayName.isEmpty ? row.username : row.displayName
        let letters = source.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: - Actions

    private func load() async {
        let friends = (try? await coordinator.fetchFriends()) ?? []
        rows = friends
            .map { Row(id: $0.friendUid, displayName: $0.displayName, username: $0.username) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
    }

    private func pick(_ row: Row) async {
        guard !inFlight.contains(row.id), sharedWithName == nil else { return }
        inFlight.insert(row.id)
        errorMessage = nil
        do {
            try await share(row.id)
            withAnimation { sharedWithName = row.name }
            try? await Task.sleep(for: .seconds(0.9))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't share. Try again."
            inFlight.remove(row.id)
        }
    }
}
