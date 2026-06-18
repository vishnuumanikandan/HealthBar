//
//  SharedInboxSection.swift
//  HealthBar
//
//  Created by Claude on 6/12/26.
//

import SwiftUI

/// "Shared with you" inbox strip (Friend System Phase 9), pinned at the top of
/// the Friends tab.
///
/// Loads BOTH kinds (meal + recipe) — each via a server-side `whereField`
/// filter — and merges them newest-first. Fetch-on-view, in memory: shares are
/// transient (deleted on save/dismiss), so this follows the leaderboard/feed
/// precedent — no listener, no SwiftData model. Hidden entirely when empty or
/// for guests. Tapping a row opens a preview with Save / Dismiss; Save imports a
/// copy into the user's own meals/recipes via the existing pipeline.
struct SharedInboxSection: View {

    private let coordinator: AppCoordinator

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var items: [SharedItemDTO] = []
    @State private var expanded = true
    @State private var previewItem: SharedItemDTO? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        Group {
            if !coordinator.isGuest && !items.isEmpty {
                strip
            }
        }
        // Once per appearance of the Friends segment.
        .task {
            guard !coordinator.isGuest else { return }
            await load()
        }
        .sheet(item: $previewItem) { item in
            SharedItemPreviewSheet(coordinator: coordinator, item: item) { resolved, _ in
                items.removeAll { $0.id == resolved.id }
            }
        }
    }

    private var strip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.primary)
                    Text("Shared with you (\(items.count))")
                        .font(AppFont.bold(15))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(AppFont.bold(12))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if expanded {
                ForEach(items) { item in
                    inboxRow(item)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
    }

    private func inboxRow(_ item: SharedItemDTO) -> some View {
        Button {
            previewItem = item
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: item.kind == "recipe" ? "list.bullet.rectangle.fill" : "rectangle.stack.fill")
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(AppFont.bold(14))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    Text("from \(item.senderName)")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(Self.relativeFormatter.localizedString(for: item.createdAt ?? .distantPast, relativeTo: Date()))
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textTertiary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(AppFont.bold(12))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .adaptiveCard(borderColor: tc.primary.opacity(0.2), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func load() async {
        // Single all-kinds, server-ordered fetch (no composite index needed).
        items = await coordinator.loadSharedItems()
    }
}

/// Preview of a single shared meal/recipe (Friend System Phase 9): the decoded
/// component list with per-item and total macros (recipes also show yield +
/// purity), and Save / Dismiss actions. An unreadable share (bad/empty JSON or
/// negative macros) offers Dismiss only.
struct SharedItemPreviewSheet: View {

    private let coordinator: AppCoordinator
    let item: SharedItemDTO

    /// (item, saved) — saved == true after an import, false after a dismiss, so
    /// the host removes the row and refreshes its collection only on save.
    let onResolved: (SharedItemDTO, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var isWorking = false
    @State private var errorMessage: String? = nil
    @State private var showDismissConfirm = false
    @State private var savedConfirmation = false

    init(coordinator: AppCoordinator, item: SharedItemDTO, onResolved: @escaping (SharedItemDTO, Bool) -> Void) {
        self.coordinator = coordinator
        self.item = item
        self.onResolved = onResolved
    }

    private var components: [SavedMealComponent] {
        guard let data = item.contentJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedMealComponent].self, from: data) else { return [] }
        return decoded
    }

    /// Mirrors the import-side validation: non-empty and all macros non-negative.
    private var isReadable: Bool {
        !components.isEmpty && components.allSatisfy {
            $0.calories >= 0 && $0.protein >= 0 && $0.carbs >= 0 && $0.fat >= 0 && $0.quantity >= 0
        }
    }

    private var isRecipe: Bool { item.kind == "recipe" }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        header
                        if isReadable {
                            componentsCard
                            totalsCard
                        } else {
                            unreadableCard
                        }
                        if let errorMessage {
                            inlineError(errorMessage)
                        }
                        actionButtons
                    }
                    .padding(DesignSystem.Spacing.lg)
                }

                if savedConfirmation {
                    savedToast
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isRecipe ? "Shared recipe" : "Shared meal")
                        .font(AppFont.bold(18))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(tc.primary)
                }
            }
        }
        .confirmationDialog("Dismiss this share?", isPresented: $showDismissConfirm, titleVisibility: .visible) {
            Button("Dismiss", role: .destructive) { Task { await performDismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from your inbox.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(item.name)
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)
                .multilineTextAlignment(.center)
            Text("from \(item.senderName)")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
            if isRecipe {
                Text("\(item.yield) serving\(item.yield == 1 ? "" : "s") · Purity \(item.purityScore)")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
    }

    private var componentsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(isRecipe ? "Ingredients" : "Items")
                .font(AppFont.bold(15))
                .foregroundColor(tc.textPrimary)

            ForEach(components) { component in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(component.foodName)
                            .font(AppFont.regular(14))
                            .foregroundColor(tc.textPrimary)
                            .lineLimit(1)
                        Text(servingText(component))
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }
                    Spacer()
                    Text("\(component.calories) cal · P\(Int(component.protein)) C\(Int(component.carbs)) F\(Int(component.fat))")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textSecondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var totalsCard: some View {
        let cal = components.reduce(0) { $0 + $1.calories }
        let p = components.reduce(0.0) { $0 + $1.protein }
        let c = components.reduce(0.0) { $0 + $1.carbs }
        let f = components.reduce(0.0) { $0 + $1.fat }
        return HStack {
            Text("Total")
                .font(AppFont.bold(15))
                .foregroundColor(tc.textPrimary)
            Spacer()
            Text("\(cal) cal · P\(Int(p)) C\(Int(c)) F\(Int(f))")
                .font(AppFont.bold(13))
                .foregroundColor(tc.textPrimary)
                .monospacedDigit()
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    private var unreadableCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.regular(32))
                .foregroundColor(DesignSystem.Colors.warning)
            Text("This share couldn't be read")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
            Text("Its contents are missing or invalid. You can dismiss it from your inbox.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: DesignSystem.Colors.warning.opacity(0.4), fillColor: tc.cardBackground)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            if isReadable {
                AppButton(
                    title: isRecipe ? "Save to my recipes" : "Save to my meals",
                    style: .primary,
                    action: { Task { await save() } }
                )
                .disabled(isWorking)
            }
            AppButton(
                title: "Dismiss",
                style: .secondary,
                action: { showDismissConfirm = true }
            )
            .disabled(isWorking)
        }
        .padding(.top, DesignSystem.Spacing.sm)
    }

    private var savedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(tc.primary)
                Text(isRecipe ? "Added to your recipes" : "Added to your meals")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.5), fillColor: tc.cardBackground)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.danger)
            Text(message)
                .font(AppFont.regular(12))
                .foregroundColor(DesignSystem.Colors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func servingText(_ component: SavedMealComponent) -> String {
        let qty = component.quantity
        let qtyStr = qty.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(qty)) : String(format: "%.1f", qty)
        return "\(qtyStr) \(component.servingUnit)"
    }

    // MARK: - Actions

    private func save() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await coordinator.importSharedItem(item)
            withAnimation { savedConfirmation = true }
            try? await Task.sleep(for: .seconds(0.9))
            onResolved(item, true)
            dismiss()
        } catch {
            if case ShareError.malformed = error {
                errorMessage = "This share couldn't be read."
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save. Try again."
            }
            isWorking = false
        }
    }

    private func performDismiss() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await coordinator.dismissSharedItem(item)
            onResolved(item, false)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't dismiss. Try again."
            isWorking = false
        }
    }
}
