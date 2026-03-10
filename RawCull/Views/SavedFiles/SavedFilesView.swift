import SwiftUI

// MARK: - Main View

struct SavedFilesView: View {
    let savedFiles: SavedFiles

    @State private var selectedRecord: FileRecord?
    @State private var hoveredRecord: UUID?

    private var catalogName: String {
        savedFiles.catalog?.lastPathComponent ?? "Unknown Catalog"
    }

    private var catalogPath: String {
        savedFiles.catalog?.path ?? "—"
    }

    private var formattedDate: String {
        savedFiles.dateStart ?? "No date"
    }

    private var records: [FileRecord] {
        savedFiles.filerecords ?? []
    }

    var body: some View {
        HSplitView {
            // Left panel: file records list
            VStack(spacing: 0) {
                listHeader
                Divider()
                fileRecordsList
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)

            // Right panel: detail view
            detailPanel
                .frame(minWidth: 300, idealWidth: 420)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left Panel

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalogName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(catalogPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 16) {
                Label(formattedDate, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(records.count) file\(records.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(NSColor.separatorColor).opacity(0.4))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var fileRecordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if records.isEmpty {
                    emptyState
                } else {
                    ForEach(records) { record in
                        FileRecordRow(
                            record: record,
                            isSelected: selectedRecord?.id == record.id,
                            isHovered: hoveredRecord == record.id
                        )
                        .onTapGesture { selectedRecord = record }
                        .onHover { hovering in
                            hoveredRecord = hovering ? record.id : nil
                        }
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No file records")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Right Panel

    private var detailPanel: some View {
        Group {
            if let record = selectedRecord {
                FileRecordDetailView(record: record)
            } else {
                placeholderDetail
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Select a file to view details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Record Row

struct FileRecordRow: View {
    let record: FileRecord
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.separatorColor).opacity(0.3))
                    .frame(width: 36, height: 36)
                Image(systemName: fileIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            // File info
            VStack(alignment: .leading, spacing: 3) {
                Text(record.fileName ?? "Unnamed File")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                HStack(spacing: 8) {
                    if let dateTagged = record.dateTagged {
                        Label(dateTagged, systemImage: "tag")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Rating stars
            if let rating = record.rating {
                StarRatingView(rating: rating, compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Group {
                if isSelected {
                    Color.accentColor.opacity(0.08)
                } else if isHovered {
                    Color(NSColor.selectedContentBackgroundColor).opacity(0.06)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
    }

    private var fileIcon: String {
        guard let name = record.fileName?.lowercased() else { return "doc" }
        if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") || name.hasSuffix(".heic") || name.hasSuffix(".tiff") {
            return "photo"
        } else if name.hasSuffix(".mp4") || name.hasSuffix(".mov") || name.hasSuffix(".avi") {
            return "video"
        } else if name.hasSuffix(".mp3") || name.hasSuffix(".wav") || name.hasSuffix(".aiff") {
            return "waveform"
        } else if name.hasSuffix(".pdf") {
            return "doc.richtext"
        }
        return "doc"
    }
}

// MARK: - Detail View

struct FileRecordDetailView: View {
    let record: FileRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero header
                detailHeader
                    .padding(.bottom, 24)

                // Info grid
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "File Details")

                    DetailRow(icon: "doc.text", label: "File Name", value: record.fileName ?? "—")
                    Divider()
                    DetailRow(icon: "tag.fill", label: "Date Tagged", value: record.dateTagged ?? "—")
                    Divider()
                    DetailRow(icon: "arrow.right.doc.on.clipboard", label: "Date Copied", value: record.dateCopied ?? "—")
                    Divider()

                    // Rating row
                    HStack(alignment: .center) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        if let rating = record.rating {
                            StarRatingView(rating: rating, compact: false)
                            Text("(\(rating)/5)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4)
                        } else {
                            Text("—")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                Spacer()
            }
            .padding(24)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.fileName ?? "Unnamed File")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if let dateTagged = record.dateTagged {
                    Text("Tagged \(dateTagged)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(1.0)
            .padding(.bottom, 4)
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct StarRatingView: View {
    let rating: Int
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(1 ... 5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: compact ? 10 : 14))
                    .foregroundStyle(star <= rating ? Color.yellow : Color(NSColor.separatorColor))
            }
        }
    }
}

// MARK: - FileRecord convenience init for preview/construction

extension FileRecord {
    init(fileName: String?, dateTagged: String?, dateCopied: String?, rating: Int?) {
        self.fileName = fileName
        self.dateTagged = dateTagged
        self.dateCopied = dateCopied
        self.rating = rating
    }
}
