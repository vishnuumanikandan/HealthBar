//
//  FoodClarification.swift
//  HealthBar
//
//  Created by Claude on 5/29/26.
//

import Foundation

struct FoodClarificationOption: Identifiable, Equatable {
    let id: UUID
    let label: String
    let deltaCalories: Int
    let deltaProtein: Double
    let deltaCarbs: Double
    let deltaFat: Double
}

struct FoodClarification: Identifiable, Equatable {
    let id: UUID
    let affectsItemId: UUID
    let question: String
    let importance: Double
    let options: [FoodClarificationOption]
    var selectedOptionID: UUID
}

// MARK: - Recompute Helper

func recomputedMacros(
    forBaseline baseline: (cal: Int, p: Double, c: Double, f: Double),
    clarifications: [FoodClarification]
) -> (cal: Int, p: Double, c: Double, f: Double) {
    var calDelta = 0
    var pDelta = 0.0
    var cDelta = 0.0
    var fDelta = 0.0

    for clarification in clarifications {
        let selected = clarification.options.first(where: { $0.id == clarification.selectedOptionID })
            ?? clarification.options.first(where: {
                $0.deltaCalories == 0 && $0.deltaProtein == 0 && $0.deltaCarbs == 0 && $0.deltaFat == 0
            })
            ?? clarification.options.first

        guard let option = selected else { continue }

        calDelta += option.deltaCalories
        pDelta += option.deltaProtein
        cDelta += option.deltaCarbs
        fDelta += option.deltaFat
    }

    var cal = baseline.cal + calDelta
    var p = baseline.p + pDelta
    var c = baseline.c + cDelta
    var f = baseline.f + fDelta

    cal = min(max(cal, 0), 5000)
    p = min(max(p, 0), 1000)
    c = min(max(c, 0), 1000)
    f = min(max(f, 0), 1000)

    // Atwater reconcile: P·4 + C·4 + F·9
    let derived = Int(round(p * 4 + c * 4 + f * 9))
    if cal == 0 && derived > 0 {
        cal = derived
    } else if derived > 0 {
        let deviation = abs(Double(cal) - Double(derived)) / Double(max(derived, 1))
        if deviation > 0.35 {
            cal = derived
        }
    }

    cal = min(max(cal, 0), 5000)

    return (cal, p, c, f)
}
