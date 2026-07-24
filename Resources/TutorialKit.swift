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

    /// The six step ids as pinned constants — the permanent wire contract, surfaced so the
    /// TUT-1b detection and beacon call sites reference `TutorialCatalog.quickLogId` etc.
    /// rather than bare string literals (Decision 1); each equals the matching `steps`
    /// entry's `id`. NEVER rename a value (it is stored in the Firestore UserProgress doc).
    static let quickLogId    = "quickLog"
    static let databaseLogId = "databaseLog"
    static let checkQuestsId = "checkQuests"
    static let visitBattleId = "visitBattle"
    static let visitGuildId  = "visitGuild"
    static let changeThemeId = "changeTheme"

    /// The six pinned tutorial steps, in pinned order (Decision 2), with the XP from
    /// Decision 9. XP total = 150 (30 + 30 + 20 + 25 + 25 + 20). Ids are the pinned
    /// constants above (single literal per id) and are stored in the Firestore
    /// UserProgress doc — NEVER rename; a new step gets an explicit pinned id.
    static let steps: [TutorialStep] = [
        TutorialStep(id: quickLogId,    ordinal: 1, title: "Quick-log a meal",           detail: "Use quick log on Home to add your first meal", xp: 30),
        TutorialStep(id: databaseLogId, ordinal: 2, title: "Log from the food database", detail: "Open the Log tab and add anything",            xp: 30),
        TutorialStep(id: checkQuestsId, ordinal: 3, title: "Check your daily quests",     detail: "Find today's quests on Home",                  xp: 20),
        TutorialStep(id: visitBattleId, ordinal: 4, title: "Learn how duels work",        detail: "Visit the Battle tab",                         xp: 25),
        TutorialStep(id: visitGuildId,  ordinal: 5, title: "Check out a guild",           detail: "Open any guild from the directory",            xp: 25),
        TutorialStep(id: changeThemeId, ordinal: 6, title: "Try a new theme",             detail: "Settings → appearance",                        xp: 20),
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

// MARK: - Shared Read-Model Store

/// The tutorial's shared, cross-tab read model (TUT-1b, Decision 1). ContentView builds a
/// DataManager per tab, so tutorial state — which drives beacons and the view-side detection
/// guard on every tab — MUST be `static`, not instance state (the per-tab-DataManager
/// invariant). This is TutorialKit's runtime read model: the AvatarKit-style read-only
/// companion to the compile-time `TutorialCatalog`, NOT a manager, owning no persistence.
/// `DuelUIState.shared` is the precedent (DataManager writes on the main actor; views read).
@Observable
@MainActor
final class TutorialProgress {
    static let shared = TutorialProgress()
    private init() {}

    /// The latest resolved read model, or nil while unloaded. nil ⇒ beacons render nothing
    /// and detection skips, exactly as when done — until the first refresh populates it.
    private(set) var state: TutorialState?

    /// The ONLY mutation path. Called exclusively by DataManager's refresh helper
    /// (`refreshTutorialStore()`) — every public DataManager tutorial entry point ends
    /// there, so the store always trails the persisted UserProgress.
    func update(_ newState: TutorialState?) {
        state = newState
    }

    /// The uniform view-side detection guard (Decision 1), used at all six sites — never
    /// inlined. False when the tutorial is unloaded, done (skipped or fully complete —
    /// guests included), or already holds `stepId`; true otherwise. An optimization only:
    /// the `completeTutorialStep` chokepoint stays the correctness boundary, not this.
    func shouldAttempt(_ stepId: String) -> Bool {
        guard let state, !state.done else { return false }
        return !state.completed.contains(stepId)
    }
}

// MARK: - Welcome Popup

/// The 3-page welcome card, shown as a centered OVERLAY over the dimmed Home (never a
/// sheet / fullScreenCover). Owns NO persistence — it takes `onStart` / `onSkip`
/// closures the presenter wires (the AvatarPickerSheet `onSave` precedent) and never
/// touches AppCoordinator, DataManager, or any store. `isReplay` (Settings replay) is
/// visually identical; the presenter simply supplies dismiss-only closures.
struct TutorialWelcomePopup: View {

    /// Greeting subject as plain data — the presenter passes the cached UserProfile
    /// displayName for first-run (or an @handle for Settings replay). nil / empty ⇒
    /// "Hey there". The popup never resolves identity itself (stays persistence-free).
    let greetingName: String?
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
        if let greetingName, !greetingName.isEmpty { return "Hey \(greetingName)" }
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

// MARK: - Quest Beacon

extension View {
    /// Pulsing concentric primary rings drawing the eye to a tutorial target (TUT-1b,
    /// Decision 3). Renders ONLY when the shared store is loaded, not done, AND `stepId`
    /// is the first incomplete step — so exactly one step's beacons glow app-wide, and
    /// post-tutorial / guest / unloaded users see nothing anywhere (zero overhead). Purely
    /// an overlay: it never wraps content, adds frames/padding, changes the target's size,
    /// or takes hit-testing, and it self-sizes to the target's bounds so a toolbar gear
    /// glows small and a card glows large (the "adapt to the metric" rule).
    func questBeacon(_ stepId: String) -> some View {
        modifier(QuestBeacon(stepId: stepId))
    }
}

/// The beacon overlay (Decision 3). Layout-neutral: `content` is returned untouched with
/// the rings drawn in a bounds-matching overlay that never hit-tests. Reduce Motion
/// collapses to a single static ring at reduced opacity — no pulse.
private struct QuestBeacon: ViewModifier {
    let stepId: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    /// True when `stepId` is the single active beacon — the lowest-ordinal step not yet
    /// completed, given a loaded, not-done tutorial. The first-incomplete predicate lives
    /// HERE, not on the store (which keeps exactly `update` + `shouldAttempt`), and reads
    /// `state` directly so @Observable re-evaluates it as the store changes.
    private var isActiveBeacon: Bool {
        guard let state = TutorialProgress.shared.state, !state.done else { return false }
        let firstIncomplete = TutorialCatalog.steps.first { !state.completed.contains($0.id) }
        return firstIncomplete?.id == stepId
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isActiveBeacon {
                beacon
            }
        }
    }

    private var beacon: some View {
        GeometryReader { geo in
            let base = max(geo.size.width, geo.size.height)
            ZStack {
                // Outer ring: the ping — expands and fades on the pulse (steady when Reduce
                // Motion). Inner ring: a constant halo so the target stays ringed between pings.
                Circle()
                    .stroke(tc.primary.opacity(reduceMotion ? 0.5 : 0.85),
                            lineWidth: max(1.5, base * 0.05))
                    .frame(width: base * 1.15, height: base * 1.15)
                    .scaleEffect(pulsing && !reduceMotion ? 1.35 : 1.0)
                    .opacity(pulsing && !reduceMotion ? 0.0 : (reduceMotion ? 0.5 : 0.85))
                if !reduceMotion {
                    Circle()
                        .stroke(tc.primary.opacity(0.55), lineWidth: max(1, base * 0.03))
                        .frame(width: base * 1.15, height: base * 1.15)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(color: tc.primary.opacity(reduceMotion ? 0 : 0.45), radius: base * 0.14)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
