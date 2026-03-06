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

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults
        self.trackAdvancedNutrition = UserDefaults.standard.bool(forKey: Keys.trackAdvancedNutrition)
    }

    // MARK: - Methods

    /// Resets all settings to defaults
    func resetToDefaults() {
        trackAdvancedNutrition = false
    }
}
