//
//  SimilarityGridSelectionView.swift
//  RawCull
//
//  Similarity and burst-grouping home with category-based result browsing.
//

import AppKit
import SwiftUI

struct SimilarityGridSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var analyzeBurstsRequested: Bool = false
    @State private var pendingRegroupTask: Task<Void, Never>?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        if viewModel.similarityModel.burstModeActive {
            CullingGridView(viewModel: viewModel) {
                burstGroupHeaderControls
            }
        } else {
            BurstGroupsHomeView(
                viewModel: viewModel,
                analyzeBurstsRequested: $analyzeBurstsRequested,
            )
        }
    }

    @ViewBuilder
    private var burstGroupHeaderControls: some View {
        HStack(spacing: 8) {
            Text("Similarity")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Slider(
                value: $viewModel.similarityModel.burstSensitivity,
                in: 0.05 ... 0.60,
            )
            .frame(width: 120)
            .help("Burst sensitivity — lower = tighter groups, higher = similar scenes grouped together")
            .onChange(of: viewModel.similarityModel.burstSensitivity) { _, _ in
                pendingRegroupTask?.cancel()
                pendingRegroupTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled {
                        return
                    }
                    await viewModel.reGroupBursts()
                }
            }

            Text(
                String(
                    format: "%.2f · %d groups",
                    viewModel.similarityModel.burstSensitivity,
                    viewModel.similarityModel.burstGroups.count,
                ),
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 84, alignment: .leading)
        }

        Spacer(minLength: 8)

        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating focus-mask threshold, please wait...")
            }
        }
    }
}
