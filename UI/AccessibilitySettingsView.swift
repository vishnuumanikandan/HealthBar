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
/// - Show Advanced Nutrition toggle (moved from ProfileView)
/// - Daily Mood Check toggle
struct AccessibilitySettingsView: View {

    /// Settings manager for persistence
    @State private var settings = SettingsManager.shared

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
}

// MARK: - Preview

#Preview("Accessibility Settings") {
    AccessibilitySettingsView()
}
