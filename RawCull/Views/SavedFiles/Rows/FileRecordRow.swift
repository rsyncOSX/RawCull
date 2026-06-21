import SwiftUI

struct FileRecordRow: View {
    let record: FileRecord
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.separatorColor).opacity(0.3))
                    .frame(width: 36, height: 36)
                Image(systemName: fileIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.fileName ?? "Unnamed File")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                if let dateTagged = record.dateTagged {
                    Label(dateTagged, systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if let rating = record.rating {
                StarRatingView(rating: rating, compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Group {
                if isSelected {
                    Color.accentColor.opacity(0.08)
                } else if isHovered {
                    Color(NSColor.selectedContentBackgroundColor).opacity(0.06)
                } else {
                    Color.clear
                }
            },
        )
        .contentShape(Rectangle())
    }

    private var fileIcon: String {
        "photo"
    }
}
