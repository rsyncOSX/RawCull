//
//  extension+String+Date.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

import Foundation

extension Date {
    func en_string_from_date() -> String {
        let dateformatter = DateFormatter()
        dateformatter.locale = Locale(identifier: "en")
        dateformatter.dateStyle = .medium
        dateformatter.timeStyle = .short
        dateformatter.dateFormat = "dd MMM yyyy HH:mm"
        return dateformatter.string(from: self)
    }
}
