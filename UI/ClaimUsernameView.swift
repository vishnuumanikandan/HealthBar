//
//  ClaimUsernameView.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import SwiftUI

struct ClaimUsernameView: View {

    @State private var viewModel: ClaimUsernameViewModel
    var onClaimed: () -> Void

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    init(coordinator: AppCoordinator, onClaimed: @escaping () -> Void) {
        self._viewModel = State(
            initialValue: ClaimUsernameViewModel(coordinator: coordinator)
        )
        self.onClaimed = onClaimed
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Choose your handle")
                    .font(AppFont.bold(28))
                    .foregroundColor(tc.textPrimary)

                Text("Pick a unique username so friends can find you.")
                    .font(AppFont.regular(15))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Username")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)

                HStack(spacing: 0) {
                    Text("@")
                        .font(AppFont.bold(17))
                        .foregroundColor(tc.textSecondary)
                        .padding(.leading, DesignSystem.Spacing.md)

                    TextField("username", text: $viewModel.input)
                        .font(AppFont.regular(DesignSystem.FontSizes.body))
                        .foregroundColor(tc.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.leading, DesignSystem.Spacing.xs)
                        .padding(.trailing, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .submitLabel(.done)
                        .onSubmit {
                            if viewModel.isSubmittable {
                                Task { await viewModel.submit() }
                            }
                        }
                }
                .frame(minHeight: 52)
                .background(tc.cardBackground)
                .clipShape(AdaptiveCardShapeStyle())
                .overlay(
                    AdaptiveCardShapeStyle()
                        .stroke(
                            viewModel.inlineError != nil
                                ? DesignSystem.Colors.danger
                                : tc.primary.opacity(0.3),
                            lineWidth: viewModel.inlineError != nil ? 2 : 1
                        )
                )

                if let error = viewModel.inlineError {
                    Text(error)
                        .font(AppFont.regular(12))
                        .foregroundColor(DesignSystem.Colors.danger)
                }
            }

            AppButton(
                title: "Continue",
                style: .primary,
                action: { Task { await viewModel.submit() } },
                isLoading: viewModel.isClaiming,
                isDisabled: !viewModel.isSubmittable
            )

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .background(tc.primaryBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onChange(of: viewModel.didClaim) { _, claimed in
            if claimed { onClaimed() }
        }
    }
}
