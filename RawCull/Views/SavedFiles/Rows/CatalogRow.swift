import SwiftUI

struct CatalogRow: View {
    let entry: SavedFiles
    let isSelected: Bool
    let isHovered: Bool

    private var catalogName: String {
        entry.catalog?.lastPathComponent ?? "Unknown Catalog"
    }

    private var fileCount: Int {
        entry.filerecords?.count ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.separatorColor).opacity(0.25))
                    .frame(width: 32, height: 32)
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(catalogName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                if let dateStart = entry.dateStart, !dateStart.isEmpty {
                    Text(dateStart)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(fileCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(NSColor.separatorColor).opacity(0.4)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
}
