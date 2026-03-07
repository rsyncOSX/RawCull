//
//  TestView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct TestView: View {
    @Environment(\.openWindow) var openWindow
    @Bindable var viewModel: RawCullViewModel

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: UUID?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    @State private var showInspector: Bool = true

    var body: some View {
        if let file = viewModel.selectedFile {
            VStack(spacing: 20) {
                CachedThumbnailView(
                    scale: $scale,
                    lastScale: $lastScale,
                    offset: $offset,
                    url: file.url
                )

                HStack {
                    VStack {
                        Text(file.name)
                            .font(.headline)
                        Text(file.url.deletingLastPathComponent().path())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .inspector(isPresented: $showInspector) {
                FileInspectorView(file: $viewModel.selectedFile)
            }
            .padding()
            // .frame(minWidth: 300, minHeight: 300)
            .onTapGesture(count: 2) {
                guard let selectedID = selectedFileID,
                      let file = files.first(where: { $0.id == selectedID }) else { return }

                JPGPreviewHandler.handle(
                    file: file,
                    setNSImage: { nsImage = $0 },
                    setCGImage: { cgImage = $0 },
                    openWindow: { id in openWindow(id: id) }
                )
            }
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a file to view its properties.")
            )
        }

        Spacer()

        ARWFileTableImageView(
            viewModel: viewModel,
            cullingManager: viewModel.cullingModel,
            files: viewModel.files,
            selectedSource: viewModel.selectedSource
        )
        .padding()
    }

    var files: [FileItem] {
        viewModel.files
    }

    var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }
}

/*
 .if(viewModel.hideInspector == false) { view in
     view.inspector(isPresented: $viewModel.isInspectorPresented) {
         FileInspectorView(file: $viewModel.selectedFile)
     }
 }
 */
