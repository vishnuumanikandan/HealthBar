//
//  SettingsManager.swift
//  HealthBar
//
//  Created by Claude on 1/27/26.
//

import Foundation
import SwiftUI

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

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults
        self.trackAdvancedNutrition = UserDefaults.standard.bool(forKey: Keys.trackAdvancedNutrition)

        // Default to true if never set before
        if UserDefaults.standard.object(forKey: Keys.dailyMoodCheckEnabled) == nil {
            UserDefaults.standard.set(true, forKey: Keys.dailyMoodCheckEnabled)
            self.dailyMoodCheckEnabled = true
        } else {
            self.dailyMoodCheckEnabled = UserDefaults.standard.bool(forKey: Keys.dailyMoodCheckEnabled)
        }
    }

    // MARK: - Methods

    /// Resets all settings to defaults
    func resetToDefaults() {
        trackAdvancedNutrition = false
        dailyMoodCheckEnabled = true
    }
}
