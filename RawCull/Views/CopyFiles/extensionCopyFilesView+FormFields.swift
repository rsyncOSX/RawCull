//
//  extensionCopyTasksView+FormFields.swift
//
//  Created by Thomas Evensen on 13/12/2025.
//
import OSLog
import SwiftUI

// MARK: - Form Field Sections

extension CopyFilesView {
    var sourceanddestination: some View {
        Section("Source and Destination") {
            VStack(alignment: .trailing) {
                HStack {
                    HStack {
                        Text(sourcecatalog)
                        Image(systemName: "arrowshape.right.fill")
                    }
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                    OpencatalogView(
                        selecteditem: $sourcecatalog,
                        catalogs: true,
                        bookmarkKey: "sourceBookmark"
                    )
                }

                HStack {
                    if destinationcatalog.isEmpty {
                        HStack {
                            Text("Select destination")
                                .foregroundColor(Color.red)
                            Image(systemName: "arrowshape.right.fill")
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        HStack {
                            Text(destinationcatalog)
                            Image(systemName: "arrowshape.right.fill")
                        }
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }

                    OpencatalogView(
                        selecteditem: $destinationcatalog,
                        catalogs: true,
                        bookmarkKey: "destBookmark"
                    )
                    .onChange(of: destinationcatalog) {
                        if copytaggedfiles {
                            max = Double(viewModel.extractTaggedfilenames().count)
                        } else {
                            copyratedfiles = 3 // default
                            max = Double(viewModel.extractRatedfilenames(copyratedfiles).count)
                        }
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                    .onChange(of: copytaggedfiles) {
                        if copytaggedfiles {
                            max = Double(viewModel.extractTaggedfilenames().count)
                        } else {
                            copyratedfiles = 3 // default
                            max = Double(viewModel.extractRatedfilenames(copyratedfiles).count)
                        }
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                    .onChange(of: copyratedfiles) {
                        max = Double(viewModel.extractRatedfilenames(copyratedfiles).count)
                        Logger.process.debugMessageOnly("CopyfilesView: max is \(max)")
                    }
                }
            }
        }
    }
}

// MARK: - Copy Options Section Component

struct CopyOptionsSection: View {
    @Binding var copytaggedfiles: Bool
    @Binding var copyratedfiles: Int
    @Binding var dryrun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy Options")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                // Copy tagged files toggle
                ToggleViewDefault(text: "Copy tagged files?",
                                  binding: $copytaggedfiles)

                // Dry run toggle
                ToggleViewDefault(text: "Dry run?",
                                  binding: $dryrun)

                // Rating picker (only shown when not copying tagged files)
                RatingPickerSection(rating: $copyratedfiles)
                    .disabled(copytaggedfiles)
            }
        }
    }
}

// MARK: - Rating Picker Component

struct RatingPickerSection: View {
    @Binding var rating: Int

    var body: some View {
        VStack {
            Label("Minimum Rating", systemImage: "star.fill")
                .foregroundColor(.secondary)

            Spacer()

            Picker("Rating", selection: $rating) {
                ForEach(1 ... 5, id: \.self) { number in
                    HStack {
                        ForEach(0 ..< number, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption)
                        }
                        Text("\(number)")
                    }
                    .tag(number)
                }
            }
            .pickerStyle(DefaultPickerStyle())
            .frame(width: 120)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Action Buttons Component

struct CopyActionButtonsSection: View {
    let dismiss: DismissAction
    let onCopyTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConditionalGlassButton(
                systemImage: "arrowshape.right.fill",
                text: "Start Copy",
                helpText: "Start copying files"
            ) {
                onCopyTapped()
            }

            Spacer()

            Button("Close", role: .close) {
                dismiss()
            }
            .buttonStyle(RefinedGlassButtonStyle())
        }
    }
}
