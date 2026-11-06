import OSLog
import RawCullCore
import SwiftUI

struct BurstWorkspaceFilmstrip: View {
    let viewModel: RawCullViewModel
    let files: [FileItem]
    let analysis: BurstAnalysisResult?
    let burstNumber: Int
    var isSingleImages = false
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let navigate: (Int) -> Void

    var showsCloseUpSelection = false
    var closeUpSelection: Set<URL> = []
    var selectCloseUp: (URL, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var toggleCloseUp: (URL) -> Void = { _ in }

    private var selectedIndex: Int {
        files.firstIndex { $0.id == viewModel.selectedFileID } ?? 0
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isSingleImages ? "Single Images" : "Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")
                Text("\(selectedIndex + 1) / \(files.count)")
                if !isSingleImages {
                    Text("⌘/⇧ select")
                        .font(.caption)
                }
            }
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .frame(width: isSingleImages ? 110 : 76, alignment: .leading)

            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(files) { file in
                                VStack(spacing: 4) {
                                    BurstFilmstripThumbnail(
                                        file: file,
                                        isSelected: file.id == viewModel.selectedFileID,
                                        isSuggested: analysis?.recommendedFileID == file.id,
                                        isDeferred: analysis?.reviewState == .deferred,
                                        isIncludedInCloseUps: !isSingleImages && closeUpSelection.contains(file.url),
                                    ) {
                                        if !isSingleImages {
                                            selectCloseUp(file.url, NSEvent.modifierFlags)
                                        }
                                        viewModel.selectedFileID = file.id
                                    }
                                    .help(!isSingleImages ? "Command-click to select multiple close-ups; Shift-click to select a range, then open Close-ups." : file.name)
                                    if showsCloseUpSelection {
                                        Toggle("Close-up", isOn: Binding(
                                            get: { closeUpSelection.contains(file.url) },
                                            set: { _ in toggleCloseUp(file.url) },
                                        ))
                                        .toggleStyle(.checkbox)
                                        .font(.caption)
                                        .accessibilityLabel("Close-up for \(file.name)")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                    .onAppear(perform: {
                        // Defer one run loop so LazyVStack IDs are registered in scroll geometry
                        DispatchQueue.main.async {
                            if let newID = viewModel.selectedFile?.id {
                                withAnimation {
                                    proxy.scrollTo(newID, anchor: .center)
                                }
                            }
                        }
                    })
                    .onChange(of: viewModel.selectedFileID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                    .onChange(of: files.map(\.id)) { _, _ in
                        guard let selectedID = viewModel.selectedFileID else { return }
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }

            HStack(spacing: 8) {
                navigationButton(systemImage: "chevron.left", delta: -1)
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
        }
        .padding(16)
        .frame(height: showsCloseUpSelection ? 166 : 144)
        .background(.quaternary.opacity(0.28))
    }

    private func navigationButton(systemImage: String, delta: Int) -> some View {
        Button { navigate(delta) } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(delta < 0 ? !canNavigatePrevious : !canNavigateNext)
    }
}
