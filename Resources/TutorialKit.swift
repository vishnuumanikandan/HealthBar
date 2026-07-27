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

    /// One tutorial step. `id` is the permanent wire contract; `ordinal` (1…10) drives
    /// display order and the pinned-card disc; `detail` is the "where to go" line;
    /// `xp` is the one-time award. No magic numbers live at call sites —
    /// every XP value is read from `step.xp`.
    struct TutorialStep: Identifiable, Equatable {
        let id: String
        let ordinal: Int
        let title: String
        let detail: String
        let xp: Int
    }

    /// The TEN step ids as pinned constants — the permanent wire contract (frozen at 2.1),
    /// surfaced so detection and beacon call sites reference `TutorialCatalog.aiLogId` etc.
    /// rather than bare string literals (Decision 1); each equals the matching `steps`
    /// entry's `id`. NEVER rename a value (it is stored in the Firestore UserProgress doc).
    /// `changeThemeId` is REUSED from the old six-step catalog (identical semantics — existing
    /// completions honor it); the other five old ids are removed and become inert.
    static let aiLogId        = "aiLog"
    static let openDatabaseId = "openDatabase"
    static let barcodeScanId  = "barcodeScan"
    static let friendsId      = "friends"
    static let duelPrimerId   = "duelPrimer"
    static let joinGuildId    = "joinGuild"
    static let weeklyStatsId  = "weeklyStats"
    static let openProfileId  = "openProfile"
    static let changeThemeId  = "changeTheme"
    static let perfectDayId   = "perfectDay"

    /// The ten pinned tutorial steps, in pinned order (Decision 1), with the XP from that
    /// table. XP total = 245 (25 + 20 + 25 + 20 + 25 + 25 + 15 + 15 + 15 + 60). Ids are the
    /// pinned constants above (single literal per id) and are stored in the Firestore
    /// UserProgress doc — NEVER rename; a new step gets an explicit pinned id.
    static let steps: [TutorialStep] = [
        TutorialStep(id: aiLogId,        ordinal:  1, title: "Log a meal with AI",       detail: "Describe a meal in the Log tab — AI does the rest", xp: 25),
        TutorialStep(id: openDatabaseId, ordinal:  2, title: "Browse the food database", detail: "Open the Log tab's food database",                  xp: 20),
        TutorialStep(id: barcodeScanId,  ordinal:  3, title: "Try the barcode scanner",  detail: "Open the scanner from the Log tab",                 xp: 25),
        TutorialStep(id: friendsId,      ordinal:  4, title: "Find your friends",        detail: "Visit Friends — or send a request",                 xp: 20),
        TutorialStep(id: duelPrimerId,   ordinal:  5, title: "Learn how duels work",     detail: "Read How Duels Work in Battle",                     xp: 25),
        TutorialStep(id: joinGuildId,    ordinal:  6, title: "Join a guild",             detail: "Join or request one from the directory",            xp: 25),
        TutorialStep(id: weeklyStatsId,  ordinal:  7, title: "Check your week",          detail: "Explore your weekly stats",                         xp: 15),
        TutorialStep(id: openProfileId,  ordinal:  8, title: "Visit your profile",       detail: "See your rank journey and badges",                  xp: 15),
        TutorialStep(id: changeThemeId,  ordinal:  9, title: "Try a new theme",          detail: "Settings → appearance",                             xp: 15),
        TutorialStep(id: perfectDayId,   ordinal: 10, title: "Meet all your goals",      detail: "Hit calories, protein, and purity in one day",      xp: 60),
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
    /// Per-quest skips (TUTFIX-1 Part C) — the ids the user dismissed one at a time from the
    /// pinned card. Monotonic like `completed`, and disjoint from it only by convention: a
    /// skipped step the user later performs still completes (and still earns its XP).
    let skippedSteps: Set<String>

    /// Done via any of three routes: legacy whole-tutorial skip (the skipped flag — no write
    /// path remains as of Part D, read-only for legacy users and guests), full completion, or
    /// every step individually completed-or-skipped. INVARIANT: !done ⇒ at least one catalog
    /// step is neither completed nor skipped, which is what guarantees
    /// FirstQuestsCard.currentStep is non-nil whenever the card renders.
    var done: Bool { skipped || completed.union(skippedSteps).isSuperset(of: TutorialCatalog.allIds) }

    /// Guests are excluded entirely (Decision 7): treated as seen + skipped ⇒ done, so
    /// no popup, no pinned card, no writes.
    static let guest = TutorialState(seen: true, skipped: true, completed: [], skippedSteps: [])
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
    /// Deliberately COMPLETED-ONLY (TUTFIX-1 Part C): a per-quest-skipped step the user later
    /// performs anyway still completes and still awards its XP — skipping only suppresses the
    /// card/beacon prompt, so the Tutorial Complete badge stays reachable after skips.
    func shouldAttempt(_ stepId: String) -> Bool {
        guard let state, !state.done else { return false }
        return !state.completed.contains(stepId)
    }
}

// MARK: - Welcome Popup

/// The 3-page welcome card, shown as a centered OVERLAY over the dimmed Home (never a
/// sheet / fullScreenCover). Owns NO persistence — it takes `onStart` / `onClose`
/// closures the presenter wires (the AvatarPickerSheet `onSave` precedent) and never
/// touches AppCoordinator, DataManager, or any store. `isReplay` (Settings replay) adds the
/// header Close button; the presenter simply supplies dismiss-only closures.
struct TutorialWelcomePopup: View {

    /// Greeting subject as plain data — the presenter passes the cached UserProfile
    /// displayName for first-run (or an @handle for Settings replay). nil / empty ⇒
    /// "Hey there". The popup never resolves identity itself (stays persistence-free).
    let greetingName: String?
    /// Read-only replay (Settings). Gates the header Close button, which first-run does not get.
    var isReplay: Bool = false
    let onStart: () -> Void
    /// Replay-only dismiss (TUTFIX-1 Part D). Defaulted because first-run never renders the
    /// button that calls it — first-run's only action is `onStart`.
    var onClose: () -> Void = {}

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    private var pageAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.32)
    }

    var body: some View {
        ZStack {
            // Dim scrim over the live Home content. Absorbs taps (no scrim-dismiss —
            // the tutorial requires an explicit Start (or, in Replay, Close) choice).
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
            // Close button — REPLAY ONLY (TUTFIX-1 Part D): first-run has no whole-skip; the
            // card's per-quest SKIP is the only skip. The whole ROW is gated, not just the
            // button, so first-run carries no dead Spacing.md gap where SKIP used to sit.
            if isReplay {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Text("SKIP")
                            .font(AppFont.bold(11))
                            .tracking(1.4)
                            .foregroundColor(tc.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
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

/// Page 3 — first quests: the ten catalog steps with XP (fixed-height scrollable box),
/// primary CTA, badge microcopy.
private struct TutorialQuestsPage: View {
    let tc: ThemeColors
    let reduceMotion: Bool
    let onStart: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            TutorialMetaLine(text: "FIRST QUESTS", tc: tc)
                .modifier(TutorialReveal(index: 0, shown: shown, reduceMotion: reduceMotion))

            Text("Ten quests. Finish them all for a badge.")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
                .modifier(TutorialReveal(index: 1, shown: shown, reduceMotion: reduceMotion))

            // Ten rows in a fixed-height scrollable box (Decision 4) — nested scroll inside the
            // card; scrolls under Dynamic Type with no clipping. Row styling is unchanged.
            ScrollView {
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
            }
            .frame(height: 180)
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

// TODO-tutorial-prebootstrap-skip: skipTutorialStep/markTutorialSeen silently no-op if UserProgress doesn't exist yet (pre-bootstrap edge, documented in refreshTutorialStore); harden if the edge ever fires in practice.
/// The pinned Home card that tracks tutorial progress. Owns NO persistence — it takes a
/// resolved `TutorialState` and an `onSkipStep` closure (the presenter wires it). Renders
/// nothing once the tutorial is done (the unloaded / guest case is filtered by the
/// caller's `if let`). Card body tap is inert (Decision 13 — navigation is TUT-1b).
struct FirstQuestsCard: View {
    let state: TutorialState
    /// Per-quest SKIP (TUTFIX-1 Part C) — receives the id of the quest currently shown. This
    /// is the ONLY skip in the product; the welcome popup's whole-tutorial skip is gone.
    let onSkipStep: (String) -> Void

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    /// Lowest-ordinal step neither completed NOR per-quest-skipped. nil when every catalog
    /// step is one or the other; a legacy whole-SKIPPED tutorial keeps this non-nil —
    /// visibility is gated on state.done, not on this.
    private var currentStep: TutorialCatalog.TutorialStep? {
        TutorialCatalog.steps.first { !state.completed.contains($0.id) && !state.skippedSteps.contains($0.id) }
    }

    /// Completed count, guarded to catalog ids so a future unknown id can't inflate it.
    /// Skipped quests deliberately do NOT count — the header tracks quests actually done.
    private var completedCount: Int {
        state.completed.intersection(TutorialCatalog.allIds).count
    }

    var body: some View {
        // Hidden whenever the tutorial is done — SKIPPED (completed set untouched, so
        // currentStep is non-nil) or fully completed. The old `done && currentStep == nil`
        // form only covered the completion path and rendered the card forever after a skip.
        if !state.done, let step = currentStep {
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
                Button(action: { onSkipStep(step.id) }) {
                    Text("SKIP")
                        .font(AppFont.bold(9))
                        .tracking(1.0)
                        .foregroundColor(tc.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, DesignSystem.Spacing.sm)
                .accessibilityLabel("Skip this quest")
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
    /// A pulsing primary OUTLINE that traces the target control's own shape, drawing the eye
    /// to a tutorial target (TUT-1b, Decision 3). Renders ONLY when the shared store is
    /// loaded, not done, AND `stepId` is the first incomplete step — so exactly one step's
    /// beacons glow app-wide, and post-tutorial / guest / unloaded users see nothing anywhere
    /// (zero overhead). Purely an overlay: it never wraps content, adds frames/padding,
    /// changes the target's size, or takes hit-testing. The outline fills the overlay, so it
    /// is already sized to the target's bounds; `cornerRadius` is what makes it match the
    /// control's silhouette — pass the control's own radius (pill/circular controls pass
    /// height/2; RoundedRectangle clamps to half the short side, yielding a capsule).
    /// Defaults to the standard Erewhon surface-card/button radius (14 — `flatCard`'s default,
    /// and AppButton's exact radius).
    func questBeacon(_ stepId: String,
                     cornerRadius: CGFloat = DesignSystem.Erewhon.buttonRadius) -> some View {
        modifier(QuestBeacon(stepId: stepId, cornerRadius: cornerRadius))
    }
}

/// The beacon overlay (Decision 3). Layout-neutral: `content` is returned untouched with the
/// outline drawn in a bounds-matching overlay that never hit-tests. Reduce Motion collapses
/// to a single static outline at reduced opacity — no pulse, no glow.
private struct QuestBeacon: ViewModifier {
    let stepId: String
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    /// True when `stepId` is the single active beacon — the lowest-ordinal step not yet
    /// completed, given a loaded, not-done tutorial. The first-incomplete predicate lives
    /// HERE, not on the store (which keeps exactly `update` + `shouldAttempt`), and reads
    /// `state` directly so @Observable re-evaluates it as the store changes.
    private var isActiveBeacon: Bool {
        guard let state = TutorialProgress.shared.state, !state.done else { return false }
        // Predicate byte-identical to FirstQuestsCard.currentStep so the glow always tracks
        // the card's current quest — including past per-quest skips (TUTFIX-1 Part C).
        let firstIncomplete = TutorialCatalog.steps.first {
            !state.completed.contains($0.id) && !state.skippedSteps.contains($0.id)
        }
        return firstIncomplete?.id == stepId
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isActiveBeacon {
                beacon
            }
        }
    }

    /// Both outlines fill the overlay — i.e. the target's own bounds — so the beacon traces
    /// the control instead of drawing a shape over it. The pulse ring scales slightly OUTWARD
    /// and fades on repeat; scaleEffect draws beyond the bounds without affecting layout.
    private var beacon: some View {
        ZStack {
            // Steady outline — keeps the target marked between pulses.
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(tc.primary.opacity(reduceMotion ? 0.55 : 0.9), lineWidth: 2)
            // The pulse — the same outline, expanding slightly and fading, forever.
            if !reduceMotion {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(tc.primary, lineWidth: 2)
                    .scaleEffect(pulsing ? 1.08 : 1.0)
                    .opacity(pulsing ? 0 : 0.85)
            }
        }
        .shadow(color: tc.primary.opacity(reduceMotion ? 0 : 0.45), radius: 8)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
