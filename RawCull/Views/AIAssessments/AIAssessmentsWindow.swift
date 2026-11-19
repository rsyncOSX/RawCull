import SwiftUI
import RawCullCore

struct AIAssessmentsWindow: View {
    let navigation: AIAssessmentNavigation
    let viewModel: RawCullViewModel
    let photoAccess: (AnalysisJobStore.FollowUpRequest) throws -> RawCullCatalogGrant

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var entries: [AIAssessmentEntry] = []
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
        VStack(spacing: 0) {
            HStack {
                Button(action: returnToBursts) {
                    Label("Burst list", systemImage: "chevron.left")
                }
                Spacer()
                Button("Next Assessment", systemImage: "chevron.right") {
                    if let presentedID { advance(after: presentedID) }
                }
                .disabled(nextAssessmentID == nil)
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
                catalogContext(for: entry)
                AIAssessmentComparison(
                    entry: entry, viewModel: viewModel, access: currentAccess,
                    accessChecked: accessJobID == entry.request.sourceJobID,
                    onMarkedReviewed: { advance(after: entry.id) },
                )
                .id(entry.id)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Assessment unavailable", systemImage: "photo.badge.exclamationmark",
                    description: Text(loadFailed
                        ? "Couldn’t load the saved assessment. Return to the burst list and try again."
                        : "The saved result expired or is no longer shared. Return to the burst list to choose a burst."),
                )
            }
        }
        .background(.windowBackground)
        .frame(minWidth: 620, minHeight: 520)
        .onChange(of: navigation.destination, initial: true) {
            guard let destination = navigation.destination else { return }
            navigation.destination = nil
            switch destination {
            case let .result(id): open(id)
            }
        }
        .task { await observeResults() }
        .task(id: currentAccess?.url) {
            guard let access = currentAccess,
                  viewModel.selectedSource?.url.standardizedFileURL == access.url.standardizedFileURL else { return }
            if await viewModel.cullingModel.ensureLoaded() {
                viewModel.rebuildRatingCache()
                viewModel.loadPersistedScoringandSaliency()
            }
        }
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

    @ViewBuilder
    private func catalogContext(for entry: AIAssessmentEntry) -> some View {
        if let access = currentAccess {
            if viewModel.selectedSource?.url.standardizedFileURL != access.url.standardizedFileURL {
                HStack {
                    Text("Open the source catalog to load ratings, subject badges, and tagging controls.")
                    Spacer()
                    Button("Open source catalog") {
                        openSourceCatalog(for: entry, access: access)
                    }
                    .disabled(viewModel.scanning || viewModel.isPreparingBurstCatalog || viewModel.isDeepAIReviewBlockedByOtherWork)
                }
                .padding(12)
            } else if viewModel.scanning || viewModel.cullingModel.loadState != .ready {
                HStack {
                    if viewModel.cullingModel.loadState == .failed {
                        Text("Saved ratings couldn’t be loaded.")
                        Button("Retry loading ratings") { Task { await viewModel.retryCullingPersistence() } }
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Preparing catalog ratings and badges…")
                    }
                }
                .padding(12)
            } else if !sourceFilesMatch(entry, catalog: access.url) {
                HStack {
                    Text("The open catalog’s photos do not match this saved assessment. Reload the catalog to check for changes.")
                    Spacer()
                    Button("Reload source catalog") { openSourceCatalog(for: entry, access: access) }
                        .disabled(viewModel.isPreparingBurstCatalog || viewModel.isDeepAIReviewBlockedByOtherWork)
                }
                .padding(12)
            }
        }
    }

    private func sourceFilesMatch(_ entry: AIAssessmentEntry, catalog: URL) -> Bool {
        let urls = Set(entry.frames.map { catalog.appendingPathComponent($0.source.relativePath).standardizedFileURL })
        return entry.matches(files: viewModel.files.filter { urls.contains($0.url.standardizedFileURL) }, catalog: catalog)
    }

    private func openSourceCatalog(for entry: AIAssessmentEntry, access: RawCullCatalogGrant) {
        let source = viewModel.sources.first { $0.url.standardizedFileURL == access.url.standardizedFileURL }
            ?? ARWSourceCatalog(name: entry.catalogName ?? access.url.lastPathComponent, url: access.url)
        if !viewModel.sources.contains(where: { $0.url.standardizedFileURL == access.url.standardizedFileURL }) {
            viewModel.sources.append(source)
        }
        viewModel.selectedSource = source
        viewModel.startCatalogLoad(for: source, scopedURL: access.url, retainedAccess: access)
    }

    private var currentAccess: RawCullCatalogGrant? {
        guard accessJobID == entries.first?.request.sourceJobID else { return nil }
        return access
    }

    private func open(_ id: UUID) {
        presentedID = id
    }

    private var nextAssessmentID: UUID? {
        guard let index = entries.firstIndex(where: { $0.id == presentedID }) else { return nil }
        return entries.dropFirst(index + 1).first?.id
    }

    private func advance(after id: UUID) {
        guard presentedID == id, let nextAssessmentID else { return }
        open(nextAssessmentID)
    }

    private func returnToBursts() {
        viewModel.returnToActiveBurstGroupView()
        openWindow(id: "main-window")
        dismissWindow(id: AIAssessmentNavigation.windowID)
    }

    private func observeResults() async {
        while !Task.isCancelled {
            do {
                let latest = try await AIAssessmentEntry.available()
                guard !Task.isCancelled else { return }
                if latest != entries { entries = latest }
                if latest != navigation.entries { navigation.entries = latest }
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

func assessmentConfidence(_ confidence: String) -> LocalizedStringResource {
    switch confidence {
    case "high": "High confidence"
    case "medium": "Review recommended"
    case "low": "Low confidence"
    default: "Confidence unavailable"
    }
}
