//
//  CreateGuildSheet.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import SwiftUI

/// Sheet for creating a new guild (Guilds Prompt G1): name, join policy, and an
/// optional description. On success it notifies the parent (which reloads to show
/// the new guild) and dismisses.
struct CreateGuildSheet: View {

    private let coordinator: AppCoordinator
    private let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var name: String = ""
    @State private var joinPolicy: String = "open"
    @State private var description: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    init(coordinator: AppCoordinator, onCreated: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onCreated = onCreated
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        GuildFormContent(
                            name: $name,
                            joinPolicy: $joinPolicy,
                            description: $description
                        )

                        if let error = errorMessage {
                            GuildFormContent.inlineError(error)
                        }

                        AppButton(
                            title: "Create Guild",
                            style: .primary,
                            action: { Task { await create() } },
                            isLoading: isWorking,
                            isDisabled: !canSubmit
                        )
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Guild")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
    }

    private func create() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await coordinator.createGuild(
                name: name,
                joinPolicy: joinPolicy,
                description: description.isEmpty ? nil : description
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let guildError = error as? GuildError {
            return guildError.errorDescription ?? "Something went wrong."
        }
        return GuildError.network(error.localizedDescription).errorDescription ?? "Something went wrong."
    }
}

// MARK: - Edit Guild Settings Sheet

/// Owner-only sheet to update a guild's name, join policy, and description.
struct EditGuildSettingsSheet: View {

    private let coordinator: AppCoordinator
    private let guild: GuildDTO
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var name: String
    @State private var joinPolicy: String
    @State private var description: String
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    init(coordinator: AppCoordinator, guild: GuildDTO, onSaved: @escaping () -> Void) {
        self.coordinator = coordinator
        self.guild = guild
        self.onSaved = onSaved
        self._name = State(initialValue: guild.name)
        self._joinPolicy = State(initialValue: guild.joinPolicy)
        self._description = State(initialValue: guild.description ?? "")
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        GuildFormContent(
                            name: $name,
                            joinPolicy: $joinPolicy,
                            description: $description
                        )

                        if let error = errorMessage {
                            GuildFormContent.inlineError(error)
                        }

                        AppButton(
                            title: "Save Changes",
                            style: .primary,
                            action: { Task { await save() } },
                            isLoading: isWorking,
                            isDisabled: !canSubmit
                        )
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Guild Settings")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
    }

    private func save() async {
        guard !isWorking, let code = guild.id else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await coordinator.updateGuildSettings(
                code: code,
                name: name,
                joinPolicy: joinPolicy,
                description: description.isEmpty ? nil : description
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let guildError = error as? GuildError {
            return guildError.errorDescription ?? "Something went wrong."
        }
        return GuildError.network(error.localizedDescription).errorDescription ?? "Something went wrong."
    }
}

// MARK: - Shared Form Content

/// The shared name / join-policy / description fields used by both the create and
/// edit sheets.
private struct GuildFormContent: View {

    @Binding var name: String
    @Binding var joinPolicy: String
    @Binding var description: String

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            AuthTextField(
                label: "Guild name",
                placeholder: "Up to 30 characters",
                text: $name
            )

            // Join policy selector
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Join policy")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)

                // R7d: three policies. Stacked rather than side-by-side — a third column
                // squeezes each option to ~a third of the width and wraps the subtitles into
                // unreadable slivers. Each option keeps the existing card treatment exactly.
                VStack(spacing: DesignSystem.Spacing.sm) {
                    policyOption(
                        value: "open",
                        title: "Open",
                        subtitle: "Anyone with the code joins instantly",
                        icon: "lock.open.fill"
                    )
                    policyOption(
                        value: "request",
                        title: "Request",
                        subtitle: "You approve each member",
                        icon: "hand.raised.fill"
                    )
                    policyOption(
                        value: "private",
                        title: "Private",
                        subtitle: "Joinable by code only — hidden from the guild list",
                        icon: "lock.fill"
                    )
                }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                AuthTextField(
                    label: "Description (optional)",
                    placeholder: "Up to 140 characters",
                    text: $description
                )
                Text("\(description.count)/140")
                    .font(AppFont.regular(11))
                    .foregroundColor(description.count > 140 ? DesignSystem.Colors.danger : tc.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func policyOption(value: String, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = joinPolicy == value
        return Button {
            joinPolicy = value
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                    Text(title)
                        .font(AppFont.bold(14))
                }
                .foregroundColor(isSelected ? .white : tc.textPrimary)

                Text(subtitle)
                    .font(AppFont.regular(11))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : tc.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(
                borderColor: isSelected ? tc.primaryDark : tc.primary.opacity(0.3),
                fillColor: isSelected ? tc.primary : tc.cardBackground
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Shared inline error row, also used by the parent sheets.
    static func inlineError(_ message: String) -> some View {
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
