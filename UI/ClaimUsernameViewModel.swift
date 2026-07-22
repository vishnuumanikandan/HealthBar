//
//  ClaimUsernameViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

@Observable
@MainActor
final class ClaimUsernameViewModel {

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - State

    var input: String = "" {
        didSet { validateInput() }
    }
    var inlineError: String? = nil
    var isClaiming: Bool = false
    var didClaim: Bool = false

    var isSubmittable: Bool {
        !isClaiming && !input.isEmpty && inlineError == nil
    }

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Validation

    private func validateInput() {
        guard !input.isEmpty else {
            inlineError = nil
            return
        }
        do {
            _ = try DataManager.normalizeAndValidateUsername(input)
            inlineError = nil
        } catch let error as UsernameError {
            inlineError = error.errorDescription
        } catch {
            inlineError = UsernameError.invalidFormat.errorDescription
        }
    }

    // MARK: - Submit

    func submit(avatarIcon: String, avatarColor: String) async {
        isClaiming = true
        defer { isClaiming = false }

        do {
            try await coordinator.claimUsername(input)
            // D7: best-effort preset-avatar save. Non-throwing, so the claim/error control
            // flow is byte-identical with this line removed — a save failure never blocks
            // onClaimed (the avatar self-heals on the next profile save).
            _ = await coordinator.updateAvatar(iconId: avatarIcon, colorId: avatarColor)
            didClaim = true
        } catch let e as UsernameError {
            inlineError = e.errorDescription
        } catch {
            inlineError = UsernameError.network(error.localizedDescription).errorDescription
        }
    }
}
