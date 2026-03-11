import SwiftUI

// MARK: - Main View

struct SavedFilesView: View {
    @Environment(\.dismiss) var dismiss

    @State private var savedFiles: [SavedFiles] = []
    @State private var selectedCatalog: SavedFiles?
    @State private var selectedRecord: FileRecord?
    @State private var hoveredCatalog: UUID?
    @State private var hoveredRecord: UUID?

    private var records: [FileRecord] {
        selectedCatalog?.filerecords ?? []
    }

    var body: some View {
        NavigationSplitView {
            // Column 1: Catalogs
            catalogList
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            // Column 2: File Records
            fileRecordsList
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            Group {
                if let record = selectedRecord {
                    FileRecordDetailView(record: record)
                } else {
                    placeholderDetail
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .task {
            savedFiles = ReadSavedFilesJSON().readjsonfilesavedfiles() ?? []
        }
    }

    // MARK: - Column 1: Catalog List

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if savedFiles.isEmpty {
                    emptyCatalogs
                } else {
                    ForEach(savedFiles) { entry in
                        CatalogRow(
                            entry: entry,
                            isSelected: selectedCatalog?.id == entry.id,
                            isHovered: hoveredCatalog == entry.id,
                        )
                        .onTapGesture {
                            if selectedCatalog?.id != entry.id {
                                selectedRecord = nil
                            }
                            selectedCatalog = entry
                        }
                        .onHover { hovering in
                            hoveredCatalog = hovering ? entry.id : nil
                        }
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.top, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle("Catalogs")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(savedFiles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(NSColor.separatorColor).opacity(0.5)))
            }
        }
    }

    private var emptyCatalogs: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No catalogs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Column 2: File Records List

    private var fileRecordsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if selectedCatalog == nil {
                    placeholderRecords
                } else if records.isEmpty {
                    emptyRecords
                } else {
                    ForEach(records) { record in
                        FileRecordRow(
                            record: record,
                            isSelected: selectedRecord?.id == record.id,
                            isHovered: hoveredRecord == record.id,
                        )
                        .onTapGesture { selectedRecord = record }
                        .onHover { hovering in
                            hoveredRecord = hovering ? record.id : nil
                        }
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.top, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .navigationTitle(selectedCatalog.map { $0.catalog?.lastPathComponent ?? "Files" } ?? "Files")
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Text("\(records.count) file\(records.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(NSColor.separatorColor).opacity(0.5)))
                }
            }
        }
    }

    private var placeholderRecords: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a catalog")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyRecords: some View {
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

    // MARK: - Column 3: Placeholder

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
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Catalog Row

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

// MARK: - File Record Row

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
                }
            }

            Spacer()

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
            },
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
                detailHeader
                    .padding(.bottom, 24)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "File Details")

                    DetailRow(icon: "doc.text", label: "File Name", value: record.fileName ?? "—")
                    Divider()
                    DetailRow(icon: "tag.fill", label: "Date Tagged", value: record.dateTagged ?? "—")
                    Divider()
                    DetailRow(icon: "arrow.right.doc.on.clipboard", label: "Date Copied", value: record.dateCopied ?? "—")
                    Divider()

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
                        .fill(Color(NSColor.controlBackgroundColor)),
                )
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
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

// MARK: - FileRecord convenience init for preview

extension FileRecord {
    init(fileName: String?, dateTagged: String?, dateCopied: String?, rating: Int?) {
        self.fileName = fileName
        self.dateTagged = dateTagged
        self.dateCopied = dateCopied
        self.rating = rating
    }
}
