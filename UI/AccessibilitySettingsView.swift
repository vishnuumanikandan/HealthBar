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

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Home Screen Theme Section
                Section {
                    themeRow(
                        title: "Auto (Day Cycle)",
                        subtitle: "Changes with time of day",
                        icon: "arrow.triangle.2.circlepath",
                        value: "auto"
                    )

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
                    Text("Home Screen Theme")
                } footer: {
                    Text("Choose how the home screen looks. Auto changes the theme based on time of day: Morning (6 AM – 2 PM), Afternoon (2 PM – 7 PM), Night (7 PM – 6 AM).")
                }

                // Nutrition Display Section
                Section {
                    Toggle(isOn: $settings.trackAdvancedNutrition) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Show Advanced Nutrition")
                                .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            Text("Track fiber, sugar, sodium, and more")
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .tint(DesignSystem.Colors.primary)
                    .accessibilityLabel("Show advanced nutrition tracking")
                    .accessibilityHint("When enabled, shows fiber, sugar, sodium, and other nutrients")
                } header: {
                    Text("Nutrition Display")
                } footer: {
                    Text("Data is saved even when this is disabled. Only the display is affected.")
                }

                // Daily Check-ins Section
                Section {
                    Toggle(isOn: $settings.dailyMoodCheckEnabled) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("Daily Mood Check")
                                .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            Text("Prompt to log your mood at 7 PM")
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .tint(DesignSystem.Colors.primary)
                    .accessibilityLabel("Enable daily mood check")
                    .accessibilityHint("When enabled, prompts you to log your mood at 7 PM each day")
                } header: {
                    Text("Daily Check-ins")
                } footer: {
                    Text("A quick way to track how you're feeling each day alongside your nutrition.")
                }
            }
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                }
            }
        }
    }

    // MARK: - Theme Row

    @ViewBuilder
    private func themeRow(title: String, subtitle: String, icon: String, value: String) -> some View {
        Button {
            settings.themePreference = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(value == settings.themePreference ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: DesignSystem.FontSizes.caption))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                if value == settings.themePreference {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
        }
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
