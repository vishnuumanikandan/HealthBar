//
//  DuelDTO.swift
//  HealthBar
//
//  Created by Claude on 7/3/26.
//

import Foundation

/// The lifecycle status of a duel.
///
/// String literals for status are FORBIDDEN outside this type — every comparison
/// and every write goes through the enum (`DuelStatus.pending.rawValue`), so a
/// typo'd `"Pending"` can never slip in. The stored/synced field stays a plain
/// `String` (via `DuelDTO.status`) so an unknown future status never breaks decode.
///
/// D1a uses `pending`/`active`/`declined`/`expired`. `resolved`/`forfeited` are
/// reserved for D1b (scoring/resolution) — declared here so the schema is stable,
/// but no D1a code writes them.
enum DuelStatus: String {
    case pending
    case active
    case declined
    case expired
    case resolved   // reserved (D1b)
    case forfeited  // reserved (D1b)
}

/// Duel tuning constants — no magic numbers at call sites. Every `48h`, `86400`,
/// and league validation in the duel flow references these.
enum DuelConstants {
    /// Valid league durations, in days.
    static let leagues = [1, 3, 5]
    /// A pending challenge auto-expires this long after creation.
    static let responseWindow: TimeInterval = 48 * 3600
    /// `endAt = acceptedAt + league * secondsPerDay` (rolling window from accept).
    static let secondsPerDay: TimeInterval = 86_400

    // MARK: - D2.5: league-scaled RR deltas (integer ranges — NEVER derive by
    // multiplying+rounding). THIS TABLE IS THE CANONICAL RR TUNING TABLE:
    // firestore.rules isResolve/isForfeit must mirror it exactly; any future
    // balancing edits BOTH places in the same change.
    //  league   win        loss (earned)   draw   forfeiter (FIXED)   forfeit-winner
    //  1-day    25...30    -25...(-20)     10     -25                 5...10
    //  3-day    38...45    -30...(-25)     15     -30                 8...15
    //  5-day    50...60    -40...(-30)     20     -40                 10...20
    // The forfeiter value is intentionally == the league's loss-range minimum (the
    // harshest earned loss). Unknown league falls back to the 1-day row (defensive
    // only — league is create-rule-validated to [1,3,5]).

    /// RR gained by a genuine winner, by league.
    static func winDelta(league: Int) -> ClosedRange<Int> {
        switch league { case 3: return 38...45; case 5: return 50...60; default: return 25...30 }
    }
    /// RR lost by an earned loser, by league (tightened + sub-linear — losses stay gentler than wins).
    static func lossDelta(league: Int) -> ClosedRange<Int> {
        switch league { case 3: return (-30)...(-25); case 5: return (-40)...(-30); default: return (-25)...(-20) }
    }
    /// RR both sides gain on a draw (fixed, no roll), by league.
    static func drawDelta(league: Int) -> Int {
        switch league { case 3: return 15; case 5: return 20; default: return 10 }
    }
    /// The forfeiter's FIXED penalty == the league's harshest earned loss (never cheaper
    /// than the worst earned loss). No roll.
    static func forfeitLossDelta(league: Int) -> Int {
        switch league { case 3: return -30; case 5: return -40; default: return -25 }
    }
    /// RR the non-forfeiting side gains on a forfeit (an unearned win), by league.
    static func forfeitWinnerDelta(league: Int) -> ClosedRange<Int> {
        switch league { case 3: return 8...15; case 5: return 10...20; default: return 5...10 }
    }
    /// Rematch is offered for this long after resolvedAt.
    static let rematchWindow: TimeInterval = 24 * 3600

    // MARK: - D1b: day-score component maxima (see DataManager.dayScore)
    static let maxDayScore = 110.0
    static let caloriePoints = 30.0
    static let proteinPoints = 25.0
    static let purityPoints = 25.0
    static let questPoints = 20.0
    /// QTE bonus cap per day (see DataManager.qteBonus).
    static let qteBonusCap = 10.0

    // MARK: - D1d: QTE tuning
    /// Per-event daily point caps (sum == Int(qteBonusCap) == 10).
    static let sparkPointsCap = 4
    static let cleanLogPointsCap = 3
    static let macroGuessPointsCap = 3
    /// The trailing player's QTE points are worth this much at per-duel aggregation.
    static let comebackMultiplier = 1.25
    /// A meal qualifies for the clean-log QTE below this toxin score (same threshold
    /// semantics as the "Clean Eating Streak" quest).
    static let cleanLogToxinThreshold = 10
    /// Spark ring: full charge sweep duration (s). Charge is a TRIANGLE WAVE of elapsed time.
    static let sparkSweepDuration = 1.8
    static let sparkPerfectZone = 75.0...95.0    // → sparkPerfectPoints
    static let sparkGoodZone = 50.0..<75.0       // → sparkGoodPoints
    static let sparkPerfectPoints = 4
    static let sparkGoodPoints = 2
    /// Clean-log marker: one full sweep (s); position is a TRIANGLE WAVE 0…1; hit zone = center.
    static let cleanLogSweepDuration = 1.2
    static let cleanLogHitZone = 0.40...0.60
    static let cleanLogHitPoints = 1
    /// Macro-guess: points for a correct answer; decoy = true protein × factor, min absolute gap.
    static let macroGuessPoints = 3
    static let macroGuessDecoyFactor = 1.5
    static let macroGuessMinGapGrams = 5.0

    // MARK: - D2: matchmaking
    /// A queue ticket dies this long after enqueue (client-stamped expiresAt).
    static let queueTicketTTL: TimeInterval = 10 * 60
    /// Queue screen re-fetch cadence while presented.
    static let queuePollInterval: TimeInterval = 5
    /// RR search bands (± around my rr) and the elapsed-seconds thresholds at which
    /// each unlocks. Band i applies once elapsed >= queueBandSchedule[i]. The last band
    /// is effectively unbounded.
    static let queueBands = [100, 250, 500, 100_000]
    static let queueBandSchedule: [TimeInterval] = [0, 15, 30, 45]
    /// Max candidate tickets fetched per poll.
    static let queueCandidateLimit = 10

    /// The current RR search band for a given elapsed queue time: `queueBands[i]` for the
    /// highest index `i` with `elapsed >= queueBandSchedule[i]`. Single source of truth for
    /// both the search query (DataManager) and the sheet's "±band RR" flavor text.
    static func queueBand(forElapsed elapsed: TimeInterval) -> Int {
        var band = queueBands.first ?? 100
        for i in queueBandSchedule.indices where elapsed >= queueBandSchedule[i] {
            band = queueBands[i]
        }
        return band
    }

    // MARK: - D2.6: concurrent duel caps (client-enforced; rules cannot count docs).
    /// Max concurrent duels per league: 1-day → 2, 3-day → 2, 5-day → 1 (total max 5).
    /// "Concurrent" is defined per DataManager.duelSlotUsage (active, plus outgoing
    /// pending on starting paths). Unknown league falls back to 1 (defensive).
    static func maxConcurrentDuels(league: Int) -> Int {
        switch league { case 1: return 2; case 3: return 2; case 5: return 1; default: return 1 }
    }

    // MARK: - D3: global leaderboard
    /// Rows fetched per board.
    static let leaderboardPageSize = 50
}

/// A challengeable person — a friend, a guild-mate, or anyone in the public directory —
/// for the challenge picker.
///
/// `uid` is the sole identity key; `username`/`displayName` are display snapshots.
/// `source` drives the picker's Friends/Guild/Everyone sectioning (a person present in
/// more than one is deduped to the more specific source: friend > guild > directory).
/// `.directory` candidates carry an empty `displayName` (the public username index has no
/// display name) — `displayLabel` then falls back to `@username`.
struct DuelOpponentCandidate: Identifiable, Equatable {
    enum Source: Equatable { case friend, guild, directory }

    let uid: String
    let username: String
    let displayName: String
    let source: Source

    var id: String { uid }

    /// Best label for display: the display name, falling back to `@username`.
    var displayLabel: String {
        displayName.isEmpty ? "@\(username)" : displayName
    }
}

/// Data Transfer Object for a top-level `duels/{duelId}` document (D1a).
///
/// A duel is a shared object owned by neither participant (precedent: guilds), living
/// in the top-level `duels` collection. Membership/query key is `participantUids`
/// (`arrayContains`). Following the guild-DTO convention for shared top-level
/// collections, this is a plain Codable value type: `id` is the Firestore document ID
/// (set from `documentID` on read, never encoded into the body), and server timestamps
/// are written as `FieldValue.serverTimestamp()` by the service layer — NOT via a
/// `@ServerTimestamp` wrapper, because the create rule pins the document to an exact
/// field set and a wrapper would write extra keys (`acceptedAt`) on create.
///
/// Reserved fields (`winnerUid`/`resolvedAt`/`forfeitedBy`/`rematchOfDuelId`) are
/// optional and ABSENT in D1a documents — declared so the schema doesn't churn; only
/// D1b/D1c write them.
struct DuelDTO: Codable, Identifiable, Equatable {
    /// Firestore document ID (= duelId). Set from `snapshot.documentID` on read;
    /// never written into the body (absent from the create rule's field set).
    var id: String?

    /// Exactly `[challengerUid, opponentUid]` — canonically ordered (index 0 is
    /// always the challenger). The membership/query key.
    var participantUids: [String]
    var challengerUid: String
    var opponentUid: String

    // Identity snapshots (display-only; all logic keys on uids).
    var challengerUsername: String
    var challengerDisplayName: String
    var opponentUsername: String
    var opponentDisplayName: String

    /// League duration in days — one of `DuelConstants.leagues`.
    var league: Int

    /// `DuelStatus.rawValue`. Kept as a String so an unknown future status never
    /// fails decode; interpret via `statusEnum`.
    var status: String

    /// Server-written creation time. Optional so a just-created (still-pending
    /// sentinel) value decodes as nil rather than throwing.
    var createdAt: Date?

    /// Client-computed `createdAt + DuelConstants.responseWindow` — the challenge
    /// expiry cutoff (rules can't do timestamp arithmetic, so the client writes it).
    var respondBy: Date

    /// Set on accept (server time). Absent while pending.
    var acceptedAt: Date?
    /// Set on accept: `now + league * secondsPerDay`. Absent while pending.
    var endAt: Date?

    /// Total score per side (0 at create; own side accumulates in D1b). Bounds 0…league×110.
    var challengerScore: Double
    var opponentScore: Double

    // MARK: - D1b: per-day scores, timestamps, resolution & RR
    /// Per-duel-day scores (size ≤ league, each 0…110). Own side writes; Arena/D1c consumes.
    var challengerDayScores: [Double]?
    var opponentDayScores: [Double]?
    /// Server timestamp of each side's last score write.
    var challengerScoreUpdatedAt: Date?
    var opponentScoreUpdatedAt: Date?
    /// Winner uid (absent on draw); set at resolution.
    var winnerUid: String?
    var resolvedAt: Date?
    var forfeitedBy: String?
    /// Signed RR deltas — both written at resolution/forfeit.
    var challengerRRDelta: Int?
    var opponentRRDelta: Int?
    /// Own-side "RR applied once" flags (false→true; absent == false).
    var challengerRRApplied: Bool?
    var opponentRRApplied: Bool?

    // MARK: - Reserved (D1c) — absent until then.
    var rematchOfDuelId: String?

    // MARK: - D2: matchmaking
    /// True for matchmade (ranked-queue) duels; absent/false for direct challenges.
    /// Optional so legacy/challenge docs decode. NOT part of the challenge create rule's
    /// key set — the challenge write path stays byte-identical.
    var matchmade: Bool?

    // MARK: - Init (fresh pending challenge)

    /// Builds a new PENDING challenge DTO with scores 0 and no accept/resolve fields.
    /// `participantUids` is stamped canonically as `[challengerUid, opponentUid]`.
    init(
        challengerUid: String,
        opponentUid: String,
        challengerUsername: String,
        challengerDisplayName: String,
        opponentUsername: String,
        opponentDisplayName: String,
        league: Int,
        respondBy: Date,
        rematchOfDuelId: String? = nil
    ) {
        self.id = nil
        self.participantUids = [challengerUid, opponentUid]
        self.challengerUid = challengerUid
        self.opponentUid = opponentUid
        self.challengerUsername = challengerUsername
        self.challengerDisplayName = challengerDisplayName
        self.opponentUsername = opponentUsername
        self.opponentDisplayName = opponentDisplayName
        self.league = league
        self.status = DuelStatus.pending.rawValue
        self.createdAt = nil
        self.respondBy = respondBy
        self.acceptedAt = nil
        self.endAt = nil
        self.challengerScore = 0
        self.opponentScore = 0
        self.challengerDayScores = []
        self.opponentDayScores = []
        self.challengerScoreUpdatedAt = nil
        self.opponentScoreUpdatedAt = nil
        self.winnerUid = nil
        self.resolvedAt = nil
        self.forfeitedBy = nil
        self.challengerRRDelta = nil
        self.opponentRRDelta = nil
        self.challengerRRApplied = nil
        self.opponentRRApplied = nil
        self.rematchOfDuelId = rematchOfDuelId
        self.matchmade = nil
    }

    // MARK: - Convenience (client-side)

    /// The typed status, or nil for an unknown/future value.
    var statusEnum: DuelStatus? { DuelStatus(rawValue: status) }

    /// True for a matchmade (ranked-queue) duel; false for a direct challenge (D2).
    var isMatchmade: Bool { matchmade ?? false }

    /// The OTHER participant's uid relative to `myUid`.
    func opponentUid(of myUid: String) -> String {
        myUid == challengerUid ? opponentUid : challengerUid
    }

    /// True when `myUid` created this challenge.
    func isChallenger(_ myUid: String) -> Bool { myUid == challengerUid }

    /// True when this is a pending challenge awaiting `myUid`'s response.
    func isPendingOnMe(_ myUid: String) -> Bool {
        statusEnum == .pending && opponentUid == myUid
    }

    /// True when this pending challenge is past its respond-by cutoff (lazy expiry).
    var isExpiredNow: Bool {
        statusEnum == .pending && Date() > respondBy
    }

    /// The counterparty's display label relative to `myUid` (display name, else `@username`).
    func opponentLabel(of myUid: String) -> String {
        let name = isChallenger(myUid) ? opponentDisplayName : challengerDisplayName
        let handle = isChallenger(myUid) ? opponentUsername : challengerUsername
        return name.isEmpty ? "@\(handle)" : name
    }

    // MARK: - D1b accessors

    var resolvedChallengerDayScores: [Double] { challengerDayScores ?? [] }
    var resolvedOpponentDayScores: [Double] { opponentDayScores ?? [] }

    /// Own-side RR-applied flag (absent == false).
    func rrApplied(for myUid: String) -> Bool {
        (isChallenger(myUid) ? challengerRRApplied : opponentRRApplied) ?? false
    }
    /// My total score / my opponent's total score.
    func myScore(_ myUid: String) -> Double { isChallenger(myUid) ? challengerScore : opponentScore }
    func theirScore(_ myUid: String) -> Double { isChallenger(myUid) ? opponentScore : challengerScore }
    /// My signed RR delta (nil until resolved).
    func myRRDelta(_ myUid: String) -> Int? { isChallenger(myUid) ? challengerRRDelta : opponentRRDelta }
}

// MARK: - Deterministic duel resolution (cross-device stable — NEVER Swift hashValue)

enum DuelWinner: Equatable { case challenger, opponent, draw }

/// FNV-1a 64-bit hash — the ONLY hash allowed for duel seeding. Swift's
/// `hashValue`/`Hasher` is randomized per process launch and would make deltas
/// differ per device; never use it here.
enum DuelRNG {
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Deterministic `RandomNumberGenerator` seeded from a UInt64 (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

extension DuelDTO {
    /// Winner from FROZEN scores, compared as rounded 1-decimal ints (NEVER raw Double `==`).
    static func scoreWinner(challengerScore: Double, opponentScore: Double) -> DuelWinner {
        let c = Int((challengerScore * 10).rounded())
        let o = Int((opponentScore * 10).rounded())
        if c > o { return .challenger }
        if o > c { return .opponent }
        return .draw
    }

    /// Deterministic RR deltas for a score-resolved duel, scaled by `league` (D2.5). Fixed
    /// draw order: winner magnitude (winDelta) first, then loser magnitude (lossDelta).
    /// Draw = drawDelta both. Same duelId + league ⇒ identical deltas on every device.
    static func resolveDeltas(duelId: String, league: Int, winner: DuelWinner) -> (challenger: Int, opponent: Int) {
        if winner == .draw { return (DuelConstants.drawDelta(league: league), DuelConstants.drawDelta(league: league)) }
        var rng = SplitMix64(seed: DuelRNG.fnv1a64(duelId))
        let winMag = Int.random(in: DuelConstants.winDelta(league: league), using: &rng)
        let lossMag = Int.random(in: DuelConstants.lossDelta(league: league), using: &rng)
        return winner == .challenger ? (winMag, lossMag) : (lossMag, winMag)
    }

    /// Deterministic RR deltas for a forfeit, scaled by `league` (D2.5). The forfeiter's loss
    /// is the FIXED `forfeitLossDelta(league:)` (no roll); the ONLY seeded draw is the other
    /// side's unearned win magnitude (forfeitWinnerDelta). Each helper seeds its own
    /// SplitMix64 from duelId, so this single-draw structure is self-consistent and
    /// deterministic — same duelId + league ⇒ identical pair on every device.
    static func forfeitDeltas(duelId: String, league: Int, forfeiterIsChallenger: Bool) -> (challenger: Int, opponent: Int) {
        var rng = SplitMix64(seed: DuelRNG.fnv1a64(duelId))
        let lossMag = DuelConstants.forfeitLossDelta(league: league)
        let winMag = Int.random(in: DuelConstants.forfeitWinnerDelta(league: league), using: &rng)
        return forfeiterIsChallenger ? (lossMag, winMag) : (winMag, lossMag)
    }
}
