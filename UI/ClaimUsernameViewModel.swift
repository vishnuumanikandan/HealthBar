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

    func submit() async {
        isClaiming = true
        defer { isClaiming = false }

        do {
            try await coordinator.claimUsername(input)
            didClaim = true
        } catch let e as UsernameError {
            inlineError = e.errorDescription
        } catch {
            inlineError = UsernameError.network(error.localizedDescription).errorDescription
        }
    }
}
