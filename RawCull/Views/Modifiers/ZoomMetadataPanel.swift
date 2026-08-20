import AppKit
import SwiftUI

struct ZoomMetadataPanel: View {
    let file: FileItem
    let image: NSImage?
    let cullingMetadata: ZoomCullingMetadata
    let onHide: () -> Void

    @State private var isCollapsed = false

    private let columns = [
        GridItem(.fixed(92), alignment: .trailing),
        GridItem(.flexible(minimum: 120), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !isCollapsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        histogramSection

                        if cullingMetadata.hasDecisionEvidence {
                            metadataSection("Culling", rows: cullingMetadata.decisionRows)
                        }

                        metadataSection("File Attributes", rows: fileAttributeRows)

                        if !cameraSettingRows.isEmpty {
                            metadataSection("Camera Settings", rows: cameraSettingRows)
                        }

                        quickActions
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300)
        .frame(maxHeight: 680, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.url.deletingLastPathComponent().path())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand metadata" : "Collapse metadata")
            .accessibilityLabel(isCollapsed ? "Expand metadata" : "Collapse metadata")

            Button(action: onHide) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide metadata (E)")
            .accessibilityLabel("Hide metadata")
        }
    }

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("Histogram")
            HistogramView(nsImage: image)
        }
    }

    private func metadataSection(_ title: LocalizedStringKey, rows: [MetadataRow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle(title)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                ForEach(rows) { row in
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .lineLimit(row.allowsMultipleLines ? 2 : 1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .font(.caption)
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Quick Actions")

            HStack(spacing: 8) {
                Spacer()

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }

                Button("Open RAW File") {
                    NSWorkspace.shared.open(file.url)
                }
            }
            .controlSize(.small)
        }
    }

    private var fileAttributeRows: [MetadataRow] {
        var rows = [
            MetadataRow(id: "size", label: "Size", value: file.formattedSize),
            MetadataRow(
                id: "path",
                label: "Path",
                value: file.url.deletingLastPathComponent().path(),
                allowsMultipleLines: true
            )
        ]

        if let captureDate = file.captureDate {
            rows.append(MetadataRow(
                id: "captured",
                label: "Captured",
                value: captureDate.formatted(date: .abbreviated, time: .standard),
            ))
        }

        rows.append(MetadataRow(
            id: "modified",
            label: "Modified",
            value: file.dateModified.formatted(date: .abbreviated, time: .shortened),
        ))
        return rows
    }

    private var cameraSettingRows: [MetadataRow] {
        guard let exif = file.exifData else { return [] }
        var rows: [MetadataRow] = []

        append(exif.camera, id: "camera", label: "Camera", to: &rows)
        append(exif.lensModel, id: "lens", label: "Lens", to: &rows)
        append(exif.focalLength, id: "focalLength", label: "Focal Length", to: &rows)
        append(exif.aperture, id: "aperture", label: "Aperture", to: &rows)
        append(exif.shutterSpeed, id: "shutterSpeed", label: "Shutter Speed", to: &rows)
        append(exif.iso, id: "iso", label: "ISO", to: &rows)

        if let compensation = exif.exposureCompensationEV {
            let value = compensation.formatted(
                .number.precision(.fractionLength(1 ... 2)),
            )
            rows.append(MetadataRow(
                id: "exposureCompensation",
                label: "Exposure Compensation",
                value: "\(value) EV",
            ))
        }

        append(exif.rawFileType, id: "rawType", label: "RAW Type", to: &rows)

        if let width = exif.pixelWidth, let height = exif.pixelHeight {
            let megapixels = Double(width * height) / 1_000_000
            var value = "\(width.formatted()) × \(height.formatted())  "
            value += "\(megapixels.formatted(.number.precision(.fractionLength(1)))) MP"
            if let rawSizeClass = exif.rawSizeClass {
                value += " (\(rawSizeClass))"
            }
            rows.append(MetadataRow(id: "dimensions", label: "Dimensions", value: value))
        }

        return rows
    }

    private func append(
        _ value: String?,
        id: String,
        label: LocalizedStringKey,
        to rows: inout [MetadataRow],
    ) {
        guard let value else { return }
        rows.append(MetadataRow(id: id, label: label, value: value))
    }
}

struct MetadataRow: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let value: String
    var allowsMultipleLines = false
}
