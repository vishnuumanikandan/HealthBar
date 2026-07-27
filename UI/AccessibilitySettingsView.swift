//
//  AccessibilitySettingsView.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import SwiftUI

/// Settings page for accessibility and display preferences
///
/// Contains:
/// - Home Screen Theme picker (auto / morning / afternoon / night)
/// - Show Advanced Nutrition toggle
/// - Daily Mood Check toggle
struct AccessibilitySettingsView: View {

    /// Settings manager for persistence
    @State private var settings = SettingsManager.shared

    /// Coordinator for the changeTheme tutorial detection (TUT-1b, Decision 6). Optional so
    /// the bare `#Preview` can omit it — nil ⇒ detection is silently skipped.
    private let coordinator: AppCoordinator?

    /// Active-theme colors (R8 token conversion)
    private var tc: ThemeColors { settings.activeColors }

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    init(coordinator: AppCoordinator? = nil) {
        self.coordinator = coordinator
    }

    var body: some View {
        NavigationStack {
            List {
                // RPG Themes
                Section {
                    themeRow(
                        title: "Auto (Day Cycle)",
                        subtitle: "Shifts morning, afternoon, night",
                        icon: "arrow.triangle.2.circlepath",
                        value: "auto"
                    )
                    // TUT-1b changeTheme beacon (Decision 7) — placed on the first theme option so it
                    // sits at the top of the theme groups (a List Section can't host the overlay itself).
                    // A flat full-width List row — trace it with the small rectangular radius.
                    .questBeacon(TutorialCatalog.changeThemeId, cornerRadius: DesignSystem.CornerRadius.sm)

                    Divider()

                    ForEach(TimeOfDayTheme.allCases) { theme in
                        themeRow(
                            title: theme.displayName,
                            subtitle: themeSubtitle(for: theme),
                            icon: theme.icon,
                            value: theme.rawValue
                        )
                    }
                } header: {
                    Text("RPG Pixel Art")
                } footer: {
                    Text("Retro pixel art with wooden boards, Silkscreen font, and themed color palettes.")
                }
                .listRowBackground(tc.cardBackground)

                // Erewhon Themes
                Section {
                    themeRow(
                        title: "Clean Light",
                        subtitle: "Minimalist, modern, easy to read",
                        icon: "sun.max",
                        value: "erewhonLight"
                    )

                    Divider()

                    themeRow(
                        title: "Clean Dark",
                        subtitle: "Sleek dark mode, reduced eye strain",
                        icon: "moon",
                        value: "erewhonDark"
                    )
                } header: {
                    Text("Clean")
                } footer: {
                    Text("Modern flat UI with Bebas Neue & Hanken Grotesk type. Same features, bolder look.")
                }
                .listRowBackground(tc.cardBackground)

                // Text Size Section (TEXTSIZE-1) — above the first accessibility toggle.
                // Each row renders at the CURRENT global scale via AppFont, so selecting
                // an option re-renders the whole screen at the new size: the list IS the preview.
                Section {
                    ForEach(TextSizeOption.allCases, id: \.self) { option in
                        textSizeRow(option)
                    }
                } header: {
                    Text("TEXT SIZE")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Nutrition Display Section
                Section {
                    Toggle(isOn: $settings.trackAdvancedNutrition) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Show Advanced Nutrition")
                                .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                                .foregroundColor(tc.textPrimary)

                            Text("Track fiber, sugar, sodium, and more")
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                    .tint(tc.primary)
                    .accessibilityLabel("Show advanced nutrition tracking")
                    .accessibilityHint("When enabled, shows fiber, sugar, sodium, and other nutrients")
                } header: {
                    Text("Nutrition Display")
                } footer: {
                    Text("Data is saved even when this is disabled. Only the display is affected.")
                }
                .listRowBackground(tc.cardBackground)

                // Daily Check-ins Section
                Section {
                    Toggle(isOn: $settings.dailyMoodCheckEnabled) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Daily Mood Check")
                                .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                                .foregroundColor(tc.textPrimary)

                            Text("Prompt to log your mood at 7 PM")
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                    .tint(tc.primary)
                    .accessibilityLabel("Enable daily mood check")
                    .accessibilityHint("When enabled, prompts you to log your mood at 7 PM each day")
                } header: {
                    Text("Daily Check-ins")
                } footer: {
                    Text("A quick way to track how you're feeling each day alongside your nutrition.")
                }
                .listRowBackground(tc.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .semibold))
                    .foregroundColor(tc.primary)
                }
            }
        }
    }

    // MARK: - Theme Row

    @ViewBuilder
    private func themeRow(title: String, subtitle: String, icon: String, value: String) -> some View {
        Button {
            // TUT-1b changeTheme detection (Decision 4/5) — capture the old preference, then fire
            // only on a REAL change (value != previous), not re-tapping the current theme.
            let previous = settings.themePreference
            settings.themePreference = value
            if value != previous,
               TutorialProgress.shared.shouldAttempt(TutorialCatalog.changeThemeId) {
                Task { _ = try? await coordinator?.completeTutorialStep(TutorialCatalog.changeThemeId) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(value == settings.themePreference ? tc.primary : tc.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                        .foregroundColor(tc.textPrimary)
                    Text(subtitle)
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                if value == settings.themePreference {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tc.primary)
                }
            }
        }
    }

    // MARK: - Text Size Row (TEXTSIZE-1)

    /// Selection row for a text-size option, using the R2 selection convention
    /// (WeeklyPaceStep). Title/subtitle render through AppFont at the CURRENT global
    /// scale, so the row previews the active size live. Tapping writes the persisted
    /// rawValue; the whole screen re-renders immediately — that live flip is the preview.
    @ViewBuilder
    private func textSizeRow(_ option: TextSizeOption) -> some View {
        let isSelected = settings.textSizeOption == option
        Button {
            settings.textSizePreference = option.rawValue
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(option.displayName)
                        .font(isSelected ? AppFont.bold(16) : AppFont.regular(16))
                        .foregroundColor(tc.textPrimary)
                    Text("Preview: The quick brown fox")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(tc.primary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            // R2 selection convention (isSelected drives the accent stroke; R6c)
            .adaptiveCard(
                borderColor: isSelected ? tc.primary : tc.primary.opacity(0.2),
                fillColor: tc.cardBackground,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text size \(option.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func themeSubtitle(for theme: TimeOfDayTheme) -> String {
        switch theme {
        case .morning: return "Green & mint, bright pixel sun"
        case .afternoon: return "Amber & gold, warm sunset"
        case .night: return "Indigo & purple, moonlit sky"
        }
    }
}

// MARK: - Preview

#Preview("Accessibility Settings") {
    AccessibilitySettingsView()
}
