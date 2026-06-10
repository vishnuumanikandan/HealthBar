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
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Pick a unique username so friends can find you.")
                    .font(AppFont.regular(15))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Username")
                    .font(AppFont.regular(14))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                HStack(spacing: 0) {
                    Text("@")
                        .font(AppFont.bold(17))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.leading, DesignSystem.Spacing.md)

                    TextField("username", text: $viewModel.input)
                        .font(AppFont.regular(DesignSystem.FontSizes.body))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
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
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(AdaptiveCardShapeStyle())
                .overlay(
                    AdaptiveCardShapeStyle()
                        .stroke(
                            viewModel.inlineError != nil
                                ? DesignSystem.Colors.danger
                                : DesignSystem.Colors.border,
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
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onChange(of: viewModel.didClaim) { _, claimed in
            if claimed { onClaimed() }
        }
    }
}
