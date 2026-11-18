#if DEBUG
import SwiftUI

struct AIAssessmentsWindow: View {
    let navigation: AIAssessmentNavigation
    let viewModel: RawCullViewModel
    let photoAccess: (AnalysisJobStore.FollowUpRequest) throws -> RawCullCatalogGrant

    @State private var entries: [AIAssessmentEntry] = []
    @State private var selection: UUID?
    @State private var presentedID: UUID?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var access: RawCullCatalogGrant?
    @State private var accessJobID: UUID?
    @State private var accessRetryID = UUID()

    private struct AccessRequest: Equatable {
        let sourceJobID: UUID?
        let retryID: UUID
    }

    var body: some View {
        ZStack {
            AIAssessmentList(
                entries: entries, selection: $selection, isLoading: isLoading, loadFailed: loadFailed,
                access: currentAccess, open: open,
            )
            .opacity(presentedID == nil ? 1 : 0)
            .allowsHitTesting(presentedID == nil)
            .disabled(presentedID != nil)
            .accessibilityHidden(presentedID != nil)

            if let presentedID {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            self.presentedID = nil
                        } label: {
                            Label("AI Assessments", systemImage: "chevron.left")
                        }
                        Spacer()
                        if let next = nextEntry(after: presentedID) {
                            Button("Next assessment") { open(next.id) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    Divider()

                    if currentAccess == nil, accessJobID != nil {
                        HStack {
                            Text("Catalog access failed. Restore access to the original catalog, then retry.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry Catalog Access") {
                                accessJobID = nil
                                accessRetryID = UUID()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }

                    if let entry = entries.first(where: { $0.id == presentedID }) {
                        AIAssessmentComparison(
                            entry: entry, viewModel: viewModel, access: currentAccess,
                            accessChecked: accessJobID == entry.request.sourceJobID,
                        )
                        .id(entry.id)
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Assessment unavailable", systemImage: "photo.badge.exclamationmark",
                            description: Text("The saved result expired or is no longer shared."),
                        )
                    }
                }
                .background(.windowBackground)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .onChange(of: navigation.destination, initial: true) {
            guard let destination = navigation.destination else { return }
            navigation.destination = nil
            switch destination {
            case .list: presentedID = nil
            case let .result(id): open(id)
            }
        }
        .task { await observeResults() }
        .task(id: AccessRequest(sourceJobID: entries.first?.request.sourceJobID, retryID: accessRetryID)) {
            access = nil
            accessJobID = nil
            guard let request = entries.first?.request else { return }
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !Task.isCancelled {
                do {
                    access = try photoAccess(request)
                } catch AnalysisJobStore.StoreError.busy {
                    if ContinuousClock.now < deadline {
                        do {
                            try await Task.sleep(for: .milliseconds(150))
                        } catch {
                            return
                        }
                        continue
                    }
                } catch {
                    access = nil
                }
                accessJobID = request.sourceJobID
                return
            }
        }
    }

    private var currentAccess: RawCullCatalogGrant? {
        guard accessJobID == entries.first?.request.sourceJobID else { return nil }
        return access
    }

    private func open(_ id: UUID) {
        selection = id
        presentedID = id
    }

    private func nextEntry(after id: UUID) -> AIAssessmentEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.dropFirst(index + 1).first
    }

    private func observeResults() async {
        while !Task.isCancelled {
            do {
                let latest = try await AIAssessmentEntry.available()
                guard !Task.isCancelled else { return }
                if latest != entries { entries = latest }
                isLoading = false
                loadFailed = false
            } catch AnalysisJobStore.StoreError.busy {
                // The writer still owns the store. Retry without changing selection.
            } catch FollowUpSourceSnapshot.SourceError.unavailable {
                entries = []
                isLoading = false
                loadFailed = false
            } catch {
                entries = []
                isLoading = false
                loadFailed = true
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

private struct AIAssessmentList: View {
    let entries: [AIAssessmentEntry]
    @Binding var selection: UUID?
    let isLoading: Bool
    let loadFailed: Bool
    let access: RawCullCatalogGrant?
    let open: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Assessments")
                .font(.largeTitle.bold())
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                if loadFailed {
                    ContentUnavailableView("Couldn’t load assessments", systemImage: "exclamationmark.triangle")
                } else {
                    ContentUnavailableView(
                        "No burst assessments", systemImage: "photo.stack",
                        description: Text("Completed MCP burst assessments appear here while their results are shared."),
                    )
                }
            } else {
                List(entries, selection: $selection) { entry in
                    AIAssessmentRow(entry: entry, access: access, open: open)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct AIAssessmentRow: View {
    let entry: AIAssessmentEntry
    let access: RawCullCatalogGrant?
    let open: (UUID) -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let frame = entry.frames.first(where: { $0.id == (entry.recommendation ?? entry.alternate) }) {
                AIAssessmentThumbnail(frame: frame, access: access)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let number = entry.burstNumber {
                    Text("Burst \(number)").font(.headline)
                } else {
                    Text("Burst assessment").font(.headline)
                }
                HStack {
                    if let catalog = entry.catalogName { Text(verbatim: catalog) }
                    Text(entry.requestedAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let confidence = entry.burstConfidence {
                    Text(assessmentConfidence(confidence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(entry.result.assessedCount) of \(entry.frames.count) frames assessed")
                    .monospacedDigit()
                if entry.result.failedCount > 0 {
                    Text("\(entry.result.failedCount) failed")
                        .foregroundStyle(.secondary)
                }
                Button("View assessment") { open(entry.id) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(entry.id) }
    }
}

func assessmentConfidence(_ confidence: String) -> LocalizedStringResource {
    switch confidence {
    case "high": "High confidence"
    case "medium": "Review recommended"
    case "low": "Low confidence"
    default: "Confidence unavailable"
    }
}
#endif
