//
//  SettingsManager.swift
//  HealthBar
//
//  Created by Claude on 1/27/26.
//

import Foundation
import SwiftUI

/// TEXTSIZE-1. rawValues are persisted in UserDefaults — PERMANENT identifiers;
/// never rename them. Display names and scale factors may be retuned freely.
enum TextSizeOption: String, CaseIterable {
    case standard = "standard"
    case large = "large"
    case extraLarge = "xlarge"

    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Global multiplier applied inside AppFont. Capped at 1.3 — fixed-height
    /// surfaces (PhotoSplitCard, toasts, RankPlaque) are layout-frozen and larger
    /// factors clip (TODO-dynamic-type for true adaptive layout).
    var scaleFactor: CGFloat {
        switch self {
        case .standard: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

/// Manages user preferences and app settings
///
/// Uses UserDefaults for persistent storage. All settings update UI immediately.
/// Observable so views can react to setting changes in real-time.
@Observable
final class SettingsManager {

    // MARK: - Singleton

    /// Shared instance for app-wide access
    static let shared = SettingsManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let trackAdvancedNutrition = "trackAdvancedNutrition"
        static let dailyMoodCheckEnabled = "dailyMoodCheckEnabled"
        static let themePreference = "themePreference"
        static let textSizePreference = "textSizePreference"
        static let didMigrateToErewhon = "didMigrateToErewhon"
        static let hasSeenWelcome = "hasSeenWelcome"
    }

    // MARK: - Settings Properties

    /// Whether to show advanced nutrition tracking (fiber, sugar, sodium, etc.)
    /// Off by default. When enabled, shows additional fields throughout the app.
    /// Data persists even when toggle is disabled (UI just hides, data stays).
    var trackAdvancedNutrition: Bool {
        didSet {
            UserDefaults.standard.set(trackAdvancedNutrition, forKey: Keys.trackAdvancedNutrition)
        }
    }

    /// Whether to prompt user for daily mood check at 7pm
    /// ON by default. When enabled, shows modal if app is active and mood not logged.
    var dailyMoodCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dailyMoodCheckEnabled, forKey: Keys.dailyMoodCheckEnabled)
        }
    }

    /// B1: whether the one-time first-launch welcome screen has been shown.
    /// Device-scoped (UserDefaults only, never synced). Set `true` when the user taps
    /// either Welcome CTA (Get Started / Log In) or on any authenticated session
    /// (grandfathering existing users). Deliberately NOT touched by `resetToDefaults()`
    /// — resetting settings must never resurface the welcome.
    var hasSeenWelcome: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenWelcome, forKey: Keys.hasSeenWelcome)
        }
    }

    /// Theme preference. Pixel schemes: "auto" (time cycle), "morning", "afternoon",
    /// "night". Flat (Erewhon) schemes: "erewhonLight", "erewhonDark". Fresh installs
    /// default to "erewhonLight". The retired "cleanLight"/"cleanDark" keys are migrated
    /// away once in init (see migrateToErewhonIfNeeded).
    var themePreference: String {
        didSet {
            UserDefaults.standard.set(themePreference, forKey: Keys.themePreference)
        }
    }

    /// Resolves the active theme based on preference
    var activeTheme: TimeOfDayTheme {
        if themePreference == "auto" {
            return TimeOfDayTheme.current()
        }
        return TimeOfDayTheme(rawValue: themePreference) ?? TimeOfDayTheme.current()
    }

    /// True when either Erewhon (flat-family) scheme is active.
    /// D3: the flat family is now Erewhon; the `isCleanUI` name is retained from the
    /// retired Clean era (no rename), and the old clean keys no longer occur.
    var isCleanUI: Bool {
        themePreference == "erewhonLight" || themePreference == "erewhonDark"
    }

    /// True specifically for Erewhon Dark (drives preferredColorScheme + the Erewhon
    /// line/lineSoft tokens). D3: name retained from the retired Clean era (no rename).
    var isCleanDark: Bool {
        themePreference == "erewhonDark"
    }

    /// Returns the resolved ThemeColors for the current settings.
    /// Erewhon schemes return their palettes; pixel schemes return time-of-day palettes.
    /// Stale "cleanLight"/"cleanDark" keys (should be unreachable post-migration)
    /// defensively map to the matching Erewhon scheme — never to pixel (D2).
    var activeColors: ThemeColors {
        switch themePreference {
        case "erewhonLight", "cleanLight": return ThemeColors.erewhonLight
        case "erewhonDark", "cleanDark": return ThemeColors.erewhonDark
        default: return activeTheme.colors
        }
    }

    // MARK: - Text Size (TEXTSIZE-1)

    /// TEXTSIZE-1: stored TextSizeOption rawValue. Unknown/legacy values resolve to standard.
    /// Device-scoped (UserDefaults only, never synced). Mirrors the `themePreference` shape.
    var textSizePreference: String {
        didSet {
            UserDefaults.standard.set(textSizePreference, forKey: Keys.textSizePreference)
        }
    }

    var textSizeOption: TextSizeOption {
        TextSizeOption(rawValue: textSizePreference) ?? .standard
    }

    var textScaleFactor: CGFloat { textSizeOption.scaleFactor }

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults
        self.trackAdvancedNutrition = UserDefaults.standard.bool(forKey: Keys.trackAdvancedNutrition)

        // B1: one-time welcome flag. Absent reads `false` (never seen) — the correct default.
        self.hasSeenWelcome = UserDefaults.standard.bool(forKey: Keys.hasSeenWelcome)

        // Default to true if never set before
        if UserDefaults.standard.object(forKey: Keys.dailyMoodCheckEnabled) == nil {
            UserDefaults.standard.set(true, forKey: Keys.dailyMoodCheckEnabled)
            self.dailyMoodCheckEnabled = true
        } else {
            self.dailyMoodCheckEnabled = UserDefaults.standard.bool(forKey: Keys.dailyMoodCheckEnabled)
        }

        // Theme preference (fresh installs default to Erewhon Dark — DARKDEFAULT-1; was Light per D2).
        if let pref = UserDefaults.standard.string(forKey: Keys.themePreference) {
            self.themePreference = pref
        } else {
            self.themePreference = "erewhonDark"
        }

        // Text size preference (fresh installs default to standard — TEXTSIZE-1).
        // Unknown/legacy stored values resolve to standard via the textSizeOption accessor.
        if let sizePref = UserDefaults.standard.string(forKey: Keys.textSizePreference) {
            self.textSizePreference = sizePref
        } else {
            self.textSizePreference = "standard"
        }

        // One-time migration to the Erewhon reskin (D2). Runs once, after the pref loads.
        migrateToErewhonIfNeeded()
    }

    // MARK: - Methods

    /// Resets all settings to defaults
    func resetToDefaults() {
        trackAdvancedNutrition = false
        dailyMoodCheckEnabled = true
        themePreference = "erewhonDark"
    }

    // MARK: - Erewhon Migration (D2)

    /// One-time migration to the Erewhon reskin. Idempotent via `didMigrateToErewhon`.
    /// Maps the retired clean keys to their Erewhon counterpart and any pixel key (incl.
    /// "auto") to Erewhon Light — the one-time new-look default. Runs once; afterward the
    /// user may re-select any pixel theme and it sticks (the migration never re-runs).
    private func migrateToErewhonIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.didMigrateToErewhon) else { return }
        let migrated = Self.migratedThemeKey(from: themePreference)
        themePreference = migrated
        // Persist explicitly — property observers may not fire for an init-time assignment.
        UserDefaults.standard.set(migrated, forKey: Keys.themePreference)
        UserDefaults.standard.set(true, forKey: Keys.didMigrateToErewhon)
    }

    /// Pure Erewhon migration mapping (verified by the standalone ThemeMigrationCheck).
    /// Exposed as a `static func` so the mapping is testable in isolation.
    static func migratedThemeKey(from key: String) -> String {
        switch key {
        case "cleanLight": return "erewhonLight"
        case "cleanDark": return "erewhonDark"
        case "erewhonLight", "erewhonDark": return key
        default: return "erewhonLight" // any pixel key (incl. "auto") or unknown
        }
    }
}
