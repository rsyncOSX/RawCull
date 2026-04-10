//
//  SharpnessControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

struct SharpnessControlsView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var sharpnessThreshold: Int

    var body: some View {
        // Score button — calibrates from the burst then scores
        Button {
            Task { await viewModel.calibrateAndScoreCurrentCatalog() }
        } label: {
            if viewModel.sharpnessModel.isScoring {
                Label("Scoring…", systemImage: "scope")
            } else if viewModel.sharpnessModel.scores.isEmpty {
                Label("Score Sharpness", systemImage: "scope")
            } else {
                Label("Re-score", systemImage: "scope")
            }
        }
        .font(.caption)
        .disabled(viewModel.sharpnessModel.isScoring || viewModel.files.isEmpty)
        .help("Auto-calibrate threshold and gain from this burst, then score sharpness")

        // Cancel button — only visible while scoring
        if viewModel.sharpnessModel.isScoring {
            Button(role: .cancel) {
                viewModel.sharpnessModel.cancelScoring()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .font(.caption)
            .tint(.red)
            .help("Abort sharpness scoring and discard results")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Sort toggle — only visible once scores exist and not currently scoring
        if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
            Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                Label("Sharpness", systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .font(.caption)
            .help("Sort thumbnails sharpest-first")
            .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        // Subject filter — only visible once saliency data exists
        if !viewModel.sharpnessModel.saliencyInfo.isEmpty, !viewModel.sharpnessModel.isScoring {
            Picker("Subject", selection: $viewModel.sharpnessModel.saliencyCategoryFilter) {
                Text("All Subjects").tag(String?.none)
                ForEach(viewModel.sharpnessModel.availableSaliencyCategories, id: \.self) { label in
                    Text(label.capitalized).tag(String?.some(label))
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
            .frame(width: 130)
            .help("Filter thumbnails by detected subject category")
            .onChange(of: viewModel.sharpnessModel.saliencyCategoryFilter) { _, _ in
                Task(priority: .background) { await viewModel.handleSortOrderChange() }
            }
        }

        Picker("Aperture", selection: $viewModel.sharpnessModel.apertureFilter) {
            ForEach(ApertureFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .frame(width: 160)
        .help("Filter by aperture — Wide for birds/portraits, Landscape for stopped-down shots")
        .onChange(of: viewModel.sharpnessModel.apertureFilter) { _, _ in
            Task(priority: .background) {
                await viewModel.handleSortOrderChange()
            }
        }

        // Sharpness threshold classifier — visible once scores exist
        if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
            Picker("Threshold", selection: $sharpnessThreshold) {
                ForEach([20, 30, 40, 50, 60, 70, 80], id: \.self) { pct in
                    Text("\(pct)%").tag(pct)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
            .frame(width: 70)
            .padding(.leading, 12)
            .help("Sharpness cut-off: images at or above this score become Keep (P), below become Rejected (X)")

            Button("Apply") {
                viewModel.applySharpnessThreshold(sharpnessThreshold)
            }
            .font(.caption)
            .padding(.trailing, 12)
            .help("Auto-classify all scored images using the selected sharpness threshold")
        }

        // Spinner shown while calibrating is in progress
        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating sharpness scoring, please wait...")
            }
        }
    }
}
