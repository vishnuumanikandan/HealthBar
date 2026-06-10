//
//  UsernameError.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

enum UsernameError: LocalizedError {
    case taken
    case invalidFormat
    case notAuthenticated
    case network(String)
    case cooldownActive(Date)

    var errorDescription: String? {
        switch self {
        case .taken:            return "That username is already taken."
        case .invalidFormat:    return "Usernames must be 3–20 characters: lowercase letters, numbers, or underscores, starting with a letter."
        case .notAuthenticated: return "You must be signed in to choose a username."
        case .network(let m):   return "Couldn't reach the server. Try again. (\(m))"
        case .cooldownActive(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "You can change your username again on \(formatter.string(from: date))."
        }
    }
}
