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

    // D7: avatar selection lives locally in the view (default preselected); the picker
    // updates it, and the actual persist is best-effort on successful claim.
    @State private var selectedIcon = AvatarCatalog.defaultIcon
    @State private var selectedColor = AvatarCatalog.defaultColor
    @State private var showAvatarPicker = false

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
                Text("Choose your identity")
                    .font(AppFont.bold(28))
                    .foregroundColor(tc.textPrimary)

                Text("Pick an avatar and a unique username so friends can find you.")
                    .font(AppFont.regular(15))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // D7: avatar preview (default preselected) + small edit affordance. Tapping opens
            // the shared picker; sel ids are always valid catalog ids so the fallback never shows.
            Button {
                showAvatarPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(iconId: selectedIcon, colorId: selectedColor, size: 88) { EmptyView() }
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tc.primary))
                        .overlay(Circle().stroke(tc.primaryBackground, lineWidth: 3))
                }
            }
            .buttonStyle(.plain)

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
                                Task { await viewModel.submit(avatarIcon: selectedIcon, avatarColor: selectedColor) }
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
                action: { Task { await viewModel.submit(avatarIcon: selectedIcon, avatarColor: selectedColor) } },
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
        .sheet(isPresented: $showAvatarPicker) {
            // Onboarding presenter: the picker's Save just updates the local selection
            // (persist happens best-effort on claim), so onSave always "succeeds".
            AvatarPickerSheet(iconId: selectedIcon, colorId: selectedColor) { icon, color in
                selectedIcon = icon
                selectedColor = color
                return true
            }
        }
    }
}
