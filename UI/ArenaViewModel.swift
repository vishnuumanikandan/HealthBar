//
//  ArenaViewModel.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import Foundation

/// Drives the Arena — the signature single-duel view (D1c). Pure presentation over a
/// `DuelDTO`; refresh funnels through the coordinator's full `loadMyDuels()` lifecycle.
@Observable
@MainActor
final class ArenaViewModel {

    private let coordinator: AppCoordinator
    private let myUid: String

    private(set) var duel: DuelDTO
    /// True when the last refresh could not find this duel (deleted/canceled elsewhere).
    private(set) var isStale = false
    private(set) var inFlight = false
    var toastMessage: String?

    /// D3b/D4: MY fighter-head avatar, from the LIVE local profile (freshest; never the possibly
    /// stale/absent duel snapshot). Loaded on refresh; nil ⇒ the initials fallback.
    private(set) var myAvatarIcon: String?
    private(set) var myAvatarColor: String?

    /// DUEL-CLARITY-1: MY day-score components for the "YOUR POINTS TODAY" card. My side only —
    /// the opponent's food data is private, so their score stays a bare total everywhere.
    /// Loaded inside `refresh()`; `.zero` until the first pass completes.
    private(set) var breakdown: DayScoreBreakdown = .zero

    init(coordinator: AppCoordinator, myUid: String, duel: DuelDTO) {
        self.coordinator = coordinator
        self.myUid = myUid
        self.duel = duel
    }

    func refresh() async {
        let all = await coordinator.loadMyDuels()
        if let fresh = all.first(where: { $0.id == duel.id }) {
            duel = fresh
            isStale = false
        } else {
            isStale = true // keep last-known render; no pop, no alert
        }
        // D3b: my own avatar from the local profile record (D3a accessor) for MY fighter head.
        let profile = try? await coordinator.getUserProfile()
        myAvatarIcon = profile?.avatarIcon
        myAvatarColor = profile?.avatarColor
        // DUEL-CLARITY-1: my live day components, awaited in this same refresh pass — one
        // lifecycle, no second `.task`. The day is global, so the same figures appear in every
        // active Arena (that is the point: today's points count in all of them).
        breakdown = await coordinator.dayScoreBreakdown(for: Date())
        await coordinator.markDuelsSeen([duel], isFullList: false)
    }

    // MARK: - Rounding helper (rounded-int convention; never raw Double compare)

    private func tenths(_ v: Double) -> Int { Int((v * 10).rounded()) }

    // MARK: - Display

    var myLabel: String { "You" }
    var theirLabel: String { duel.opponentLabel(of: myUid) }

    // MARK: - Opponent identity (NAV-1b profile threading)

    /// The other participant's uid — side-aware (I may be challenger or opponent).
    var theirUid: String { duel.isChallenger(myUid) ? duel.opponentUid : duel.challengerUid }
    /// Stamped identity snapshots off the DTO (display-only; mirrors `opponentLabel(of:)`).
    var theirUsername: String { duel.isChallenger(myUid) ? duel.opponentUsername : duel.challengerUsername }
    var theirDisplayName: String { duel.isChallenger(myUid) ? duel.opponentDisplayName : duel.challengerDisplayName }
    /// D3b/D4: THEIR fighter-head avatar — the COUNTERPARTY side of the duel snapshot, via the same
    /// challenger/opponent ownership logic as the names/scores (no new branching). nil ⇒ initials.
    var theirAvatarIcon: String? { duel.isChallenger(myUid) ? duel.opponentAvatarIcon : duel.challengerAvatarIcon }
    var theirAvatarColor: String? { duel.isChallenger(myUid) ? duel.opponentAvatarColor : duel.challengerAvatarColor }
    /// A blocked opponent leaves the head inert — active duels are never touched (UGC-1b).
    var canOpenOpponentProfile: Bool { !coordinator.isBlocked(theirUid) }

    var myScore: Double { duel.myScore(myUid) }
    var theirScore: Double { duel.theirScore(myUid) }
    var myScoreText: String { "\(Int(myScore.rounded()))" }
    var theirScoreText: String { "\(Int(theirScore.rounded()))" }
    var iAmLeading: Bool { tenths(myScore) > tenths(theirScore) }
    var league: Int { duel.league }
    func leagueLabel() -> String { "\(duel.league)-DAY" }

    var isActive: Bool { duel.statusEnum == .active }
    var isFinished: Bool { duel.statusEnum == .resolved || duel.statusEnum == .forfeited }
    var endAt: Date? { duel.endAt }
    var resolvedAt: Date? { duel.resolvedAt }

    /// Fill fraction of the tug-of-war bar. 0.5 at a rounded tie or 0–0; else my share of the
    /// total, clamped so neither side is ever fully pushed out.
    var barFraction: Double {
        let m = tenths(myScore), t = tenths(theirScore)
        if m == t { return 0.5 }               // covers 0–0 and any exact tie
        let total = myScore + theirScore
        guard total > 0 else { return 0.5 }
        return min(0.92, max(0.08, myScore / total))
    }

    /// Endgame: less than one duel-day remaining (reuse the constant — no magic 86_400).
    var isEndgame: Bool {
        guard isActive, let endAt = duel.endAt else { return false }
        return endAt.timeIntervalSinceNow < DuelConstants.secondsPerDay
    }

    // MARK: - My-side breakdown (DUEL-CLARITY-1)

    /// The breakdown card is an ACTIVE-duel affordance — a finished duel's day is over, so it
    /// is hidden there (the card would describe a day that can no longer change the result).
    var showBreakdown: Bool { isActive }

    /// Trailing in THIS duel — the comeback multiplier's condition, using the same strict
    /// rounded-tenths comparison as the scoring pass (a tie is NOT trailing).
    var iAmTrailing: Bool { tenths(myScore) < tenths(theirScore) }

    /// Points rendered at the app's 1-decimal day-score convention ("30", "17.9").
    func pointsText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// One sentence naming the largest remaining gap. FIXED copy table keyed by category —
    /// never free-form. Ties resolve in primer order via `largestGapComponent`.
    var breakdownHint: String {
        guard let gap = breakdown.largestGapComponent else {
            // Everything banked. N is the max-day-score constant, never a literal.
            return "Perfect day so far — all \(pointsText(DuelConstants.maxDayScore)) points banked."
        }
        let n = pointsText(breakdown.remaining(gap))
        switch gap {
        case .calories: return "Log under your calorie goal to bank the last \(n) calorie points."
        case .protein:  return "Hit your protein target to bank \(n) more points."
        case .purity:   return "Keep meals clean to bank \(n) more purity points."
        case .quests:   return "Finish today's quests for \(n) more points."
        case .qteBonus: return "QTE events can add \(n) more points."
        }
    }

    /// The comeback callout, appended only while I'm behind in THIS duel (the multiplier is
    /// per-duel). nil otherwise. The multiplier comes from the constants.
    var comebackCallout: String? {
        guard isActive, iAmTrailing else { return nil }
        return "You're behind — QTE points count ×\(DuelConstants.comebackMultiplier.formatted(.number.precision(.fractionLength(0...2)))) in this duel."
    }

    // MARK: - Score feed (DUEL-FEED-1)

    /// Both sides' category-level score events, straight off the already-refreshed duel — pure
    /// passthroughs, so no new state, no new load and no listener. `refresh()` already refetches
    /// the duel, which is what makes the feed current on appear and on pull-to-refresh.
    var myFeedEvents: [DuelFeedEventDTO] { duel.myFeedEvents(myUid) }
    var theirFeedEvents: [DuelFeedEventDTO] { duel.theirFeedEvents(myUid) }

    // MARK: - Day timeline

    struct DayRow: Identifiable {
        enum State { case done, current, upcoming }
        let dayNumber: Int
        let myScore: Double?
        let theirScore: Double?
        let state: State
        var id: Int { dayNumber }

        /// true → I won the day, false → they did, nil → tie / incomplete (no marker).
        var myWins: Bool? {
            guard let m = myScore, let t = theirScore else { return nil }
            let mi = Int((m * 10).rounded()), ti = Int((t * 10).rounded())
            if mi == ti { return nil }
            return mi > ti
        }
    }

    var dayRows: [DayRow] {
        let myDays = duel.isChallenger(myUid) ? duel.resolvedChallengerDayScores : duel.resolvedOpponentDayScores
        let theirDays = duel.isChallenger(myUid) ? duel.resolvedOpponentDayScores : duel.resolvedChallengerDayScores
        let calendar = Calendar.current

        // Current duel-day index (same definition as updateMyDuelScores). -1 when finished
        // or acceptedAt missing → no `current` row.
        var currentIndex = -1
        if isActive, let acceptedAt = duel.acceptedAt {
            let day1 = calendar.startOfDay(for: acceptedAt)
            let today = calendar.startOfDay(for: Date())
            currentIndex = calendar.dateComponents([.day], from: day1, to: today).day ?? -1
        }

        return (0..<max(0, duel.league)).map { idx in
            let my = idx < myDays.count ? myDays[idx] : nil
            let their = idx < theirDays.count ? theirDays[idx] : nil
            let state: DayRow.State
            if isFinished || idx < currentIndex {
                state = .done
            } else if idx == currentIndex {
                state = .current
            } else {
                state = .upcoming
            }
            return DayRow(dayNumber: idx + 1, myScore: my, theirScore: their, state: state)
        }
    }

    // MARK: - Finished / projected

    /// Reuses the exact wording logic of BattleViewModel.finishedLabel (duplicated locally
    /// per the D1c spec — do not rename or change that method).
    var outcomeHeadline: String {
        switch duel.statusEnum {
        case .forfeited: return duel.forfeitedBy == myUid ? "Forfeit" : "Won"
        case .resolved:
            if duel.winnerUid == nil { return "Draw" }
            return duel.winnerUid == myUid ? "Won" : "Lost"
        default: return duel.status.capitalized
        }
    }

    var rrDeltaText: String? {
        guard isFinished, let delta = duel.myRRDelta(myUid) else { return nil }
        return delta >= 0 ? "+\(delta) RR" : "\(delta) RR"
    }

    var canRematch: Bool {
        guard isFinished, let resolvedAt = duel.resolvedAt else { return false }
        return Date() < resolvedAt.addingTimeInterval(DuelConstants.rematchWindow)
    }

    /// Projected RR — a preview of the deterministic resolution at the current leader, not a
    /// promise. Active duels only.
    var projectedRRText: String? {
        guard isActive else { return nil }
        let winner = DuelDTO.scoreWinner(challengerScore: duel.challengerScore, opponentScore: duel.opponentScore)
        if winner == .draw { return "Projected: draw · +\(DuelConstants.drawDelta(league: duel.league)) each" }
        let deltas = DuelDTO.resolveDeltas(duelId: duel.id ?? "", league: duel.league, winner: winner)
        let myDelta = duel.isChallenger(myUid) ? deltas.challenger : deltas.opponent
        let theirDelta = duel.isChallenger(myUid) ? deltas.opponent : deltas.challenger
        let mySign = myDelta >= 0 ? "+" : ""
        let theirSign = theirDelta >= 0 ? "+" : ""
        return "Projected: You \(mySign)\(myDelta) · \(theirLabel) \(theirSign)\(theirDelta)"
    }

    // MARK: - Actions (same shape as BattleViewModel)

    func forfeit() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            try await coordinator.forfeitDuel(duel)
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't forfeit."
        }
        await refresh()
    }

    func rematch() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            try await coordinator.rematch(duel)
            toastMessage = "Rematch sent"
        } catch {
            toastMessage = (error as? DuelError)?.errorDescription ?? "Couldn't send the rematch."
        }
        await refresh()
    }
}
