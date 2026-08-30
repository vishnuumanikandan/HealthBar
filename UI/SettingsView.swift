//
//  SettingsView.swift
//  HealthBar
//
//  Created by Claude on 7/12/26.
//

import SwiftUI

/// R7b §2: the app's settings, moved wholesale out of ProfileView and reached from a gear in
/// Profile's top-right toolbar. A pushed screen inside Profile's existing NavigationStack
/// (FriendsView precedent) — it constructs NO view model of its own; the values passed in are
/// its entire data surface. Returning to Profile triggers Profile's single on-return reload,
/// so SettingsView needs no reload wiring of its own.
struct SettingsView: View {

    /// Coordinator for the presented sheets (Daily Goals, Account) and the onboarding editor.
    private let coordinator: AppCoordinator
    /// Read-only — gates the Account row and the Sign Out row's guest branch.
    private let authService: any AuthService
    /// Ends the auth session (provided by ProfileView, itself from ContentView).
    private let onLogout: () -> Void
    /// Snapshot passed in for the Edit Health Profile onboarding editor (SettingsView has no VM).
    private let existingProfile: UserProfile?

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Presentation state, moved verbatim from ProfileView (Tools omitted — deleted, not moved).
    @State private var showingDailyGoals = false
    @State private var showingAccessibility = false
    @State private var showingOnboarding = false
    @State private var showingAccount = false
    @State private var showGuestSignOutWarning = false
    // FEEDBACK-1: the compose sheet + the presenter's transient "thanks" confirmation.
    @State private var showingFeedback = false
    @State private var showFeedbackConfirmation = false

    // MARK: - SECRET-1 (constants + state)

    /// Consecutive taps on the version row that toggle the hidden section.
    private static let secretMenuTapCount = 7
    /// A gap longer than this between taps abandons the run and starts over.
    private static let secretMenuTapResetSeconds: TimeInterval = 2

    /// Taps landed so far in the current run (never persisted — a relaunch starts at zero).
    @State private var secretTapRun = 0
    /// Pending "the run went cold" reset; cancelled and replaced by each new tap.
    @State private var secretTapResetTask: Task<Void, Never>?

    /// Whether the hidden section is showing. Device-scoped and never synced, the same
    /// shape as `textSizePreference` — once revealed it stays revealed across launches,
    /// and repeating the taps hides it again.
    @AppStorage("secretMenuRevealed") private var secretMenuRevealed = false

    /// The version row's subtitle, reading the shipped marketing version exactly the way
    /// `DataManager.submitFeedback` stamps it.
    private static var appVersionSubtitle: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "Version \(version)"
    }

    // MARK: - TABVIS-1b (build gate + debug flags)

    /// Whether this build may expose the TABVIS-1b diagnostics UI.
    ///
    /// What this proves is **App-Store-exclusion**, NOT TestFlight-exclusivity: App Store
    /// builds carry a production receipt and resolve `false`, TestFlight builds carry a
    /// `sandboxReceipt` and resolve `true` — and development/sandbox installs also resolve
    /// `true`, which is accepted. The invariant that matters is that a shipped App Store
    /// build can never reach this UI.
    ///
    /// This is the gate's single owning site; `FoodDatabaseView` reads it as
    /// `SettingsView.isDebugOrTestFlight`.
    static var isDebugOrTestFlight: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// TABVIS-1b diagnostics overlay on the Food Database strip. Device-local DEBUG state,
    /// not user data — deliberately NOT uid-scoped and never synced. Read here only to
    /// bind the toggle below; every consuming read goes through a gated computed (D3).
    @AppStorage("debug.stripDiagnostics") private var stripDiagnostics = false

    /// TABVIS-1b experimental v2 tab strip. Same storage semantics as above. Defaults OFF
    /// and stays OFF: this PR does not adopt v2 as the production path under any outcome.
    @AppStorage("debug.tabStripV2") private var tabStripV2 = false

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onLogout: @escaping () -> Void,
        existingProfile: UserProfile?
    ) {
        self.coordinator = coordinator
        self.authService = authService
        self.onLogout = onLogout
        self.existingProfile = existingProfile
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Daily Goals button - navigates to goal editing
                settingButton(
                    icon: "target",
                    title: "Daily Goals",
                    subtitle: "Customize your targets",
                    action: {
                        showingDailyGoals = true
                    }
                )

                // Accessibility button - navigates to accessibility settings
                settingButton(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "Display & notification preferences",
                    action: {
                        showingAccessibility = true
                    }
                )
                // TUT-1b changeTheme beacon (Decision 7) — the Accessibility row leads to the theme picker.
                // settingButton is an adaptiveCard — match its radius exactly.
                .questBeacon(TutorialCatalog.changeThemeId, cornerRadius: DesignSystem.Erewhon.cardRadius)

                // Edit Health Profile — opens onboarding in edit mode
                settingButton(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Edit Health Profile",
                    subtitle: "Update your goals and preferences",
                    iconColor: tc.primary,
                    action: { showingOnboarding = true }
                )

                // WATER-1 D5: Water Unit — directly below Edit Health Profile, and ONLY
                // while the tracker is on. Hidden when the toggle is off even if a stored
                // preference exists.
                if settings.waterTrackerEnabled {
                    waterUnitRow
                }

                // Account button — hidden for guest users (requires a real account)
                if !authService.isGuest {
                    settingButton(
                        icon: "person.circle",
                        title: "Account",
                        subtitle: "Manage username, display name, password",
                        action: { showingAccount = true }
                    )
                }

                // Send Feedback — hidden for guests (writes to the signed-in
                // account; mirrors the Account row's guest gating). Sits directly
                // above About.
                if !authService.isGuest {
                    settingButton(
                        icon: "envelope",
                        title: "Send Feedback",
                        subtitle: "Tell the developer what's working — or not",
                        action: { showingFeedback = true }
                    )
                }

                // About — the app-version row. SECRET-1 hangs the reveal gesture here:
                // `secretMenuTapCount` taps in a row toggle the hidden section below.
                // TODO-about-screen: this row still has no destination; the tap handler
                // is the reveal counter, not navigation.
                settingButton(
                    icon: "info.circle",
                    title: "About",
                    subtitle: Self.appVersionSubtitle,
                    action: { registerSecretTap() }
                )

                // Sign Out — for guests shows a warning before deleting local data
                settingButton(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    subtitle: authService.isGuest
                        ? "Delete local data and exit guest mode"
                        : "Log out of your account",
                    iconColor: DesignSystem.Colors.danger,
                    isDanger: true,
                    action: {
                        if authService.isGuest {
                            showGuestSignOutWarning = true
                        } else {
                            onLogout()
                        }
                    }
                )

                // SECRET-1: the hidden section, last so revealing it never reflows the
                // rows above. Toggled by the version row's tap run.
                if secretMenuRevealed {
                    secretSection
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(tc.primaryBackground.ignoresSafeArea())
        // FEEDBACK-1: the presenter's transient success confirmation, shown after
        // the compose sheet dismisses and auto-hidden after 2s (set in the sheet's
        // onSuccess closure below).
        .overlay(alignment: .bottom) {
            if showFeedbackConfirmation {
                Text("Thanks — your feedback was sent.")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .adaptiveCard(
                        borderColor: tc.primary.opacity(0.3),
                        fillColor: tc.cardBackground
                    )
                    .padding(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(AppFont.display(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        // R2 §5: reserve the bottom tab bar's height (the TabView's bottom safeAreaInset
        // doesn't reach this pushed screen's ScrollView).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
        .sheet(isPresented: $showingDailyGoals) {
            DailyGoalsView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingAccessibility) {
            AccessibilitySettingsView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingAccount) {
            AccountView(coordinator: coordinator, authService: FirebaseAuthService.shared)
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackComposeView(coordinator: coordinator) {
                // Success: show the presenter's transient confirmation for 2s.
                withAnimation { showFeedbackConfirmation = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showFeedbackConfirmation = false }
                }
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                coordinator: coordinator,
                authService: FirebaseAuthService.shared,
                existingProfile: existingProfile
            )
        }
        // Guest sign-out warning: deleting local data is irreversible
        .confirmationDialog(
            "Sign Out of Guest Mode?",
            isPresented: $showGuestSignOutWarning,
            titleVisibility: .visible
        ) {
            Button("Sign Out & Delete Data", role: .destructive) {
                Task {
                    try? await coordinator.deleteAllGuestData()
                    onLogout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're using guest mode. Signing out will delete all local data. Create a free account first to save your progress.")
        }
    }

    // MARK: - SECRET-1 (section + reveal gesture)

    /// The hidden section. Deliberately unlabelled — finding it is the joke.
    private var secretSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("???")
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignSystem.Spacing.md)

            PoopCounterCard(userId: authService.currentUserEmail ?? "guest")

            // TABVIS-1b: diagnostics rows. Doubly gated — the SECRET-1 section must be
            // revealed AND the build must be Debug/TestFlight, so a shipped App Store
            // build renders nothing here even if the hidden section is showing.
            if Self.isDebugOrTestFlight {
                Text("DIAGNOSTICS (TestFlight only)")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DesignSystem.Spacing.md)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Toggle(isOn: $stripDiagnostics) {
                        Text("Strip Diagnostics")
                            .font(AppFont.regular(DesignSystem.FontSizes.body))
                            .foregroundColor(tc.textPrimary)
                    }
                    .tint(tc.primary)

                    Toggle(isOn: $tabStripV2) {
                        Text("Tab Strip v2 — experimental")
                            .font(AppFont.regular(DesignSystem.FontSizes.body))
                            .foregroundColor(tc.textPrimary)
                    }
                    .tint(tc.primary)
                }
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(
                    borderColor: tc.primary.opacity(0.3),
                    fillColor: tc.cardBackground
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Counts taps on the version row. The `secretMenuTapCount`-th consecutive tap
    /// toggles the hidden section — revealing it, or hiding it again if it is already
    /// showing — and the run restarts. A pause longer than `secretMenuTapResetSeconds`
    /// abandons the run, so stray taps never accumulate into an accidental reveal.
    private func registerSecretTap() {
        secretTapResetTask?.cancel()
        secretTapRun += 1

        guard secretTapRun >= Self.secretMenuTapCount else {
            // Task.sleep, not Timer (project convention).
            secretTapResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.secretMenuTapResetSeconds))
                guard !Task.isCancelled else { return }
                secretTapRun = 0
            }
            return
        }

        secretTapRun = 0
        secretTapResetTask = nil
        withAnimation(DesignSystem.Erewhon.ease(0.25)) {
            secretMenuRevealed.toggle()
        }
    }

    // MARK: - Water Unit (WATER-1 D5)

    /// Display-unit control for the water tracker. Segmented, in the WeeklySummaryView
    /// `.seg` convention (recessed track + raised active pill), using existing tokens.
    /// Storage stays cups-canonical — this only changes what is rendered.
    private var waterUnitRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "drop.fill")
                    .font(AppFont.bold(18))
                    .foregroundColor(.white)
                    .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)
                    .adaptivePill(
                        borderColor: settings.isCleanUI ? .clear : tc.primary.adjustedBrightness(-0.2),
                        fillColor: .clear,
                        fillGradient: DesignSystem.Colors.adaptiveGradientFrom(tc.primary)
                    )

                Text("Water Unit")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)

                Spacer()
            }

            HStack(spacing: 2) {
                ForEach(WaterUnit.allCases, id: \.self) { unit in
                    let isSelected = settings.waterUnit == unit
                    Button {
                        withAnimation(DesignSystem.Erewhon.ease(0.35)) {
                            settings.waterUnitPreference = unit.rawValue
                        }
                    } label: {
                        Text(unit.displayName)
                            .font(isSelected ? AppFont.bold(13) : AppFont.regular(13))
                            .foregroundColor(isSelected ? tc.segActiveText : tc.segInactiveText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                isSelected
                                    ? RoundedRectangle(cornerRadius: 7).fill(tc.segActiveFill)
                                    : nil
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(unit.displayName)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(tc.segBackground))
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// Reusable settings button component (moved verbatim from ProfileView).
    private func settingButton(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = SettingsManager.shared.activeColors.primary,
        isDanger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(AppFont.bold(18))
                    .foregroundColor(.white)
                    .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)
                    .adaptivePill(
                        borderColor: SettingsManager.shared.isCleanUI ? .clear : iconColor.adjustedBrightness(-0.2),
                        fillColor: .clear,
                        fillGradient: DesignSystem.Colors.adaptiveGradientFrom(iconColor)
                    )

                // Text
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)

                    Text(subtitle)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(
                borderColor: isDanger ? DesignSystem.Colors.danger : tc.primary.opacity(0.3),
                fillColor: tc.cardBackground
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Feedback Compose Sheet (FEEDBACK-1)

/// The compose sheet — a small local view (no view model, no own file, per the
/// prompt). Validation here is UX-only; `DataManager.submitFeedback` revalidates
/// and is the authority. A successful submit calls `onSuccess` then self-dismisses
/// (NOT via onDismiss/onDisappear, which fire on the success path too — the
/// AILOG-1c lesson); a failure keeps the sheet open with an inline error and Send
/// re-enabled.
private struct FeedbackComposeView: View {

    private let coordinator: AppCoordinator
    /// Called exactly once, on a successful submit, immediately before self-dismiss,
    /// so the presenter can show its transient confirmation.
    private let onSuccess: () -> Void

    init(coordinator: AppCoordinator, onSuccess: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onSuccess = onSuccess
    }

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    /// The trimmed draft — the exact value DataManager would store.
    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isOverLimit: Bool { message.count > FeedbackLimits.maxLength }
    /// Send is enabled only for a non-empty, in-bounds draft that isn't mid-send.
    private var canSend: Bool { !trimmed.isEmpty && !isOverLimit && !isSubmitting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    // Persistent label (always visible — not a placeholder).
                    Text("What's on your mind?")
                        .font(AppFont.display(16))
                        .foregroundColor(tc.textPrimary)

                    TextEditor(text: $message)
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.textPrimary)
                        .frame(minHeight: 160, maxHeight: 280)
                        .scrollContentBackground(.hidden)
                        .padding(DesignSystem.Spacing.sm)
                        .adaptiveCard(
                            borderColor: tc.primary.opacity(0.3),
                            fillColor: tc.primaryBackground
                        )
                        .accessibilityLabel("Feedback message")

                    // Live character counter — appears only past the threshold.
                    if message.count > FeedbackLimits.counterThreshold {
                        Text("\(message.count) / \(FeedbackLimits.maxLength)")
                            .font(AppFont.regular(12))
                            .foregroundColor(isOverLimit ? DesignSystem.Colors.danger : tc.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // Failure path: inline error; the sheet stays open and Send
                    // re-enables (isSubmitting is reset in submit()'s catch).
                    if let errorText {
                        Text(errorText)
                            .font(AppFont.regular(13))
                            .foregroundColor(DesignSystem.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    AppButton(
                        title: "Send",
                        style: .primary,
                        action: { submit() },
                        isLoading: isSubmitting,
                        isDisabled: !canSend
                    )
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Send Feedback")
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
    }

    private func submit() {
        // Double-tap guard: canSend is already false while isSubmitting and
        // AppButton ignores taps while isLoading — this belt-and-suspenders re-check
        // ensures a queued tap can't open a second write.
        guard canSend else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                try await coordinator.submitFeedback(message: message)
                onSuccess()
                dismiss()
            } catch {
                errorText = "Couldn't send your feedback. Check your connection and try again."
                isSubmitting = false
            }
        }
    }
}

// MARK: - Poop Counter (SECRET-1)

/// The hidden section's one feature: a tally that resets every month and earns nothing.
///
/// A small local view in this file (the `FeedbackComposeView` precedent) — no view model,
/// no manager, no persistence layer, no new abstraction. It earns NOTHING on purpose:
/// there is no `GamificationManager` call here, no XP, no badge, no streak, no
/// notification. Nothing it stores is read by anything else.
private struct PoopCounterCard: View {

    /// Scopes the stored count, mirroring the `userId` scoping every local model uses.
    /// `"guest"` is local scoping only — nothing leaves the device in either case.
    let userId: String

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// This month's count — loaded on appear, rewritten by each increment.
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text("💩")
                    .font(AppFont.regular(28))

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Poop Counter")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)

                    Text(count == 1 ? "1 so far this month" : "\(count) so far this month")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()
            }

            // AppButton already carries the press haptic (.sensoryFeedback, DesignSystem)
            // — adding a second one here would buzz twice per tap.
            AppButton(
                title: "Log One",
                style: .primary,
                action: { increment() }
            )
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: tc.primary.opacity(0.3),
            fillColor: tc.cardBackground
        )
        .accessibilityElement(children: .contain)
        .onAppear { count = Self.storedCount(userId: userId) }
    }

    /// Bumps this month's count and persists it. Recomputing the key from `Date()` on
    /// every write is what makes the rollover free: on the 1st of a new month the key is
    /// new, so it reads 0 and this writes 1.
    private func increment() {
        let key = Self.monthKey(userId: userId)
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        count = next
    }

    // MARK: Storage
    //
    // local-only by design — TODO-poop-leaderboard would need a projection, not this store

    /// This month's stored count. A key that has never been written reads as 0, which is
    /// exactly the wanted behaviour for a month that hasn't started yet.
    private static func storedCount(userId: String) -> Int {
        UserDefaults.standard.integer(forKey: monthKey(userId: userId))
    }

    /// This user's key for the month containing right now.
    private static func monthKey(userId: String) -> String {
        poopCountKey(userId: userId, date: Date(), calendar: localGregorianCalendar)
    }

    /// Explicitly Gregorian, in the user's own time zone. Built fresh per access so a
    /// travelling user's time-zone change is picked up (a cached `static let` would
    /// freeze the zone at first launch).
    private static var localGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    /// The UserDefaults key holding one user's count for one month:
    /// `poopCount.<userId>.<yyyyMM>`. Months roll over naturally by key — a new month
    /// simply reads a key that doesn't exist yet and starts at zero. Old months are left
    /// in place; the bytes are trivial and there is nothing to clean up.
    ///
    /// Manual zero-padding via an explicit Gregorian calendar, mirroring `utcDayKey` in
    /// FirestoreServiceImpl. `DateFormatter` is deliberately NOT used: it is locale- and
    /// calendar-sensitive, so a Buddhist-calendar device would write year 2569 and an
    /// Arabic-Indic locale would write non-ASCII digits — either silently stranding the
    /// count under a key nothing else reads. Unlike the `aiUsage` day keys this one
    /// matches no server key, so it uses the user's own zone: "this month" is the user's
    /// month, not UTC's.
    private static func poopCountKey(userId: String, date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "poopCount.\(userId).\(String(format: "%04d%02d", c.year ?? 0, c.month ?? 0))"
    }
}
