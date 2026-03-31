//
//  APIConfig.swift
//  HealthBar
//
//  Created by Claude on 3/31/26.
//

import Foundation

/// Reads API keys from Config.plist (bundled resource, excluded from git).
///
/// To set up: add Config.plist to the HealthBar/ directory with key CLAUDE_API_KEY.
enum APIConfig {

    /// The Claude API key read from Config.plist at runtime.
    /// Returns an empty string if the file is missing or the key is absent.
    static var claudeAPIKey: String {
        guard
            let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url),
            let key = dict["CLAUDE_API_KEY"] as? String
        else {
            return ""
        }
        return key
    }
}
