//
//  FoodLogView.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData

/// Main Food Log view showing nutrition progress and meal entries organised by category.
///
/// Features:
/// - Date navigator (browse up to 7 days back, 4 days forward)
/// - Today's Progress ring + macro cards (always reflects today)
/// - 5 meal category sections (Breakfast, Lunch, Dinner, Snack, Uncategorized)
///   - Each section is collapsible (Fix #8)
///   - Logged meals appear as bundle rows with expand/collapse (Fix #2)
///   - Individual entries support swipe-left (edit/delete) and swipe-right (favorite) (Fix #5)
/// - Recent Foods section above Breakfast (Fix #6)
/// - Undo-delete with 5-second Task.sleep window
struct FoodLogView: View {

    // MARK: - Properties

    @State private var viewModel: FoodLogViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = SettingsManager.shared
    @State private var draggingOver: MealType? = nil
    /// Triggers the existing guest → signup path (provided by ContentView).
    /// Threaded through to the describe sheet's guest card (AIPROXY-1b).
    private let onCreateAccount: () -> Void

    /// HOMECTA-1: one-shot cross-tab request (owned by ContentView, beside `selectedTab`) for
    /// this tab to present the AI describe-meal sheet. Consumed in `consumeDescribeRequest()`.
    /// Defaulted to a constant binding so the previews below — and any future non-tab mount —
    /// simply never receive a request.
    @Binding private var pendingDescribePresentation: Bool

    private var tc: ThemeColors { settings.activeColors }

    // Fix #8: track which sections are collapsed
    @State private var collapsedSections: Set<MealType> = []

    // Fix #2 UI: track which meal bundles are expanded
    @State private var expandedBundles: Set<String> = []

    // R5a: datenav tools button presents the existing ToolsView via .sheet (D2).
    @State private var toolsViewModel = ToolsViewModel()
    @State private var showingTools = false

    // R5a: Add-to-log block's "Scan barcode" row pushes the existing BarcodeOptionsView (D7).
    @State private var showingBarcodeOptions = false

    // MARK: - Water (WATER-1)
    //
    // Every piece of state below is view-local, transient and purely decorative. None of it
    // is persisted — not in SwiftData, not in SettingsManager, not on the view model. The
    // count and the goal live on the view model; these only describe motion.

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Corner-button disc scale: dips on the tap and springs back past 1 (mockup §4).
    @State private var waterDiscScale: CGFloat = 1
    /// Bumped per tap so the splash restarts rather than queueing (D15 retargeting).
    @State private var waterSplashToken = 0
    /// Whether a splash burst is currently on screen.
    @State private var waterSplashRunning = false
    /// Reduce-Motion stand-in for the splash: one 180 ms wash that fades. Keyed by token
    /// so each tap builds a fresh one (see `WaterTapPulse`).
    @State private var waterPulseActive = false
    @State private var waterPulseToken = 0
    /// Whether an arrival ring is currently on screen.
    @State private var waterGoalRingActive = false
    /// Bumped per crossing: re-identifies the ring so a new one starts from scratch, and
    /// guards the ring's own teardown against a later crossing.
    @State private var waterGoalRingToken = 0
    /// Overfull glow breathing (decorative). Under Reduce Motion the glow stays lit and
    /// simply stops breathing — it is state, not decoration.
    @State private var waterOverfullBreathing = false

    // MARK: - Initialization

    init(
        coordinator: AppCoordinator,
        onCreateAccount: @escaping () -> Void = {},
        pendingDescribePresentation: Binding<Bool> = .constant(false)
    ) {
        self._viewModel = State(initialValue: FoodLogViewModel(coordinator: coordinator))
        self.onCreateAccount = onCreateAccount
        self._pendingDescribePresentation = pendingDescribePresentation
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.displayedEntries.isEmpty && viewModel.isViewingToday {
                    loadingView
                } else {
                    contentView
                }
            }
            // WATER-1 D15: the corner button. Attached through this screen's existing
            // overlay mechanism and offset by tokens only — no screen coordinates.
            //
            // The bottom offset is `tabBarContentHeight` + a spacing token, the same
            // clearance this file's `contentMargins` and SettingsView's toast already use:
            // the TabView mounts the bar as a bottom `safeAreaInset`, and that inset does
            // NOT propagate into a tab's own NavigationStack, so this container's bottom
            // edge is the screen's. Verified in the simulator — without it the button
            // renders behind the translucent bar.
            .overlay(alignment: .bottomTrailing) {
                if settings.waterTrackerEnabled {
                    waterAddButton
                        .padding(.trailing, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Erewhon.tabBarContentHeight + DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // R7c §4: no nav-bar title on the tab root — the in-content head is the header, and the
            // root's toolbar held nothing else (the date nav lives in the content, not the bar), so
            // the empty bar is hidden. The sheets below keep their own principal titles.
            .toolbar(.hidden, for: .navigationBar)
            // Add Food 3-choice sheet
            .sheet(isPresented: $viewModel.showingAddFoodChoice) {
                AddFoodChoiceSheet(viewModel: viewModel)
            }
            // Food Database full-screen sheet
            .sheet(isPresented: $viewModel.showingFoodDatabase) {
                FoodDatabaseView(viewModel: viewModel)
            }
            // Add food entry form
            .sheet(isPresented: $viewModel.showingAddFood) {
                AddFoodFormView(viewModel: viewModel)
            }
            // AI Describe Meal input sheet
            .sheet(isPresented: $viewModel.showingDescribeMeal) {
                DescribeMealView(viewModel: viewModel, onCreateAccount: onCreateAccount)
            }
            // AI Recognized Foods review sheet
            .sheet(isPresented: $viewModel.showingRecognitionReview) {
                RecognizedFoodsReviewView(viewModel: viewModel)
            }
            // Edit meal form
            .sheet(isPresented: $viewModel.showingEditSheet) {
                if let entry = viewModel.editingEntry {
                    EditMealView(
                        entry: entry,
                        onSave: { name, calories, protein, carbs, fat, toxinScore, photoData in
                            Task {
                                await viewModel.updateMeal(
                                    entry,
                                    name: name,
                                    calories: calories,
                                    protein: protein,
                                    carbs: carbs,
                                    fat: fat,
                                    toxinScore: toxinScore,
                                    photoData: photoData
                                )
                            }
                        },
                        onCancel: {
                            viewModel.cancelEditing()
                        }
                    )
                }
            }
            // R5a D2: Tools sheet (datenav tools button). Additional entry point;
            // ToolsView's existing entry point elsewhere is untouched.
            .sheet(isPresented: $showingTools) {
                ToolsView(toolsViewModel: toolsViewModel)
            }
            // R5a D7: barcode path for the Add-to-log block — reuses the existing
            // BarcodeOptionsView. onDismissAll pops back to the food screen (mirrors the
            // sheet flow's dismiss()).
            .navigationDestination(isPresented: $showingBarcodeOptions) {
                BarcodeOptionsView(
                    viewModel: viewModel,
                    onDismissAll: { showingBarcodeOptions = false }
                )
                // TUT-2 barcodeScan detection (Decision 2) — the barcode surface's appearance
                // (opening counts; a successful scan is NOT required). The one chosen site — not
                // the presentation-state flip.
                .onAppear {
                    if TutorialProgress.shared.shouldAttempt(TutorialCatalog.barcodeScanId) {
                        Task { _ = try? await viewModel.coordinator.completeTutorialStep(TutorialCatalog.barcodeScanId) }
                    }
                }
            }
            // Bridge: barcode scan → open add food form after sheet dismiss animation
            .onChange(of: viewModel.shouldOpenAddFoodForm) { _, newValue in
                if newValue {
                    viewModel.showingAddFood = true
                    viewModel.shouldOpenAddFoodForm = false
                }
            }
            .alert("Food Added!", isPresented: $viewModel.showSuccessMessage) {
                Button("OK") { viewModel.dismissSuccessMessage() }
            } message: {
                if viewModel.lastEarnedXP > 0 {
                    Text("\(viewModel.lastAddedFoodName) logged successfully! You earned +\(viewModel.lastEarnedXP) XP!")
                } else {
                    Text("\(viewModel.lastAddedFoodName) logged successfully!")
                }
            }
            .onChange(of: viewModel.showSuccessMessage) { _, newValue in
                if newValue {
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage { Text(error) }
            }
            .task {
                await viewModel.loadTodaysData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
                viewModel.displayedEntries = viewModel.todaysEntries
            }
            .refreshable {
                await viewModel.refreshData()
                await viewModel.loadRecentFoods()
                await viewModel.loadFavorites()
            }
            .overlay {
                if viewModel.showToast, let message = viewModel.toastMessage {
                    toastOverlay(message: message)
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.showUndoToast {
                    UndoToast(
                        message: viewModel.undoMessage,
                        onUndo: { viewModel.undoDelete() }
                    )
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showUndoToast)
                }
            }
            .onDisappear {
                Task { await viewModel.finalizeAnyPendingDeletes() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    Task { await viewModel.finalizeAnyPendingDeletes() }
                }
                if newPhase == .active {
                    Task { await viewModel.loadRecentFoods() }
                }
            }
            // HOMECTA-1: consume Home's describe request. BOTH hooks are required —
            // `onChange` covers the case where this tab is already mounted (returning from Home
            // to an already-visited Food Log, where `onAppear` never fires again), and the
            // appear-time check covers the first visit, where the tab was not yet in the
            // hierarchy when the flag flipped and no change was observed.
            .onChange(of: pendingDescribePresentation) { _, isPending in
                if isPending { consumeDescribeRequest() }
            }
            .onAppear {
                consumeDescribeRequest()
            }
        }
    }

    // MARK: - Home CTA Bridge (HOMECTA-1)

    /// Consumes a pending describe-meal request from Home's Log Food CTA.
    ///
    /// One-shot by construction: the flag is cleared in the SAME synchronous update that
    /// presents the sheet — before any `await`, never on sheet dismissal and never on a delay.
    /// That is what makes dismiss → revisit-tab not re-present.
    ///
    /// Idempotent: a request arriving while the sheet is already up is a no-op (the flag still
    /// clears). Re-entering `openDescribeMeal()` would reset the session — clearing the typed
    /// description and cancelling any in-flight recognition — so repeated Home taps must not
    /// reach it.
    private func consumeDescribeRequest() {
        guard pendingDescribePresentation else { return }
        if !viewModel.showingDescribeMeal {
            viewModel.openDescribeMeal()
        }
        pendingDescribePresentation = false
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView().scaleEffect(1.5)
            Text("Loading your meals...")
                .font(AppFont.regular(DesignSystem.FontSizes.callout))
                .foregroundColor(tc.textSecondary)
        }
    }

    // MARK: - Future Date Empty State

    private var futureDateEmptyView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                dateNavigator
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.lg)
                EmptyStateView(
                    icon: "calendar",
                    title: "No meals yet",
                    message: "You haven't logged any meals for this date.",
                    actionTitle: nil,
                    action: nil
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
    }

    // MARK: - Main Content

    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Date Navigator (D2)
                dateNavigator

                // Progress → food hero + gated nutrition detgrid for Erewhon (D3/D4);
                // pixel keeps its paged progress card, byte-identical.
                if settings.isCleanUI {
                    foodHeroClean
                    if settings.trackAdvancedNutrition {
                        nutritionDetailsClean
                    }
                } else {
                    progressSection
                }

                // Fix #6: Recent Foods above meal sections (behavior unchanged; D5 restyle)
                if !viewModel.recentFoods.isEmpty {
                    recentFoodsSection
                }

                // 5 Meal Category Sections (D6). Erewhon groups them under one sec-head
                // as a hairline list; pixel keeps the per-section cards.
                if settings.isCleanUI {
                    VStack(spacing: 0) {
                        secHead("Meals", "Tap to expand")
                        ForEach(MealType.allCases, id: \.self) { mealType in
                            mealSection(for: mealType)
                        }
                    }
                } else {
                    ForEach(MealType.allCases, id: \.self) { mealType in
                        mealSection(for: mealType)
                    }
                }

                // Add-to-log methods block (D7) — Erewhon-only additional surface (uses
                // Erewhon-flat tokens). The per-section + entry points stay for both families.
                if settings.isCleanUI {
                    addToLogSection
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .padding(.bottom, 40)
        }
        // R2 §5: reserve the tab bar's height so the bottom meal sections clear the
        // translucent bar (the TabView's safeAreaInset doesn't reach this ScrollView).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
    }

    // MARK: - Date Navigator

    /// Mockup `.datenav`: ‹ chip · day word + full date · › chip, centered, with a
    /// trailing tools button presenting the existing ToolsView (D2). Drives the existing
    /// date state — same bounds, same future-date handling.
    private var dateNavigator: some View {
        HStack(spacing: 18) {
            Button {
                viewModel.navigateToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppFont.regular(18))
                    .foregroundColor(viewModel.canNavigateBack ? tc.textSecondary : tc.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canNavigateBack)
            .buttonStyle(PlainButtonStyle())

            VStack(spacing: 3) {
                Text(dayWord(for: viewModel.selectedDate))
                    .font(AppFont.display(23))
                    .foregroundColor(tc.textPrimary)
                    .animation(nil, value: viewModel.selectedDate)
                Text(fullDate(for: viewModel.selectedDate))
                    .font(AppFont.regular(10.5))
                    .foregroundColor(tc.textTertiary)
            }
            .frame(minWidth: 148)

            Button {
                viewModel.navigateToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppFont.regular(18))
                    .foregroundColor(viewModel.canNavigateForward ? tc.textSecondary : tc.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canNavigateForward)
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button {
                showingTools = true
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .font(AppFont.regular(17))
                    .foregroundColor(tc.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Tools")
        }
    }

    /// Big day word for the datenav (display type, D9). View-local — no VM change (D10).
    private func dayWord(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Full-date subline for the datenav (Hanken). View-local — no VM change.
    private func fullDate(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Section Header (mockup `.sec-head`)

    /// Mockup `.sec-head`: display title (D9) + optional right-aligned meta over a soft
    /// hairline. Matches the R3b/R4 convention (HomeView/BattleView `secHead`).
    private func secHead(_ title: String, _ meta: String?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                if let meta {
                    Text(meta)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(.bottom, 10)
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .padding(.bottom, 14)
    }

    /// Mockup meal time ranges (D6). Defined view-local — MealType has no time-range
    /// metadata and must not gain any. Uncategorized has no range in the mockup.
    private func mealTimeRange(for mealType: MealType) -> String? {
        switch mealType {
        case .breakfast: return "5:00 – 11:00 AM"
        case .lunch: return "11:00 AM – 4:00 PM"
        case .dinner: return "4:00 – 9:00 PM"
        case .snack: return "9:00 PM – 5:00 AM"
        case .uncategorized: return nil
        }
    }

    // MARK: - Meal Category Section (D6)

    private func mealSection(for mealType: MealType) -> some View {
        let allEntries = viewModel.entries(for: mealType)
        let isCollapsed = collapsedSections.contains(mealType)

        // Group entries: solo vs bundle
        let soloEntries = allEntries.filter { $0.mealBundleId == nil }
        let bundleDict = Dictionary(
            grouping: allEntries.filter { $0.mealBundleId != nil },
            by: { $0.mealBundleId! }
        )
        // Sort bundle IDs by the earliest entry date in each bundle
        let sortedBundleIds = bundleDict.keys.sorted {
            let d1 = bundleDict[$0]?.first?.date ?? Date.distantPast
            let d2 = bundleDict[$1]?.first?.date ?? Date.distantPast
            return d1 < d2
        }

        let sectionCalTotal = allEntries.reduce(0) { $0 + $1.calories }

        // Header + body (shared body wiring; header/container chrome branch per family).
        let content = VStack(spacing: 0) {
            if settings.isCleanUI {
                mealHeaderClean(mealType: mealType, allEntries: allEntries,
                                sectionCalTotal: sectionCalTotal, isCollapsed: isCollapsed)
                if !isCollapsed {
                    mealBody(mealType: mealType, allEntries: allEntries, soloEntries: soloEntries,
                             bundleDict: bundleDict, sortedBundleIds: sortedBundleIds)
                        .padding(.bottom, DesignSystem.Spacing.md)
                }
            } else {
                mealHeaderPixel(mealType: mealType, allEntries: allEntries,
                                sectionCalTotal: sectionCalTotal, isCollapsed: isCollapsed)
                if !isCollapsed {
                    mealBody(mealType: mealType, allEntries: allEntries, soloEntries: soloEntries,
                             bundleDict: bundleDict, sortedBundleIds: sortedBundleIds)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.bottom, DesignSystem.Spacing.md)
                } else {
                    // Collapsed spacer
                    Color.clear.frame(height: DesignSystem.Spacing.sm)
                }
            }
        }

        return Group {
            if settings.isCleanUI {
                // Erewhon: flat hairline row (no card); drag highlight via a subtle tint.
                content
                    .background(draggingOver == mealType ? tc.primary.opacity(0.06) : Color.clear)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
                    }
            } else {
                content
                    .adaptiveCard(
                        borderColor: draggingOver == mealType ? mealType.color.opacity(0.5) : tc.primary.opacity(0.15),
                        fillColor: draggingOver == mealType ? mealType.color.opacity(0.08) : tc.cardBackground
                    )
            }
        }
        // Drop target on the whole section (bar2 + body) — a drop on a COLLAPSED header
        // still registers, unchanged from before.
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }

            // Bundle drag: prefix "bundle:<bundleId>"
            if item.hasPrefix("bundle:") {
                let bid = String(item.dropFirst(7))
                let bundleEntries = viewModel.displayedEntries.filter { $0.mealBundleId == bid }
                guard !bundleEntries.isEmpty,
                      bundleEntries.first?.mealType != mealType else { return false }
                Task {
                    for entry in bundleEntries {
                        await viewModel.updateMealType(of: entry, to: mealType)
                    }
                }
                return true
            }

            // Solo entry drag: item is the UUID string
            guard let uuid = UUID(uuidString: item),
                  let entry = viewModel.displayedEntries.first(where: { $0.id == uuid }),
                  entry.mealType != mealType else { return false }
            Task { await viewModel.updateMealType(of: entry, to: mealType) }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                draggingOver = targeted ? mealType : nil
            }
        }
    }

    /// Erewhon `.bar2`: the info + total + chevron region toggles the accordion; the
    /// existing + control stays a distinct button. Meal name / count / range / total per
    /// D6 (total in display, D9).
    private func mealHeaderClean(mealType: MealType, allEntries: [FoodEntry],
                                 sectionCalTotal: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: 13) {
            Button {
                toggleCollapse(mealType)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: mealType.icon)
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 9) {
                            Text(mealType.displayName)
                                .font(AppFont.bold(13.5))
                                .foregroundColor(tc.textPrimary)
                            Text("\(allEntries.count) item\(allEntries.count == 1 ? "" : "s")")
                                .font(AppFont.regular(10))
                                .foregroundColor(tc.textTertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Erewhon.line, lineWidth: 1)
                                )
                        }
                        if let range = mealTimeRange(for: mealType) {
                            Text(range)
                                .font(AppFont.regular(10.5))
                                .foregroundColor(tc.textTertiary)
                        }
                    }

                    Spacer()

                    Text("\(sectionCalTotal)")
                        .font(AppFont.display(16))
                        .foregroundColor(tc.textPrimary)

                    Image(systemName: "chevron.right")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textTertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(DesignSystem.Erewhon.ease(0.4), value: isCollapsed)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            plusButton(for: mealType)
        }
        .padding(.vertical, 15)
    }

    /// Pixel section header (preserved byte-identical, incl. the collapse toggle and the
    /// + button's `settings.isCleanUI` border branch via `plusButton`).
    private func mealHeaderPixel(mealType: MealType, allEntries: [FoodEntry],
                                 sectionCalTotal: Int, isCollapsed: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: mealType.icon)
                .font(AppFont.bold(16))
                .foregroundColor(mealType.color)

            Text(mealType.displayName)
                .font(AppFont.bold(18))
                .foregroundColor(tc.textPrimary)

            if !allEntries.isEmpty {
                Text("\(allEntries.count)")
                    .font(AppFont.bold(DesignSystem.FontSizes.caption))
                    .foregroundColor(mealType.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(mealType.color.opacity(0.15))
                    .clipShape(AdaptivePillShapeStyle())
            }

            Spacer()

            // Fix #8: show total cal when collapsed
            if isCollapsed && !allEntries.isEmpty {
                Text("\(sectionCalTotal) cal")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
            }

            // Fix #8: collapse toggle (only when there are entries)
            if !allEntries.isEmpty {
                Button {
                    toggleCollapse(mealType)
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(AppFont.bold(13))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            plusButton(for: mealType)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, (allEntries.isEmpty || isCollapsed) ? DesignSystem.Spacing.xs : DesignSystem.Spacing.sm)
    }

    /// The per-section + button (existing add entry point; preserves the isCleanUI border
    /// branch — the only pre-existing pixel fragment in the meal header).
    private func plusButton(for mealType: MealType) -> some View {
        Button {
            viewModel.openAddFoodChoice(for: mealType)
        } label: {
            Text("+")
                .font(AppFont.bold(16))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .adaptivePill(
                    borderColor: settings.isCleanUI ? .clear : mealType.color.adjustedBrightness(-0.2),
                    fillColor: .clear,
                    fillGradient: DesignSystem.Colors.adaptiveGradientFrom(mealType.color)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func toggleCollapse(_ mealType: MealType) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if collapsedSections.contains(mealType) {
                collapsedSections.remove(mealType)
            } else {
                collapsedSections.insert(mealType)
            }
        }
    }

    /// Shared meal body: empty-state add affordance, or solo swipe cards + bundle rows.
    /// Swipe / delete / undo + drag logic untouched (F3-hardened).
    @ViewBuilder
    private func mealBody(mealType: MealType, allEntries: [FoodEntry], soloEntries: [FoodEntry],
                          bundleDict: [String: [FoodEntry]], sortedBundleIds: [String]) -> some View {
        if allEntries.isEmpty {
            // Tappable empty state row (drag target still registers via the section)
            Button {
                viewModel.openAddFoodChoice(for: mealType)
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "plus")
                        .font(AppFont.bold(13))
                        .foregroundColor(mealType.color)
                    Text("Add \(mealType.displayName)")
                        .font(AppFont.regular(DesignSystem.FontSizes.callout))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                }
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: mealType.color.opacity(0.3), fillColor: mealType.color.opacity(0.06))
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Solo entries with swipe actions (Fix #5)
                ForEach(soloEntries, id: \.id) { entry in
                    SwipeableEntryCard(
                        entry: entry,
                        onFavorite: { Task { await viewModel.toggleFavorite(entry) } },
                        onEdit: { viewModel.startEditing(entry) },
                        onDelete: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.deleteWithUndo(entry)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // Bundle rows (Fix #2 UI)
                ForEach(sortedBundleIds, id: \.self) { bundleId in
                    if let components = bundleDict[bundleId] {
                        bundleRow(bundleId: bundleId, components: components)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
        }
    }

    // MARK: - Bundle Row

    private func bundleRow(bundleId: String, components: [FoodEntry]) -> some View {
        let bundleName = components.first?.mealBundleName ?? "Meal Bundle"
        let totalCal = components.reduce(0) { $0 + $1.calories }
        let isExpanded = expandedBundles.contains(bundleId)
        // MEALPHOTO-1: the bundle's photo lives on exactly one component (the first item
        // logged from an AI recognition); nil once that component is deleted, or when the
        // bundle was never photographed — either way the header falls back to today's row.
        //
        // PHOTOPERF-1: carry the OWNING component's id alongside the data — keying the
        // decode cache on the bundle id would let a key outlive the photo it names.
        let bundlePhoto = components
            .compactMap { component in
                component.photoData.map { (data: $0, cacheKey: component.id.uuidString) }
            }
            .first

        return VStack(spacing: 4) {
            // Bundle header row — photo-conditional split card (MEALROW-1 pattern), else
            // the existing header unchanged. The expanded children render below either.
            if let bundlePhoto {
                PhotoSplitCard(photoData: bundlePhoto.data,
                               cacheKey: bundlePhoto.cacheKey,
                               cornerRadius: DesignSystem.Erewhon.cardRadius) {
                    bundleHeaderContent(bundleId: bundleId, bundleName: bundleName,
                                        totalCal: totalCal, componentCount: components.count,
                                        isExpanded: isExpanded)
                }
                .adaptiveCard(borderColor: tc.iconAmber.mid.opacity(0.25), fillColor: tc.cardBackground)
                .draggable("bundle:\(bundleId)")
            } else {
                bundleHeaderContent(bundleId: bundleId, bundleName: bundleName,
                                    totalCal: totalCal, componentCount: components.count,
                                    isExpanded: isExpanded)
                    .adaptiveCard(borderColor: tc.iconAmber.mid.opacity(0.25), fillColor: tc.cardBackground)
                    // Drag entire bundle to a new section
                    .draggable("bundle:\(bundleId)")
            }

            // Expanded component rows
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(components, id: \.id) { component in
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(AppFont.regular(5))
                                .foregroundColor(tc.textTertiary)

                            Text(component.name)
                                .font(AppFont.regular(DesignSystem.FontSizes.footnote))
                                .foregroundColor(tc.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(component.calories) cal")
                                .font(AppFont.regular(DesignSystem.FontSizes.caption))
                                .foregroundColor(tc.textSecondary)

                            // Per-component delete button
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.deleteWithUndo(component)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(AppFont.regular(12))
                                    .foregroundColor(.red.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .adaptiveCard(borderColor: tc.primary.opacity(0.1), fillColor: tc.cardBackground.opacity(0.6))
                    }
                }
            }
        }
    }

    /// The bundle header's inner content (icon + name/total + expand + menu), extracted so
    /// the photo and photo-less arms share ONE definition — layout identical to the
    /// pre-MEALPHOTO-1 header; card chrome stays at the call site.
    @ViewBuilder
    private func bundleHeaderContent(bundleId: String, bundleName: String, totalCal: Int,
                                     componentCount: Int, isExpanded: Bool) -> some View {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    AdaptiveCardShapeStyle()
                        .fill(tc.iconAmber.mid.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "rectangle.stack.fill")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.iconAmber.mid)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(bundleName)
                        .font(AppFont.bold(DesignSystem.FontSizes.callout))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    Text("\(totalCal) cal · \(componentCount) item\(componentCount == 1 ? "" : "s")")
                        .font(AppFont.regular(DesignSystem.FontSizes.caption))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                // Collapse/expand toggle
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isExpanded {
                            expandedBundles.remove(bundleId)
                        } else {
                            expandedBundles.insert(bundleId)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(AppFont.bold(12))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Three-dot menu: delete entire bundle
                Menu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteBundle(bundleId: bundleId) }
                    } label: {
                        Label("Delete Meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, DesignSystem.Spacing.md)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        let progressTitle = viewModel.isViewingToday
            ? "Today's Progress"
            : "\(viewModel.selectedDateDisplayLabel)'s Progress"

        return VStack(spacing: DesignSystem.Spacing.md) {
            Text(progressTitle)
                .font(AppFont.bold(DesignSystem.FontSizes.title2))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Paged carousel: Page 1 = calories+macros, Page 2 = extra nutrients
            TabView {
                // Page 1: Calorie ring + macro cards
                VStack(spacing: DesignSystem.Spacing.md) {
                    PixelCalorieRing(
                        progress: viewModel.calorieProgress,
                        calories: viewModel.totalCalories,
                        filledColor: tc.ringFilled,
                        emptyColor: tc.ringEmpty,
                        textColor: tc.textPrimary,
                        labelColor: tc.textSecondary
                    )
                    .frame(width: 210, height: 210)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, DesignSystem.Spacing.sm)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignSystem.Spacing.md) {
                        macroCard(
                            icon: "leaf.fill", title: "Protein",
                            current: Int(viewModel.totalProtein),
                            target: Int(viewModel.currentGoal?.proteinTarget ?? 1),
                            unit: "g", color: tc.macroBarProtein,
                            progress: viewModel.proteinProgress
                        )
                        macroCard(
                            icon: "flame.fill", title: "Carbs",
                            current: Int(viewModel.totalCarbs),
                            target: Int(viewModel.currentGoal?.carbTarget ?? 1),
                            unit: "g", color: tc.macroBarCarbs,
                            progress: viewModel.carbProgress
                        )
                        macroCard(
                            icon: "drop.fill", title: "Fat",
                            current: Int(viewModel.totalFat),
                            target: Int(viewModel.currentGoal?.fatTarget ?? 1),
                            unit: "g", color: tc.macroBarFat,
                            progress: viewModel.fatProgress
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, DesignSystem.Spacing.lg) // space for page dots

                // Page 2: Additional nutrients detail
                nutrientsDetailPage
                    .padding(.bottom, DesignSystem.Spacing.lg)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 400)

            if settings.trackAdvancedNutrition {
                AdvancedNutrientsGrid(entries: viewModel.displayedEntries, goal: viewModel.currentGoal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.2), fillColor: tc.cardBackground)
    }

    // MARK: - Food Hero (Erewhon, D3)

    /// Mockup `.food-hero`: mini calorie ring + three macro tracks. Uses the existing
    /// calorie/macro progress values; ring figure + macro values in display (D9).
    private var foodHeroClean: some View {
        HStack(alignment: .center, spacing: 18) {
            miniRingClean
            VStack(spacing: 13) {
                macroTrackClean(
                    label: "Protein",
                    value: Int(viewModel.totalProtein),
                    target: Int(viewModel.currentGoal?.proteinTarget ?? 1),
                    unit: "g",
                    progress: viewModel.proteinProgress,
                    color: tc.macroBarProtein
                )
                macroTrackClean(
                    label: "Carbs",
                    value: Int(viewModel.totalCarbs),
                    target: Int(viewModel.currentGoal?.carbTarget ?? 1),
                    unit: "g",
                    progress: viewModel.carbProgress,
                    color: tc.macroBarCarbs
                )
                macroTrackClean(
                    label: "Fat",
                    value: Int(viewModel.totalFat),
                    target: Int(viewModel.currentGoal?.fatTarget ?? 1),
                    unit: "g",
                    progress: viewModel.fatProgress,
                    color: tc.macroBarFat
                )
            }

            // WATER-1 D12: the fourth track. The carrier is ZERO-HEIGHT and reserves only
            // the column's width, so switching water on cannot change the food hero's
            // height — the macro stack still sets it. The column is drawn in the carrier's
            // overlay, and because the HStack is centre-aligned every child's centre lands
            // on the same line: carrier centre == macro-stack centre.
            if settings.waterTrackerEnabled {
                Color.clear
                    .frame(width: WaterConstants.vesselWidth, height: 0)
                    .overlay(waterColumnClean)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Water Column (WATER-1 D12/D13/D14)

    /// The column: a macro-track-equivalent top block, then the vessel, and NOTHING below.
    ///
    /// That shape is the whole centring rule and it is structural, not a nudge. A macro
    /// track is `[label][6][bar]`, so the macro stack is top-heavy by exactly
    /// `labelHeight/2 + 3` relative to its own centre — and so is this column, for any
    /// label height. Ordinary centre alignment therefore puts the vessel's centre on the
    /// bar run's centre at every text size, with no offset to maintain.
    private var waterColumnClean: some View {
        VStack(spacing: 6) {
            waterCountLabel
            waterVessel
        }
    }

    /// Current count only — the hero drops the mockup's "cups" caption, because the bottom
    /// block must be zero for the centring rule above. Ink token, display type.
    private var waterCountLabel: some View {
        ZStack {
            // Invisible stand-in for a macro track's label row — the same three fonts on one
            // baseline, in the same HStack shape `macroTrackClean` uses — so this block is
            // exactly as tall as a macro label row at every text scale. Load-bearing, not
            // decoration: it is what makes the centring structural instead of a magic offset.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("W").font(AppFont.bold(12))
                Text("0").font(AppFont.display(13))
                Text("g").font(AppFont.regular(11))
            }
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)

            // The reading is labelled on the leaf, not on a merged container: the column
            // lives in a zero-height carrier's overlay, and a container element there does
            // not collapse — VoiceOver read a bare "0". This is also what keeps the count
            // accessible without depending on any animation state.
            Text(waterReadingText)
                .font(AppFont.display(13))
                .foregroundColor(tc.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Water")
                .accessibilityValue(waterReadingAccessibilityValue)
        }
        .frame(width: WaterConstants.vesselWidth)
    }

    /// The vessel: quantised water inside a curved themed shell (the rev-10 hybrid — one
    /// renderer, both themes). The shell owns the edge and takes theme tokens; only the
    /// water uses `waterFill`.
    private var waterVessel: some View {
        let count = viewModel.waterCupCount
        let goal = viewModel.waterGoalCups
        let units = WaterConstants.filledUnits(count: count, goal: goal)
        let isStill = count >= goal          // goal met or overfull: the water goes still
        let isOver = count > goal

        return ZStack(alignment: .bottom) {
            // Empty state falls out for free: no fill, and therefore no crest and no motion.
            if units > 0 {
                waterFillBody(units: units, isStill: isStill, isOver: isOver)
            }
        }
        // `alignment: .bottom` is load-bearing: the ZStack sizes to the fill, and a bare
        // `.frame` would CENTRE that block in the vessel — the water floated mid-column.
        .frame(
            width: WaterConstants.vesselWidth,
            height: WaterConstants.vesselHeight,
            alignment: .bottom
        )
        .background(
            RoundedRectangle(cornerRadius: WaterConstants.vesselRadius)
                .fill(tc.ringEmpty)          // same track as the macro bars beside it
        )
        .clipShape(RoundedRectangle(cornerRadius: WaterConstants.vesselRadius))
        .overlay(
            RoundedRectangle(cornerRadius: WaterConstants.vesselRadius)
                .stroke(
                    isOver ? tc.waterFill.adjustedBrightness(0.08) : DesignSystem.Erewhon.line,
                    lineWidth: 1
                )
        )
        // Overfull glow: brimming, never a warning. Breathes when motion is allowed and
        // stays lit at full strength when it is not.
        .shadow(
            color: isOver
                ? tc.waterFill.opacity(waterOverfullBreathing && !reduceMotion ? 0.72 : 1.0).opacity(0.5)
                : .clear,
            radius: isOver ? 7 : 0
        )
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: units)
        .overlay(waterGoalRing)              // drawn OUTSIDE the clip so it can expand past it
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                waterOverfullBreathing = true
            }
        }
    }

    /// The fill itself: a quantised body plus the stepped crest that rides its surface.
    private func waterFillBody(units: Int, isStill: Bool, isOver: Bool) -> some View {
        let height = CGFloat(units) * WaterConstants.unitSize
        return Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        isOver ? tc.waterFill.adjustedBrightness(0.06) : tc.waterFill,
                        tc.waterFill.adjustedBrightness(-0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: height)
            .overlay(alignment: .top) {
                waterCrest(isStill: isStill)
                    .opacity(isStill ? 0 : 1)
                    .animation(.easeOut(duration: 0.32), value: isStill)
            }
            // One unit of inset at each end — the mockup's outline slot, kept in the hybrid
            // so the fill never fights the shell's corners.
            .padding(.bottom, WaterConstants.unitSize)
    }

    /// The stepped waterline. Drift is a rotation of the crest's index, never a sub-unit
    /// translate, so every frame lands on the grid (the mockup's `steps(8)`, load-bearing).
    /// Reduce Motion holds it still mid-crest rather than snapping it flat.
    private func waterCrest(isStill: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: WaterConstants.waveStepSeconds)) { context in
            let frozen = isStill || reduceMotion
            let phase = frozen ? 0 : waterCrestPhase(at: context.date)
            let columns = Int(
                (WaterConstants.vesselWidth / WaterConstants.unitSize).rounded(.up)
            )
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { column in
                    let profile = WaterConstants.crestProfile
                    let rise = profile[(column + phase) % profile.count]
                    // Foam sits ON the crest: one unit, at the waterline or one unit above it.
                    Rectangle()
                        .fill(Color.white.opacity(0.85))   // specular only — never on the page
                        .frame(width: WaterConstants.unitSize, height: WaterConstants.unitSize)
                        .offset(y: -CGFloat(rise) * WaterConstants.unitSize)
                }
            }
        }
    }

    /// Whole-unit wave phase for a given instant.
    private func waterCrestPhase(at date: Date) -> Int {
        let steps = Int(date.timeIntervalSinceReferenceDate / WaterConstants.waveStepSeconds)
        let period = WaterConstants.crestProfile.count
        return ((steps % period) + period) % period
    }

    /// One-shot arrival ring. Fires ONLY from a goal crossing (see `addWaterCup`) — never
    /// on a redraw, never from a goal edit, and suppressed entirely under Reduce Motion.
    ///
    /// Built fresh per crossing (`.id(token)`) and animated from `onAppear`, the same shape
    /// the splash uses. That indirection is load-bearing: driving scale+opacity from one
    /// 0->1 state does NOT work, because SwiftUI interpolates between the START and END
    /// modifier values — a ring that ends at opacity 0 and only *exists* while firing is
    /// invisible for its whole life. Caught on video; the ring band measured flat zero.
    @ViewBuilder
    private var waterGoalRing: some View {
        if waterGoalRingActive {
            WaterGoalRing(color: tc.waterFill, cornerRadius: WaterConstants.vesselRadius)
                .id(waterGoalRingToken)
                .allowsHitTesting(false)
        }
    }

    /// The count as rendered: cups, or `count x mlPerCup` in ml mode.
    private var waterReadingText: String {
        switch settings.waterUnit {
        case .cups: return "\(viewModel.waterCupCount)"
        case .ml:   return "\(WaterConstants.milliliters(cups: viewModel.waterCupCount))"
        }
    }

    /// Spoken reading for both the column and the button, in the unit on screen.
    private var waterReadingAccessibilityValue: String {
        switch settings.waterUnit {
        case .cups:
            return "\(viewModel.waterCupCount) of \(viewModel.waterGoalCups) cups"
        case .ml:
            let current = WaterConstants.milliliters(cups: viewModel.waterCupCount)
            let target = WaterConstants.milliliters(cups: viewModel.waterGoalCups)
            return "\(current) of \(target) millilitres"
        }
    }

    // MARK: - Water Corner Button (WATER-1 D15)

    /// The add control: a disc of water, so striking it is what splashes. Tap = +1;
    /// long-press = -1. `ExclusiveGesture` (long press first) is what keeps a held press
    /// from also firing the tap on release and netting zero.
    private var waterAddButton: some View {
        let longPress = LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in removeWaterCup() }
        let tap = TapGesture().onEnded { addWaterCup() }

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tc.waterFill, tc.waterFill.adjustedBrightness(-0.30)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Image(systemName: "drop.fill")
                .font(AppFont.bold(20))
                // Knocked out in a deep tone derived from the water itself: the disc is the
                // same pale cyan in both themes, so the glyph must be dark in both.
                .foregroundColor(tc.waterFill.adjustedBrightness(-0.55))
        }
        .frame(width: WaterConstants.buttonDiameter, height: WaterConstants.buttonDiameter)
        .scaleEffect(waterDiscScale)
        .shadow(color: tc.waterFill.opacity(0.34), radius: 9, x: 0, y: 6)
        // Reduce Motion acknowledgement: a wash that brightens the disc and fades. Nothing
        // moves and nothing scales.
        .overlay {
            if waterPulseActive {
                WaterTapPulse(color: tc.waterFill)
                    .id(waterPulseToken)
                    .allowsHitTesting(false)
            }
        }
        // The crown and ripples clear the rim, so they are drawn OUTSIDE the disc and are
        // never clipped. Keyed by token: each tap builds a fresh burst instead of queueing.
        .overlay {
            if waterSplashRunning && !reduceMotion {
                WaterSplashBurst(
                    color: tc.waterFill,
                    discRadius: WaterConstants.buttonDiameter / 2
                )
                .id(waterSplashToken)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Circle())
        .gesture(longPress.exclusively(before: tap))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Add water")
        .accessibilityValue(waterReadingAccessibilityValue)
        // Long-press is not discoverable by VoiceOver, so decrement is exposed as a named
        // action rather than left behind the gesture.
        .accessibilityAction { addWaterCup() }
        .accessibilityAction(named: Text("Remove a cup")) { removeWaterCup() }
    }

    // MARK: - Water Actions (WATER-1 D14/D15)

    /// +1 cup. The feedback fires from the mutation's RESULT, so a crossing is a fact and
    /// not a prediction — that is what makes "success haptic replaces the impact" exact and
    /// keeps a failed write silent. The splash starts immediately and never waits on it.
    private func addWaterCup() {
        let before = viewModel.waterCupCount
        let goal = viewModel.waterGoalCups
        fireWaterSplash()

        Task {
            await viewModel.incrementWater()
            let after = viewModel.waterCupCount
            // The ring is per-CROSSING, not per-day: dropping back below the goal re-arms it.
            let crossed = before < goal && after >= goal
            if crossed && !reduceMotion { fireWaterGoalRing() }

            #if os(iOS)
            if crossed {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } else {
                // No escalation past the goal — cups 9, 10, 11 get the light impact again.
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            #endif
        }
    }

    /// -1 cup, floored at 0. At 0 this is a no-op with no haptic.
    private func removeWaterCup() {
        guard viewModel.waterCupCount > 0 else { return }
        Task {
            await viewModel.decrementWater()
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
            #endif
        }
    }

    /// Disc dip + rebound, plus the burst. Under Reduce Motion nothing moves or scales —
    /// a single 180 ms brightness decay acknowledges the tap instead.
    private func fireWaterSplash() {
        guard !reduceMotion else {
            // Built fresh per tap and animated from `onAppear`, like the ring and the
            // burst. Setting a flag true and animating it false in ONE update coalesces to
            // "no change" and renders nothing — measured: the disc's luma never moved.
            waterPulseToken += 1
            waterPulseActive = true
            let pulseToken = waterPulseToken
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                if waterPulseToken == pulseToken { waterPulseActive = false }
            }
            return
        }

        waterSplashToken += 1
        waterSplashRunning = true
        let token = waterSplashToken

        withAnimation(.easeOut(duration: 0.11)) { waterDiscScale = 0.86 }
        // A low-damping spring is what produces the ~1.07 rebound before it settles.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45).delay(0.11)) {
            waterDiscScale = 1
        }

        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if waterSplashToken == token { waterSplashRunning = false }
        }
    }

    /// The one-shot arrival ring, retargeted (never queued) if it fires again mid-flight.
    private func fireWaterGoalRing() {
        waterGoalRingToken += 1
        waterGoalRingActive = true
        let token = waterGoalRingToken

        Task {
            try? await Task.sleep(for: .milliseconds(560))
            if waterGoalRingToken == token { waterGoalRingActive = false }
        }
    }

    /// Mockup `.mini-ring`: calorie progress arc + centered display figure (D9).
    private var miniRingClean: some View {
        let goal = Int(viewModel.currentGoal?.calorieTarget ?? 2100)
        return ZStack {
            Circle()
                .stroke(tc.ringEmpty, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(viewModel.calorieProgress, 0), 1))
                .stroke(tc.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DesignSystem.Erewhon.ease(0.8), value: viewModel.calorieProgress)
            VStack(spacing: 4) {
                Text(viewModel.totalCalories.formatted())
                    .font(AppFont.display(22))
                    .foregroundColor(tc.textPrimary)
                    .contentTransition(.numericText())
                Text("of \(goal.formatted())")
                    .font(AppFont.regular(9))
                    .foregroundColor(tc.textTertiary)
            }
        }
        .frame(width: 104, height: 104)
    }

    /// Mockup `.fm`: colored macro label + display value/goal over a token track fill.
    ///
    /// WATER-1: this row's `spacing: 6` and its three label fonts are a SHARED CONVENTION
    /// with `waterCountLabel`, which mirrors both to stay exactly as tall as this label row.
    /// That equality is what centres the water vessel on the bar run with no magic offset —
    /// if either changes here, change it there too.
    private func macroTrackClean(
        label: String, value: Int, target: Int, unit: String,
        progress: Double, color: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.bold(12))
                    .foregroundColor(color)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)")
                        .font(AppFont.display(13))
                        .foregroundColor(tc.textPrimary)
                        .contentTransition(.numericText())
                    Text("/ \(target) \(unit)")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tc.ringEmpty)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Nutrition Details (Erewhon detgrid, D4)

    /// Mockup `.detgrid`: 3-column hairline grid of logged advanced nutrients. Values in
    /// display, units in Hanken (D9). Gated by `trackAdvancedNutrition` — hidden entirely
    /// when off (deviation from the always-on mockup, noted).
    private var nutritionDetailsClean: some View {
        let entries = viewModel.displayedEntries
        let sugar = entries.compactMap(\.sugar).reduce(0, +)
        let fiber = entries.compactMap(\.fiber).reduce(0, +)
        let sodium = entries.compactMap(\.sodium).reduce(0, +)
        let satFat = entries.compactMap(\.saturatedFat).reduce(0, +)
        let cholesterol = entries.compactMap(\.cholesterol).reduce(0, +)
        let potassium = entries.compactMap(\.potassium).reduce(0, +)

        return VStack(spacing: 0) {
            secHead("Nutrition details", "Logged today")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1)
                ],
                spacing: 1
            ) {
                detCell(label: "Sugar", value: sugar, unit: "g")
                detCell(label: "Fiber", value: fiber, unit: "g")
                detCell(label: "Sodium", value: sodium, unit: "mg")
                detCell(label: "Sat. Fat", value: satFat, unit: "g")
                detCell(label: "Cholest.", value: cholesterol, unit: "mg")
                detCell(label: "Potassium", value: potassium, unit: "mg")
            }
            .background(DesignSystem.Erewhon.lineSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignSystem.Erewhon.line, lineWidth: 1)
            )
        }
    }

    private func detCell(label: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.regular(10.5))
                .foregroundColor(tc.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Int(value.rounded()).formatted())
                    .font(AppFont.display(19))
                    .foregroundColor(tc.textPrimary)
                Text(unit)
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .padding(.horizontal, 13)
        .background(tc.cardBackground)
    }

    // MARK: - Nutrients Detail Page (Page 2 of progress)

    private var nutrientsDetailPage: some View {
        let entries = viewModel.displayedEntries

        let totalSugar = entries.compactMap(\.sugar).reduce(0, +)
        let totalFiber = entries.compactMap(\.fiber).reduce(0, +)
        let totalSodium = entries.compactMap(\.sodium).reduce(0, +)
        let totalSatFat = entries.compactMap(\.saturatedFat).reduce(0, +)
        let totalCholesterol = entries.compactMap(\.cholesterol).reduce(0, +)
        let totalPotassium = entries.compactMap(\.potassium).reduce(0, +)

        return VStack(spacing: DesignSystem.Spacing.md) {
            Text("Nutrition Details")
                .font(AppFont.bold(DesignSystem.FontSizes.headline))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DesignSystem.Spacing.sm)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: DesignSystem.Spacing.md) {
                nutrientChip(label: "Sugar", value: String(format: "%.1f", totalSugar), unit: "g",
                             icon: "cube.fill", color: .pink)
                nutrientChip(label: "Fiber", value: String(format: "%.1f", totalFiber), unit: "g",
                             icon: "leaf", color: .green)
                nutrientChip(label: "Sodium", value: String(format: "%.0f", totalSodium), unit: "mg",
                             icon: "drop.halffull", color: .blue)
                nutrientChip(label: "Sat. Fat", value: String(format: "%.1f", totalSatFat), unit: "g",
                             icon: "drop.fill", color: .orange)
                nutrientChip(label: "Cholesterol", value: String(format: "%.0f", totalCholesterol), unit: "mg",
                             icon: "heart.fill", color: .red)
                nutrientChip(label: "Potassium", value: String(format: "%.0f", totalPotassium), unit: "mg",
                             icon: "bolt.fill", color: .purple)
            }

            Text("Logged values only — missing if food not entered")
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func nutrientChip(label: String, value: String, unit: String,
                               icon: String, color: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.bold(13))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    Text(unit)
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textTertiary)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: color.opacity(0.2), fillColor: color.opacity(0.08))
    }

    // MARK: - Recent Foods Section

    private var recentFoodsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if settings.isCleanUI {
                secHead("Recent foods", "Tap to add")
            } else {
                Text("Recent Foods")
                    .font(AppFont.bold(DesignSystem.FontSizes.title2))
                    .foregroundColor(tc.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(viewModel.recentFoods, id: \.id) { entry in
                        quickLogCard(entry: entry, showFavoriteButton: true)
                    }
                }
                .padding(.horizontal, 2)
            }
            // Don't inherit the outer ScrollView's bottom contentMargins on this
            // horizontal recents row (it would add an empty gap below the cards).
            .contentMargins(.bottom, 0, for: .scrollContent)
        }
    }

    // MARK: - Quick Log Card

    /// Rendered size of the quick-log card's photo/icon well (mockup `.ph`).
    private static let quickLogPhotoSize = CGSize(width: 120, height: 70)

    /// Mockup `.rfood`: photo/icon header + name + display calories + relative time, with
    /// the favorite star kept as an in-chip affordance (D5). Behavior (tap-to-quick-log,
    /// favorite toggle) unchanged; still fed by `recentFoods` only (no new dedup).
    private func quickLogCard(entry: FoodEntry, showFavoriteButton: Bool) -> some View {
        Button {
            Task { await viewModel.quickLog(entry) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Photo / icon area (mockup `.ph`)
                ZStack(alignment: .topTrailing) {
                    if let photoData = entry.photoData {
                        // PHOTOPERF-1: async decode at the rendered size; the placeholder
                        // holds the identical frame so the card never resizes on arrival.
                        DownsampledPhotoView(
                            photoData: photoData,
                            targetSize: Self.quickLogPhotoSize,
                            cacheKey: entry.id.uuidString
                        ) {
                            Rectangle().fill(tc.ringEmpty)
                        }
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(tc.ringEmpty)
                                .frame(width: Self.quickLogPhotoSize.width,
                                       height: Self.quickLogPhotoSize.height)
                            Image(systemName: "fork.knife")
                                .font(AppFont.regular(24))
                                .foregroundColor(tc.textSecondary)
                        }
                    }

                    if showFavoriteButton {
                        Button {
                            Task { await viewModel.toggleFavorite(entry) }
                        } label: {
                            Image(systemName: entry.isFavorite ? "star.fill" : "star")
                                .font(AppFont.bold(12))
                                .foregroundColor(entry.isFavorite ? tc.macroBarCarbs : .white)
                                .padding(5)
                                .background(
                                    Circle()
                                        .fill(entry.isFavorite
                                              ? tc.macroBarCarbs.opacity(0.2)
                                              : Color.black.opacity(0.4))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .offset(x: -4, y: 4)
                    }
                }

                // Meta (mockup `.meta`): name + calories/time
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(AppFont.bold(11.5))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: 30, alignment: .top)

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(entry.calories)")
                            .font(AppFont.display(13))
                            .foregroundColor(tc.textPrimary)
                        Spacer(minLength: 4)
                        Text("cal · \(viewModel.relativeTimeString(from: entry.date))")
                            .font(AppFont.regular(9))
                            .foregroundColor(tc.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .frame(width: 120)
            .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Macro Card (pixel progress only — Erewhon uses macroTrackClean)

    private func macroCard(
        icon: String, title: String,
        current: Int, target: Int, unit: String,
        color: Color, progress: Double
    ) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.bold(14))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .adaptivePill(
                    borderColor: color.adjustedBrightness(-0.2),
                    fillColor: .clear,
                    fillGradient: DesignSystem.Colors.adaptiveGradientFrom(color)
                )

            Text(title)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)

            Text("\(current)")
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text("/ \(target)\(unit)")
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tc.macroBarTrack)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1), height: 4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 4)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .adaptiveCard(borderColor: color.opacity(0.2), fillColor: tc.cardBackground)
    }

    // MARK: - Add to Log (Erewhon, D7)

    /// Mockup `.addlog`: three method rows wired to the SAME destinations the current add
    /// flow exposes (AI describe, food database, barcode). Additional surface — the
    /// per-section + entry points and the AddFoodChoiceSheet are untouched.
    private var addToLogSection: some View {
        VStack(spacing: 0) {
            secHead("Add to log", "Choose a method")
            VStack(spacing: 1) {
                addRow(
                    icon: "camera.viewfinder", title: "Scan food",
                    subtitle: "Describe or snap a photo, AI does the rest",
                    beta: true, accent: true
                ) {
                    viewModel.pendingMealType = .uncategorized
                    viewModel.openDescribeMeal()
                }
                // TUTFIX-1 aiLog beacon — the AI describe entry affordance (one target; retargeted
                // from the Home Quick Scan, which is barcode-only). A flat method row inside the
                // 14-radius group — trace it with the small radius.
                .questBeacon(TutorialCatalog.aiLogId, cornerRadius: DesignSystem.CornerRadius.sm)
                addRow(
                    icon: "magnifyingglass", title: "Food database",
                    subtitle: "Search thousands of foods",
                    beta: false, accent: false
                ) {
                    viewModel.pendingMealType = .uncategorized
                    viewModel.formMealType = .uncategorized
                    viewModel.showingFoodDatabase = true
                }
                // TUT-2 openDatabase beacon (Decision 3) — the food-database entry affordance (one target).
                // A flat method row inside the 14-radius group — trace it with the small radius.
                .questBeacon(TutorialCatalog.openDatabaseId, cornerRadius: DesignSystem.CornerRadius.sm)
                addRow(
                    icon: "barcode", title: "Scan barcode",
                    subtitle: "Auto-fill from product label",
                    beta: false, accent: false
                ) {
                    viewModel.pendingMealType = .uncategorized
                    viewModel.formMealType = .uncategorized
                    showingBarcodeOptions = true
                }
                // TUT-2 barcodeScan beacon (Decision 3) — the barcode entry affordance (one target).
                // A flat method row inside the 14-radius group — trace it with the small radius.
                .questBeacon(TutorialCatalog.barcodeScanId, cornerRadius: DesignSystem.CornerRadius.sm)
            }
            .background(DesignSystem.Erewhon.lineSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignSystem.Erewhon.line, lineWidth: 1)
            )
        }
    }

    /// Mockup `.addrow`: leading icon tile (accent-filled for the first row) + title
    /// (+ Beta tag) + subtitle + chevron.
    private func addRow(icon: String, title: String, subtitle: String,
                        beta: Bool, accent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(AppFont.regular(16))
                    .foregroundColor(accent ? DesignSystem.Erewhon.onAccent : tc.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accent ? tc.primary : tc.ringEmpty)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(AppFont.bold(13.5))
                            .foregroundColor(tc.textPrimary)
                        if beta {
                            Text("Beta")
                                .font(AppFont.regular(9))
                                .foregroundColor(tc.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(tc.primary.opacity(0.4), lineWidth: 1)
                                )
                        }
                    }
                    Text(subtitle)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(tc.cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Toast Overlay

    private func toastOverlay(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.bold(20))
                    .foregroundColor(.white)
                Text(message)
                    .font(AppFont.bold(DesignSystem.FontSizes.headline))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .adaptivePill(borderColor: tc.primary, fillColor: tc.primary, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showToast)
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - SwipeableEntryCard

/// Food entry card with swipe-left (edit + delete) and swipe-right (favorite) gestures.
/// Card is intentionally thin for a compact log view.
// MARK: - MEALROW-1: Photo Split Card

/// Photo-conditional split-card *face*: the photo fills the left `splitRatio`
/// of the card edge-to-edge; caller-supplied content fills the right. Layout ONLY —
/// background, border, and shadow come from the call site's card styling (the
/// adaptiveCard / flatCard family); this view adds none of its own. `cornerRadius`
/// matches the enclosing card so the photo's outer (left) corners round while its
/// inner (right) edge at the split line stays square. One shared type referenced by
/// both call sites (SwipeableEntryCard here + HomeView.mealSlot) — no per-surface copies.
///
/// PHOTOPERF-1: takes raw `photoData` and decodes it asynchronously at the rendered size
/// via `DownsampledPhotoView`. There is deliberately no `UIImage` initializer — a call
/// site that decoded eagerly just to construct this view would reintroduce the
/// main-thread decode this change removes.
struct PhotoSplitCard<Content: View>: View {
    let photoData: Data
    /// Stable identity of the photo's owning entry — the decode cache key's base.
    let cacheKey: String
    let cornerRadius: CGFloat
    var height: CGFloat = Layout.cardHeight
    @ViewBuilder let content: () -> Content

    private enum Layout {
        // Computed (not stored) so the enum can nest inside a generic type:
        // Swift disallows `static let` stored properties in generic types.
        static var splitRatio: CGFloat { 0.42 }
        static var cardHeight: CGFloat { 78 }
    }

    var body: some View {
        GeometryReader { proxy in
            let photoWidth = proxy.size.width * Layout.splitRatio
            HStack(spacing: 0) {
                DownsampledPhotoView(
                    photoData: photoData,
                    targetSize: CGSize(width: photoWidth, height: height),
                    cacheKey: cacheKey
                ) {
                    // Layout-only contract: no fill of its own, so the call site's card
                    // styling shows through for the frame or two before the decode lands.
                    Color.clear
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .accessibilityHidden(true)

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }
}

private struct SwipeableEntryCard: View {

    let entry: FoodEntry
    let onFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var offset: CGFloat = 0
    /// Offset captured at gesture start — used for context-aware snapping
    @State private var dragStartOffset: CGFloat = 0
    /// Direction lock: true=horizontal, false=vertical, nil=undecided
    @State private var isHorizontalDrag: Bool? = nil

    private let trailWidth: CGFloat = 128  // edit(64) + delete(64)
    private let leadWidth: CGFloat = 64    // favorite(64)

    var body: some View {
        ZStack(alignment: .center) {
            // Trailing actions: edit + delete (full-width HStack, buttons at trailing edge)
            if offset < -8 {
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(AppFont.bold(15))
                            .foregroundColor(.white)
                            .frame(width: 64)
                            .frame(maxHeight: .infinity)
                            .background(Color.blue)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(AppFont.bold(15))
                            .foregroundColor(.white)
                            .frame(width: 64)
                            .frame(maxHeight: .infinity)
                            .background(Color.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .clipShape(AdaptiveCardShapeStyle())
            }

            // Leading action: favorite (full-width HStack, button at leading edge)
            if offset > 8 {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.25)) { offset = 0 }
                        onFavorite()
                    } label: {
                        Image(systemName: entry.isFavorite ? "star.fill" : "star")
                            .font(AppFont.bold(15))
                            .foregroundColor(.white)
                            .frame(width: leadWidth)
                            .frame(maxHeight: .infinity)
                            .background(tc.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .clipShape(AdaptiveCardShapeStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            // Card content (thin layout)
            thinCard
                .offset(x: offset)
                .onTapGesture {
                    guard offset != 0 else { return }
                    withAnimation(.spring(response: 0.25)) { offset = 0 }
                }
        }
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height

                    // Determine and lock drag direction on first significant movement
                    if isHorizontalDrag == nil {
                        let ratio = abs(dx) / max(abs(dy), 0.001)
                        if ratio > 1.5 {
                            isHorizontalDrag = true
                            dragStartOffset = offset
                        } else if ratio < 0.67 {
                            isHorizontalDrag = false
                        }
                        // If ratio is between 0.67–1.5 (ambiguous), wait for more movement
                        return
                    }

                    guard isHorizontalDrag == true else { return }

                    withAnimation(.interactiveSpring(response: 0.3)) {
                        let proposed = dragStartOffset + dx
                        offset = max(-trailWidth, min(leadWidth, proposed))
                    }
                }
                .onEnded { value in
                    defer { isHorizontalDrag = nil }
                    guard isHorizontalDrag == true else { return }

                    let dx = value.translation.width
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if dragStartOffset < -trailWidth / 2 {
                            // Was on delete side: any rightward swipe (20px) closes, else stays open
                            offset = dx > 20 ? 0 : -trailWidth
                        } else if dragStartOffset > leadWidth / 2 {
                            // Was on favorite side: any leftward swipe (20px) closes, else stays open
                            offset = dx < -20 ? 0 : leadWidth
                        } else {
                            // Near center: threshold-based snap
                            if dx < -40 { offset = -trailWidth }
                            else if dx > 40 { offset = leadWidth }
                            else { offset = 0 }
                        }
                    }
                }
        )
        .draggable(entry.id.uuidString)
    }

    // Fix #7: Thin card layout
    // MEALROW-1: photo-conditional — split-card face when a photo EXISTS (photo left,
    // the existing content restacked right), else the existing thin row unchanged.
    // PHOTOPERF-1: the branch keys on `photoData != nil` rather than on decode success,
    // so the split face no longer waits on a main-thread decode; a corrupt photo keeps
    // the split face and shows the placeholder, matching "photo exists" semantics.
    @ViewBuilder
    private var thinCard: some View {
        if let photoData = entry.photoData {
            PhotoSplitCard(photoData: photoData,
                           cacheKey: entry.id.uuidString,
                           cornerRadius: DesignSystem.Erewhon.cardRadius) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // Food info: name + cal + time on two lines
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(AppFont.regular(16))
                            .foregroundColor(tc.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text("\(entry.calories) cal")
                                .font(AppFont.bold(14))
                                .foregroundColor(tc.primary)
                            Text("·")
                                .font(AppFont.regular(DesignSystem.FontSizes.caption))
                                .foregroundColor(tc.textTertiary)
                            Text(timeString(from: entry.date))
                                .font(AppFont.regular(12))
                                .foregroundColor(tc.textTertiary)
                            if entry.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(AppFont.regular(9))
                                    .foregroundColor(tc.macroBarCarbs)
                            }
                        }
                    }

                    Spacer()

                    // Three-dot menu
                    Menu {
                        Button {
                            onFavorite()
                        } label: {
                            Label(
                                entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: entry.isFavorite ? "star.slash" : "star"
                            )
                        }

                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(AppFont.regular(16))
                            .foregroundColor(tc.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
            .adaptiveCard(borderColor: tc.primary.opacity(0.15), fillColor: tc.cardBackground)
        } else {
            // Reached only when `entry.photoData == nil`, so the 32×32 thumbnail this
            // branch used to carry was unreachable (MEALROW-1 left it behind when it added
            // the split-card face above, which already tested the same condition).
            // PHOTOPERF-1 removed it.
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Food info: name + cal + time on two lines
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(entry.calories) cal")
                            .font(AppFont.bold(14))
                            .foregroundColor(tc.primary)
                        Text("·")
                            .font(AppFont.regular(DesignSystem.FontSizes.caption))
                            .foregroundColor(tc.textTertiary)
                        Text(timeString(from: entry.date))
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textTertiary)
                        if entry.isFavorite {
                            Image(systemName: "star.fill")
                                .font(AppFont.regular(9))
                                .foregroundColor(tc.macroBarCarbs)
                        }
                    }
                }

                Spacer()

                // Three-dot menu
                Menu {
                    Button {
                        onFavorite()
                    } label: {
                        Label(
                            entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: entry.isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: tc.primary.opacity(0.15), fillColor: tc.cardBackground)
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Water Tap Pulse (WATER-1 D15, Reduce Motion)

/// The Reduce-Motion acknowledgement: a brightening wash over the disc that fades over
/// 180 ms. No crown, no ripples, no dip — nothing that moves or scales — but the tap is
/// still unmistakable. Created fresh per tap so repeat taps restart it.
private struct WaterTapPulse: View {

    let color: Color

    @State private var faded = false

    var body: some View {
        Circle()
            .fill(color)
            .opacity(faded ? 0 : 0.55)
            .onAppear {
                withAnimation(.easeOut(duration: 0.18)) { faded = true }
            }
    }
}

// MARK: - Water Goal Ring (WATER-1 D14)

/// The arrival ring: expands past the vessel's own clip and fades, once, on the tap that
/// crosses the goal. Created fresh per crossing and animated from `onAppear` so a repeat
/// crossing restarts it rather than queueing behind it.
private struct WaterGoalRing: View {

    let color: Color
    let cornerRadius: CGFloat

    @State private var expanded = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(color, lineWidth: 2)
            .scaleEffect(expanded ? 1.34 : 1)
            .opacity(expanded ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.52)) { expanded = true }
            }
    }
}

// MARK: - Water Splash Burst (WATER-1 D15)

/// The struck-water burst: three expanding ripples plus a crown thrown clear of the rim.
///
/// Built to be created fresh per tap (`.id(token)` at the call site) and animated from
/// `onAppear`, which is what makes a second tap RETARGET the burst rather than queue behind
/// it. Purely decorative and non-interactive; never rendered under Reduce Motion.
private struct WaterSplashBurst: View {

    let color: Color
    /// Radius of the disc being struck — the crown's throw distances are fractions of it.
    let discRadius: CGFloat

    /// Ripple stagger, mockup §4: 0 / 80 / 150 ms.
    private static let rippleDelays: [Double] = [0, 0.08, 0.15]

    /// Crown droplets: angle in degrees and throw distance as a fraction of the disc radius.
    /// Angles and distances vary together — an evenly spaced crown of identical dots reads
    /// as a mechanical starburst rather than thrown water.
    private static let crown: [(angle: Double, throwFactor: CGFloat, size: CGFloat, delay: Double)] = [
        (-90, 1.00, 4.0, 0.00), (-58, 0.82, 3.0, 0.02), (-122, 0.86, 3.5, 0.01),
        (-26, 0.74, 2.5, 0.03), (-154, 0.78, 3.0, 0.02), (6, 0.68, 2.5, 0.03),
        (-186, 0.70, 2.5, 0.01), (-72, 0.92, 2.5, 0.02)
    ]

    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(Array(Self.rippleDelays.enumerated()), id: \.offset) { index, delay in
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: discRadius * 2, height: discRadius * 2)
                    .scaleEffect(expanded ? 2.45 : 0.3)
                    .opacity(expanded ? 0 : 0.85)
                    .animation(.easeOut(duration: 0.42).delay(delay), value: expanded)
                    .id(index)
            }

            ForEach(Array(Self.crown.enumerated()), id: \.offset) { _, droplet in
                let radians = droplet.angle * .pi / 180
                let distance = expanded ? discRadius * droplet.throwFactor : 0
                Circle()
                    .fill(color)
                    .frame(width: droplet.size, height: droplet.size)
                    .offset(
                        x: distance * CGFloat(cos(radians)),
                        y: distance * CGFloat(sin(radians))
                    )
                    .opacity(expanded ? 0 : 1)
                    .animation(.easeOut(duration: 0.38).delay(droplet.delay), value: expanded)
            }
        }
        .onAppear { expanded = true }
    }
}

// MARK: - Preview

#Preview("Food Log - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let sampleEntry1 = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )
    sampleEntry1.mealType = .lunch

    let sampleEntry2 = FoodEntry(
        name: "Protein Smoothie",
        date: Date().addingTimeInterval(-3600),
        calories: 320,
        protein: 28.0,
        carbs: 35.0,
        fat: 8.0,
        toxinScore: 20
    )
    sampleEntry2.mealType = .breakfast

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 0,
        currentStreak: 0,
        longestStreak: 0,
        lastActiveDate: Date()
    )

    context.insert(sampleEntry1)
    context.insert(sampleEntry2)
    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)
    return FoodLogView(coordinator: coordinator)
}

#Preview("Food Log - Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 0,
        currentStreak: 0,
        longestStreak: 0,
        lastActiveDate: Date()
    )

    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)
    return FoodLogView(coordinator: coordinator)
}
