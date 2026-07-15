//
//  ProfanityFilter.swift
//  HealthBar
//
//  Created by Claude on 7/15/26.
//
//  UGC-1a — client-side name filtering (User Safety Data Core).
//
//  A caseless enum (no instances) that matches user-supplied text against a
//  bundled denylist after aggressive normalization, so leetspeak and separator
//  evasions collapse onto their base form before the scan. This is enforcement
//  at the username chokepoint and the guild name/description chokepoint; rules
//  cannot do wordlist matching, so this is the honest architecture (D7) —
//  filter at entry, plus the report path and block path as backstops.
//

import Foundation

enum ProfanityFilter {

    /// Leetspeak substitution map (D8, exact): applied character-by-character
    /// during normalization so `sh1t`/`@$$` fold onto their base letters.
    static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
        "7": "t", "8": "b", "@": "a", "$": "s", "!": "i"
    ]

    /// Normalize per D8, one pass:
    /// lowercase → Unicode-fold (diacritic/width-insensitive) → leetspeak map →
    /// strip every character outside `a–z`. The result is a dense lowercase-Latin
    /// string with all separators and decorations removed.
    static func normalize(_ text: String) -> String {
        let folded = text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        result.reserveCapacity(folded.count)
        for ch in folded {
            let mapped = leetMap[ch] ?? ch
            if ("a"..."z").contains(mapped) {
                result.append(mapped)
            }
        }
        return result
    }

    /// Substring-scan the already-normalized string against a term set (D8).
    /// An empty input never matches.
    static func matches(_ normalized: String, against terms: Set<String>) -> Bool {
        guard !normalized.isEmpty else { return false }
        for term in terms where normalized.contains(term) {
            return true
        }
        return false
    }

    /// True when `text` normalizes to contain any denylisted term.
    static func containsBlockedTerm(_ text: String) -> Bool {
        matches(normalize(text), against: denylist)
    }

    /// The bundled denylist, loaded ONCE into a static Set (lazy on first use).
    /// D10: on a missing/unreadable resource, assert in debug and fail OPEN in
    /// release (empty set → all input treated as clean) — never brick username
    /// claims in production over a bundling defect.
    static let denylist: Set<String> = loadDenylist()

    private static func loadDenylist() -> Set<String> {
        guard let url = Bundle.main.url(forResource: "ProfanityDenylist", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("ProfanityDenylist.txt missing or unreadable — name filtering disabled (failing open).")
            return []
        }
        // D9 authoring rules: one lowercase term per line; `#` comments and blank
        // lines ignored. Entries are matched as substrings of the normalized input,
        // so each is normalized here too (defensive — the file is authored clean).
        var terms = Set<String>()
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let normalized = normalize(trimmed)
            if !normalized.isEmpty { terms.insert(normalized) }
        }
        return terms
    }
}
