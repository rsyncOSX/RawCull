import Foundation

enum RawCullAccessibilityPresentation {
    static func savedCatalogValue(
        fileCount: Int,
        date: String?,
        isSelected: Bool,
    ) -> String {
        var values = [count(fileCount, singular: "file")]
        if let date, !date.isEmpty {
            values.append(date)
        }
        values.append(isSelected ? "Selected" : "Not selected")
        return values.joined(separator: ", ")
    }

    static func savedRecordValue(
        rating: Int?,
        dateTagged: String?,
        isSelected: Bool,
    ) -> String {
        var values = [ratingDescription(rating)]
        if let dateTagged, !dateTagged.isEmpty {
            values.append("Tagged \(dateTagged)")
        }
        values.append(isSelected ? "Selected" : "Not selected")
        return values.joined(separator: ", ")
    }

    static func imageValue(
        rating: RatingDisplay,
        isSelected: Bool,
        isMultiSelected: Bool,
    ) -> String {
        var values = [rating.help]
        if isSelected {
            values.append("Primary selection")
        } else if isMultiSelected {
            values.append("Included in selection")
        } else {
            values.append("Not selected")
        }
        return values.joined(separator: ", ")
    }

    private static func ratingDescription(_ rating: Int?) -> String {
        guard let rating else { return "Unrated" }
        return RatingDisplay(rating: rating).help
    }

    private static func count(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}
