import SwiftUI

// MARK: - Main View

struct SavedFilesView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(RawCullViewModel.self) private var viewModel

    @State private var selectedCatalogID: SavedFiles.ID?
    @State private var selectedRecordID: FileRecord.ID?
    @State private var showResetAlert = false

    private var records: [FileRecord] {
        selectedCatalog?.filerecords ?? []
    }

    private var selectedCatalog: SavedFiles? {
        viewModel.cullingModel.savedFiles.first { $0.id == selectedCatalogID }
    }

    private var selectedRecord: FileRecord? {
        records.first { $0.id == selectedRecordID }
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
                ) {
                    showResetAlert = true
                }
                .disabled(viewModel.creatingthumbnails)
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .alert("Reset Saved Files", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                viewModel.clearAllCullingState()
                selectedCatalogID = nil
                selectedRecordID = nil
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
                        Button {
                            if selectedCatalogID != entry.id {
                                selectedRecordID = nil
                            }
                            selectedCatalogID = entry.id
                        } label: {
                            CatalogRow(
                                entry: entry,
                                isSelected: selectedCatalogID == entry.id,
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            entry.catalog?.lastPathComponent ?? "Unknown Catalog",
                        )
                        .accessibilityValue(RawCullAccessibilityPresentation.savedCatalogValue(
                            fileCount: entry.filerecords?.count ?? 0,
                            date: entry.dateStart,
                            isSelected: selectedCatalogID == entry.id,
                        ))
                        .accessibilityAddTraits(
                            selectedCatalogID == entry.id ? .isSelected : [],
                        )
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
                        Button {
                            selectedRecordID = record.id
                        } label: {
                            FileRecordRow(
                                record: record,
                                isSelected: selectedRecordID == record.id,
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(record.fileName ?? "Unnamed File")
                        .accessibilityValue(RawCullAccessibilityPresentation.savedRecordValue(
                            rating: record.rating,
                            dateTagged: record.dateTagged,
                            isSelected: selectedRecordID == record.id,
                        ))
                        .accessibilityAddTraits(
                            selectedRecordID == record.id ? .isSelected : [],
                        )
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
