import SwiftUI

// MARK: - Main View

struct SavedFilesView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(RawCullViewModel.self) private var viewModel

    @State private var selectedCatalog: SavedFiles?
    @State private var selectedRecord: FileRecord?
    @State private var hoveredCatalog: UUID?
    @State private var hoveredRecord: UUID?
    @State private var showResetAlert = false

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
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                ConditionalGlassButton(
                    systemImage: "trash",
                    text: "Reset",
                    helpText: "Clean up data from previous saves",
                    style: .softCapsule,
                ) {
                    showResetAlert = true
                }
                .disabled(viewModel.creatingthumbnails)
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .alert("Reset Saved Files", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                viewModel.cullingModel.resetAllSavedFiles()
                selectedCatalog = nil
                selectedRecord = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reset all saved files?")
        }
    }

    // MARK: - Column 1: Catalog List

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.cullingModel.savedFiles.isEmpty {
                    emptyCatalogs
                } else {
                    ForEach(viewModel.cullingModel.savedFiles) { entry in
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
                Text("\(viewModel.cullingModel.savedFiles.count)")
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
            Text("No Catalogs")
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
            Text("No Files")
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
    }
}
