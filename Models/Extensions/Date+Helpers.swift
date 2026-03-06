//
//  Date+Helpers.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Date utilities for streak calculation and daily tracking
extension Date {
    /// Checks if this date is today
    /// - Returns: True if the date falls on the current calendar day
    func isToday() -> Bool {
        return Calendar.current.isDateInToday(self)
    }

    /// Checks if this date is yesterday
    /// - Returns: True if the date falls on yesterday's calendar day
    func isYesterday() -> Bool {
        return Calendar.current.isDateInYesterday(self)
    }

    /// Calculates the number of days between this date and another date
    /// - Parameter other: The date to compare against
    /// - Returns: Number of days between the two dates (absolute value)
    func daysBetween(_ other: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: self, to: other)
        return abs(components.day ?? 0)
    }

    /// Returns the start of the day (midnight) for this date
    /// Useful for comparing dates without time components
    var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }

    /// Checks if this date is the same calendar day as another date
    /// - Parameter other: The date to compare against
    /// - Returns: True if both dates fall on the same calendar day
    func isSameDay(as other: Date) -> Bool {
        return Calendar.current.isDate(self, inSameDayAs: other)
    }
}
