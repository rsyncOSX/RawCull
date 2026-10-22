import AppKit
import RawCullCore
import SwiftUI

struct ComparisonGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var showCandidateInspector: Bool

    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session: ComparisonSessionModel
    @State private var keyMonitor = ReviewKeyMonitor()
    @FocusState private var isFocused: Bool

    init(
        viewModel: RawCullViewModel,
        showCandidateInspector: Binding<Bool>,
        imageService: (any ComparisonSessionImageServing)? = nil,
    ) {
        self.viewModel = viewModel
        _showCandidateInspector = showCandidateInspector
        _session = State(
            initialValue: ComparisonSessionModel(
                imageService: imageService ?? LiveComparisonSessionImageService(viewModel: viewModel),
                selection: viewModel,
            ))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            if files.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    if burstComparisonResult != nil {
                        BurstComparisonEvidenceView(
                            inspectorIsPresented: showCandidateInspector,
                            onBack: viewModel.returnToActiveBurstGroupView,
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }

                    ComparisonPager(files: files, selectedFileID: viewModel.selectedFileID, select: session.select) { file in
                        ComparisonPane(
                            viewModel: viewModel, session: session, presentation: presentation,
                            file: file, isSelected: viewModel.selectedFileID == file.id,
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select Images to Compare",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Select two to four thumbnails in a grid view, then use Compare."),
                )
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .background(ReviewKeyboardScopeReader(scope: keyboardScope))
        .onAppear {
            session.activate()
            isFocused = true
            installKeyMonitor()
            selectFirstComparisonFileIfNeeded()
        }
        .onDisappear {
            session.cancel()
            removeKeyMonitor()
        }
        .task(id: loadKey) {
            selectFirstComparisonFileIfNeeded()
            await session.loadImages(files: files)
        }
        .onChange(of: viewModel.comparisonFileIDs) { _, _ in
            session.resetDisplayScope()
            selectFirstComparisonFileIfNeeded()
        }
        .onChange(of: viewModel.activeBurstComparisonGroupID) { _, _ in
            session.resetDisplayScope()
            showCandidateInspector = false
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            Task { await session.regenerateFocusMasks(files: files) }
        }
    }

    private var presentation: ComparisonSessionPresentation {
        session.presentation(
            filteredFiles: viewModel.filteredFiles,
            comparisonFileIDs: viewModel.comparisonFileIDs,
            activeBurstComparisonGroupID: viewModel.activeBurstComparisonGroupID,
            burstAnalysisResult: viewModel.burstAnalysisResult(for:),
        )
    }

    private var files: [FileItem] {
        presentation.files
    }

    private var allComparisonFiles: [FileItem] {
        presentation.allComparisonFiles
    }

    private var burstComparisonResult: BurstAnalysisResult? {
        presentation.burstComparisonResult
    }

    private var loadKey: String {
        presentation.loadKey
    }

    private func selectFirstComparisonFileIfNeeded() {
        session.ensureValidSelection(in: files)
    }

    private func installKeyMonitor() {
        keyMonitor.install { event in
            guard canHandleKeyboardShortcut(event: event) else { return .ignored }

            return ComparisonKeyboardController(
                viewModel: viewModel, session: session, showCandidateInspector: $showCandidateInspector,
            ).handleKeyEvent(event)
        }
    }

    private func canHandleKeyboardShortcut(event: NSEvent) -> Bool {
        viewModel.mainViewMode == .comparisonGrid
            && !viewModel.zoomOverlayVisible
            && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && keyboardScope.accepts(event)
    }

    private func removeKeyMonitor() {
        keyMonitor.remove()
    }

}
