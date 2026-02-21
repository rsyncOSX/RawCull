//
//  extension+String+Date.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

import Foundation

extension String {
    func en_date_from_string() -> Date {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "dd MMM yyyy HH:mm"
        return dateformatter.date(from: self) ?? Date()
    }

    func validate_en_date_from_string() -> Date? {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "dd MMM yyyy HH:mm"
        return dateformatter.date(from: self)
    }

    func localized_date_from_string() -> Date {
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        return dateformatter.date(from: self) ?? Date()
    }
}

extension Date {
    func localized_string_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        return dateformatter.string(from: self)
    }

    func long_localized_string_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .long
        return dateformatter.string(from: self)
    }

    func en_string_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "dd MMM yyyy HH:mm"
        return dateformatter.string(from: self)
    }

    func en_string_month_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "dd MMM yyyy"
        return dateformatter.string(from: self)
    }

    func en_string_hour_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "HH:mm"
        return dateformatter.string(from: self)
    }

    func shortlocalized_string_from_date() -> String {
        // MM-dd-yyyy HH:mm
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "MM-dd-yyyy:HH:mm"
        return dateformatter.string(from: self)
    }

    func localized_weekday_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "EEEE"
        return dateformatter.string(from: self)
    }

    func localized_month_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.formatterBehavior = .behavior10_4
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "MMMM"
        return dateformatter.string(from: self)
    }

    static let firstDayOfWeek = Calendar.current.firstWeekday

    static var capitalizedFirstLettersOfWeekdays: [String] {
        let calendar = Calendar.current
        // Adjusted for the different weekday starts
        var weekdays = calendar.shortWeekdaySymbols
        if firstDayOfWeek > 1 {
            for _ in 1 ..< firstDayOfWeek {
                if let first = weekdays.first {
                    weekdays.append(first)
                    weekdays.removeFirst()
                }
            }
        }
        return weekdays.map(\.capitalized)
    }

    static var fullMonthNames: [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current

        return (1 ... 12).compactMap { month in
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMM")
            let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: 1))
            return date.map { dateFormatter.string(from: $0) }
        }
    }

    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    var endOfCurrentMonth: Date {
        guard let interval = Calendar.current.dateInterval(of: .month, for: self),
              let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
        else {
            return self
        }
        return lastDay
    }

    var endOfNextMonth: Date? {
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: self),
              let interval = Calendar.current.dateInterval(of: .month, for: nextMonth),
              let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
        else {
            return nil
        }
        return lastDay
    }

    var numberOfDaysInMonth: Int {
        Calendar.current.component(.day, from: endOfCurrentMonth)
    }

    // Fix: negative days causing issue for first row
    var firstWeekDayBeforeStart: Date {
        let startOfMonthWeekday = Calendar.current.component(.weekday, from: startOfMonth)
        var numberFromPreviousMonth = startOfMonthWeekday - Self.firstDayOfWeek
        if numberFromPreviousMonth < 0 {
            numberFromPreviousMonth += 7 // Adjust to a 0-6 range if negative
        }
        guard let adjusted = Calendar.current.date(byAdding: .day, value: -numberFromPreviousMonth, to: startOfMonth) else {
            return startOfMonth
        }
        return adjusted
    }

    var calendarDisplayDays: [Date] {
        var days: [Date] = []
        // Start with days from the previous month to fill the grid
        let firstDisplayDay = firstWeekDayBeforeStart
        var day = firstDisplayDay
        while day < startOfMonth {
            days.append(day)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        // Add days of the current month
        for dayOffset in 0 ..< numberOfDaysInMonth {
            let newDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: startOfMonth)
            if let newDay {
                days.append(newDay)
            }
        }
        return days
    }

    var yearInt: Int {
        Calendar.current.component(.year, from: self)
    }

    var monthInt: Int {
        Calendar.current.component(.month, from: self)
    }

    var dayInt: Int {
        Calendar.current.component(.day, from: self)
    }

    var hourInt: Int {
        Calendar.current.component(.hour, from: self)
    }

    var minuteInt: Int {
        Calendar.current.component(.minute, from: self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
