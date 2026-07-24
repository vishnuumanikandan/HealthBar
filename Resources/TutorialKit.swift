//
//  TutorialKit.swift
//  HealthBar
//
//  Created by Claude on 7/23/26.
//
//  TUT-1a — First-session tutorial: state core + the two on-screen surfaces, in
//  one shared file (the AvatarKit organization):
//    • TutorialCatalog       — a STATIC namespace: compile-time step table + lookup.
//    • TutorialState          — the tutorial's read model (seen / skipped / completed).
//    • TutorialWelcomePopup   — the 3-page centered welcome card (overlay).
//    • FirstQuestsCard        — the pinned Home card that tracks tutorial progress.
//
//  Step ids are the PERMANENT wire contract — they are stored in the Firestore
//  UserProgress doc (never as SwiftData quest rows; the catalog is compile-time and
//  never resets daily). Never rename an id; new steps require explicit pinned ids.
//  An unknown id anywhere (a future app version echoing a newer step down) is ignored
//  silently — no logging, no assertion — exactly like AvatarCatalog's unknown-id path.
//
//  The pure half (TutorialCatalog + TutorialState) is Foundation-only and locked by a
//  standalone swiftc spec (the HealthBar scheme has no <Testables>); the SwiftUI paint
//  half is verified by compilation + the Acceptance Checklist.
//

import SwiftUI

// MARK: - Catalog

/// The single source of truth for tutorial steps. A STATIC NAMESPACE ONLY — no
/// singleton, no ObservableObject, no runtime mutation, never a `TutorialManager`.
/// Steps are compile-time definitions; they never enter the DailyQuest model, never
/// reset daily, and never sync as quest docs.
enum TutorialCatalog {

    /// One tutorial step. `id` is the permanent wire contract; `ordinal` (1…6) drives
    /// display order and the pinned-card disc; `detail` is the "where to go" line;
    /// `xp` is the one-time award (Decision 9). No magic numbers live at call sites —
    /// every XP value is read from `step.xp`.
    struct TutorialStep: Identifiable, Equatable {
        let id: String
        let ordinal: Int
        let title: String
        let detail: String
        let xp: Int
    }

    /// The six pinned tutorial steps, in pinned order (Decision 2), with the XP from
    /// Decision 9. XP total = 150 (30 + 30 + 20 + 25 + 25 + 20). Ids are stored in the
    /// Firestore UserProgress doc — NEVER rename; a new step gets an explicit pinned id.
    static let steps: [TutorialStep] = [
        TutorialStep(id: "quickLog",    ordinal: 1, title: "Quick-log a meal",           detail: "Use quick log on Home to add your first meal", xp: 30),
        TutorialStep(id: "databaseLog", ordinal: 2, title: "Log from the food database", detail: "Open the Log tab and add anything",            xp: 30),
        TutorialStep(id: "checkQuests", ordinal: 3, title: "Check your daily quests",     detail: "Find today's quests on Home",                  xp: 20),
        TutorialStep(id: "visitBattle", ordinal: 4, title: "Learn how duels work",        detail: "Visit the Battle tab",                         xp: 25),
        TutorialStep(id: "visitGuild",  ordinal: 5, title: "Check out a guild",           detail: "Open any guild from the directory",            xp: 25),
        TutorialStep(id: "changeTheme", ordinal: 6, title: "Try a new theme",             detail: "Settings → appearance",                        xp: 20),
    ]

    /// The set of all catalog step ids — the target of the `done` superset check.
    static let allIds: Set<String> = Set(steps.map { $0.id })

    /// Resolves a step id to its definition, or nil for an unknown id. Unknown ids are
    /// ignored everywhere (no logging, no assertion) — future-proofs later additions.
    static func step(id: String) -> TutorialStep? {
        steps.first { $0.id == id }
    }
}

// MARK: - State

/// The tutorial's read model — no ad-hoc tuples. `done` is defined HERE and only here
/// (Decision 5); `UserProgress.tutorialDone` delegates to it rather than restating the
/// predicate. Monotonic by construction upstream: `completed` only grows, the bools only
/// go false→true (see DataManager's union/OR merge).
struct TutorialState: Equatable {
    let seen: Bool
    let skipped: Bool
    let completed: Set<String>

    /// Done := skipped OR every catalog id completed. A superset (an extra unknown id
    /// from a future version) still counts as done — the check is against `allIds`.
    var done: Bool { skipped || completed.isSuperset(of: TutorialCatalog.allIds) }

    /// Guests are excluded entirely (Decision 7): treated as seen + skipped ⇒ done, so
    /// no popup, no pinned card, no writes.
    static let guest = TutorialState(seen: true, skipped: true, completed: [])
}

// MARK: - Welcome Popup

/// The 3-page welcome card, shown as a centered OVERLAY over the dimmed Home (never a
/// sheet / fullScreenCover). Owns NO persistence — it takes `onStart` / `onSkip`
/// closures the presenter wires (the AvatarPickerSheet `onSave` precedent) and never
/// touches AppCoordinator, DataManager, or any store. `isReplay` (Settings replay) is
/// visually identical; the presenter simply supplies dismiss-only closures.
struct TutorialWelcomePopup: View {

    /// Handle for the greeting, or nil ⇒ "Hey there". Sourced by the presenter.
    let username: String?
    /// Read-only replay (Settings). Visuals identical; only the a11y verb differs.
    var isReplay: Bool = false
    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    private var pageAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.32)
    }

    var body: some View {
        ZStack {
            // Dim scrim over the live Home content. Absorbs taps (no scrim-dismiss —
            // the tutorial requires an explicit Start / Skip choice).
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            card
                .frame(maxWidth: 340)
                .padding(DesignSystem.Spacing.lg)
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // SKIP persists on every page (Decision / spec).
            HStack {
                Spacer()
                Button(action: onSkip) {
                    Text("SKIP")
                        .font(AppFont.bold(11))
                        .tracking(1.4)
                        .foregroundColor(tc.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReplay ? "Close" : "Skip tutorial")
            }

            // Paged content — only the current page mounts, so each page re-stages its
            // entrance on every visit (per-page cascade). Page-to-page is a crossfade.
            Group {
                switch page {
                case 0: TutorialGreetingPage(greeting: greeting, tc: tc, reduceMotion: reduceMotion)
                case 1: TutorialLoopPage(tc: tc, reduceMotion: reduceMotion)
                default: TutorialQuestsPage(tc: tc, reduceMotion: reduceMotion, onStart: onStart)
                }
            }
            .transition(.opacity)
            .id(page)

            pageDots
        }
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true)
        .shadow(color: Color.black.opacity(0.32), radius: 22, y: 12)
        // Swipe to page (the dots signal paging; pages 1–2 have no button).
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width
                    if dx < -44, page < 2 {
                        withAnimation(pageAnimation) { page += 1 }
                    } else if dx > 44, page > 0 {
                        withAnimation(pageAnimation) { page -= 1 }
                    }
                }
        )
    }

    private var greeting: String {
        if let username, !username.isEmpty { return "Hey @\(username)" }
        return "Hey there"
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == page ? tc.primary : tc.textTertiary.opacity(0.35))
                    .frame(width: i == page ? 14 : 4, height: 4)
                    .animation(pageAnimation, value: page)
            }
        }
        .padding(.top, DesignSystem.Spacing.xs)
    }
}

// MARK: Welcome Popup — pages

/// Page 1 — greeting: spark ring, WELCOME meta line, "Hey @handle", tagline.
private struct TutorialGreetingPage: View {
    let greeting: String
    let tc: ThemeColors
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(tc.primary, lineWidth: 2)
                    .frame(width: 56, height: 56)
                Image(systemName: "sparkles")
                    .font(AppFont.regular(22))
                    .foregroundColor(tc.primary)
            }
            .shadow(color: tc.primary.opacity(0.35), radius: 14)
            .modifier(TutorialReveal(index: 0, shown: shown, reduceMotion: reduceMotion))

            TutorialMetaLine(text: "WELCOME", tc: tc)
                .modifier(TutorialReveal(index: 1, shown: shown, reduceMotion: reduceMotion))

            Text(greeting)
                .font(AppFont.display(28))
                .foregroundColor(tc.textPrimary)
                .modifier(TutorialReveal(index: 2, shown: shown, reduceMotion: reduceMotion))

            Text("Overheal turns eating well into a game you can win.")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(TutorialReveal(index: 3, shown: shown, reduceMotion: reduceMotion))
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .onAppear { shown = true }
    }
}

/// Page 2 — the loop: four hairline-separated rows (icon + title + one-line sub).
private struct TutorialLoopPage: View {
    let tc: ThemeColors
    let reduceMotion: Bool
    @State private var shown = false

    private struct Row: Identifiable { let id = UUID(); let icon: String; let title: String; let sub: String }
    private let rows: [Row] = [
        Row(icon: "fork.knife",         title: "Log what you eat",   sub: "Describe it, scan it, or pick it"),
        Row(icon: "star.fill",          title: "Earn XP and streaks", sub: "Quests reward eating clean"),
        Row(icon: "trophy.fill",        title: "Climb the ranks",    sub: "Stone to Zenith, one day at a time"),
        Row(icon: "flag.2.crossed.fill", title: "Duel your friends",  sub: "Best eating wins the day"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TutorialMetaLine(text: "THE LOOP", tc: tc)
                .padding(.bottom, DesignSystem.Spacing.xs)
                .modifier(TutorialReveal(index: 0, shown: shown, reduceMotion: reduceMotion))

            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                let row = pair.element
                if pair.offset > 0 {
                    Rectangle().fill(tc.textPrimary.opacity(0.08)).frame(height: 1)
                }
                HStack(spacing: 11) {
                    Image(systemName: row.icon)
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.primary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(AppFont.bold(13))
                            .foregroundColor(tc.textPrimary)
                        Text(row.sub)
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .modifier(TutorialReveal(index: pair.offset + 1, shown: shown, reduceMotion: reduceMotion))
            }
        }
        .onAppear { shown = true }
    }
}

/// Page 3 — first quests: the six catalog steps with XP, primary CTA, badge microcopy.
private struct TutorialQuestsPage: View {
    let tc: ThemeColors
    let reduceMotion: Bool
    let onStart: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            TutorialMetaLine(text: "FIRST QUESTS", tc: tc)
                .modifier(TutorialReveal(index: 0, shown: shown, reduceMotion: reduceMotion))

            Text("Six quests. Finish them all for a badge.")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
                .modifier(TutorialReveal(index: 1, shown: shown, reduceMotion: reduceMotion))

            VStack(spacing: 0) {
                ForEach(Array(TutorialCatalog.steps.enumerated()), id: \.element.id) { pair in
                    let step = pair.element
                    if pair.offset > 0 {
                        Rectangle().fill(tc.textPrimary.opacity(0.08)).frame(height: 1)
                    }
                    HStack {
                        Text(step.title)
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textPrimary)
                        Spacer(minLength: 8)
                        Text("+\(step.xp) XP")
                            .font(AppFont.bold(11))
                            .foregroundColor(tc.primary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 11)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Erewhon.buttonRadius)
                    .stroke(tc.textPrimary.opacity(0.10), lineWidth: 1)
            )
            .padding(.top, DesignSystem.Spacing.xs)
            .modifier(TutorialReveal(index: 2, shown: shown, reduceMotion: reduceMotion))

            AppButton(title: "Start your first quest", style: .primary, action: onStart)
                .padding(.top, DesignSystem.Spacing.xs)
                .modifier(TutorialReveal(index: 3, shown: shown, reduceMotion: reduceMotion))

            Text("Tutorial complete badge awaits")
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)
                .modifier(TutorialReveal(index: 4, shown: shown, reduceMotion: reduceMotion))
        }
        .onAppear { shown = true }
    }
}

/// Tracked-uppercase meta line flanked by hairlines (the mockup's `— WELCOME —`).
private struct TutorialMetaLine: View {
    let text: String
    let tc: ThemeColors

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(tc.textTertiary.opacity(0.4)).frame(width: 18, height: 1)
            Text(text)
                .font(AppFont.bold(10))
                .tracking(1.8)
                .foregroundColor(tc.textTertiary)
            Rectangle().fill(tc.textTertiary.opacity(0.4)).frame(width: 18, height: 1)
        }
    }
}

/// Staged fade/rise for popup elements — mirrors HomeView's EntranceReveal idiom. Reduce
/// Motion drops the vertical movement (crossfade only) and the per-element delay.
private struct TutorialReveal: ViewModifier {
    let index: Int
    let shown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : (reduceMotion ? 0 : 10))
            .animation(reduceMotion
                       ? .easeIn(duration: 0.25)
                       : .easeOut(duration: 0.38).delay(Double(index) * 0.06),
                       value: shown)
    }
}

// MARK: - First-Quests Card

/// The pinned Home card that tracks tutorial progress. Owns NO persistence — it takes a
/// resolved `TutorialState` and an `onSkip` closure (the presenter wires it). Renders
/// nothing once the tutorial is done (the unloaded / guest case is filtered by the
/// caller's `if let`). Card body tap is inert (Decision 13 — navigation is TUT-1b).
struct FirstQuestsCard: View {
    let state: TutorialState
    let onSkip: () -> Void

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    /// Lowest-ordinal step not yet completed. nil only when all are done (⇒ card hidden).
    private var currentStep: TutorialCatalog.TutorialStep? {
        TutorialCatalog.steps.first { !state.completed.contains($0.id) }
    }

    /// Completed count, guarded to catalog ids so a future unknown id can't inflate it.
    private var completedCount: Int {
        state.completed.intersection(TutorialCatalog.allIds).count
    }

    var body: some View {
        if state.done, currentStep == nil {
            EmptyView()
        } else if let step = currentStep {
            content(step)
        }
    }

    private func content(_ step: TutorialCatalog.TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("FIRST QUESTS")
                    .font(AppFont.bold(10))
                    .tracking(1.6)
                    .foregroundColor(tc.primary)
                Spacer()
                Text("\(completedCount) / \(TutorialCatalog.steps.count)")
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textTertiary)
                Button(action: onSkip) {
                    Text("SKIP")
                        .font(AppFont.bold(9))
                        .tracking(1.0)
                        .foregroundColor(tc.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, DesignSystem.Spacing.sm)
                .accessibilityLabel("Skip tutorial")
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(tc.primary, lineWidth: 2)
                    Text("\(step.ordinal)")
                        .font(AppFont.bold(11))
                        .foregroundColor(tc.primary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title)
                        .font(AppFont.bold(13))
                        .foregroundColor(tc.textPrimary)
                    Text("\(step.detail)  →")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Primary-accent border per the mockup; adaptiveCard adapts pixel vs flat.
        .adaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true)
    }
}
