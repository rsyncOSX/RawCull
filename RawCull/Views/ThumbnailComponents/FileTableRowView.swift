//
//  FileTableRowView.swift
//  RawCull
//

import SwiftUI

struct FileTableRowView: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        let filteredFiles = viewModel.filteredFiles.compactMap { file in
            viewModel.passesRatingFilter(file) ? file : nil
        }

        VStack(alignment: .leading) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor)),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
                )

                Picker("Filter", selection: $viewModel.ratingFilter) {
                    Text("All").tag(RatingFilter.all)
                    Text("✕ Rejected").foregroundStyle(.red).tag(RatingFilter.rejected)
                    Text("Keep").tag(RatingFilter.keepers)
                    ForEach(2 ... 5, id: \.self) { n in
                        HStack(spacing: 2) {
                            ForEach(0 ..< n, id: \.self) { _ in
                                Image(systemName: "star.fill").font(.caption2)
                            }
                        }
                        .tag(RatingFilter.stars(n))
                    }
                }
                .pickerStyle(DefaultPickerStyle())
                .labelsHidden()
            }
            .padding(.horizontal, 4)

            Table(
                filteredFiles,
                selection: $viewModel.selectedFileID,
                sortOrder: $viewModel.sortOrder,
            ) {
                TableColumn("Rating") { file in
                    HStack(spacing: 2) {
                        let rating = viewModel.getRating(for: file)
                        ForEach(2 ... 5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundStyle(star <= rating ? .yellow : .gray)
                                .font(.system(size: 12))
                        }
                    }
                }
                .width(90)

                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 8) {
                        if file.id == viewModel.previouslySelectedFileID {
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.blue)
                                    .frame(width: 3)
                                Spacer()
                            }
                        }
                        Text(file.name)
                    }
                }

                TableColumn("Size", value: \.size) { file in
                    Text(file.formattedSize).monospacedDigit()
                }
                .width(75)

                TableColumn("Created", value: \.dateModified) { file in
                    Text(file.dateModified, style: .date)
                }
            }
        }
        .onChange(of: viewModel.selectedFileID) { _, _ in
            if viewModel.selectedFileID != nil {
                viewModel.previouslySelectedFileID = viewModel.selectedFileID
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task(priority: .background) {
                await viewModel.handleSearchTextChange()
            }
        }
    }
}
