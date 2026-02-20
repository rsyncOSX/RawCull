import AppKit
import SwiftUI

struct FileInspectorView: View {
    @Binding var file: FileItem?
    @State var nsImage: NSImage?

    var body: some View {
        VStack {
            HistogramView(nsImage: $nsImage)
                .padding()

            if let file {
                Form {
                    Section("File Attributes") {
                        LabeledContent("Size", value: file.formattedSize)
                        LabeledContent("Path", value: file.url.deletingLastPathComponent().path())
                        LabeledContent("Modified", value: file.dateModified.formatted(date: .abbreviated, time: .shortened))
                    }

                    if let exif = file.exifData {
                        Section("Camera Settings") {
                            if let camera = exif.camera {
                                LabeledContent("Camera", value: camera)
                            }
                            if let lens = exif.lensModel {
                                LabeledContent("Lens", value: lens)
                            }
                            if let focalLength = exif.focalLength {
                                LabeledContent("Focal Length", value: focalLength)
                            }
                            if let aperture = exif.aperture {
                                LabeledContent("Aperture", value: aperture)
                            }
                            if let shutterSpeed = exif.shutterSpeed {
                                LabeledContent("Shutter Speed", value: shutterSpeed)
                            }
                            if let iso = exif.iso {
                                LabeledContent("ISO", value: iso)
                            }
                        }
                    }

                    Section("Quick Actions") {
                        Button("Open in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                        Button("Open ARW File") { NSWorkspace.shared.open(file.url) }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Details")
            }
        }
        .onChange(of: file) {
            Task {
                if let file {
                    let cgImage = await SharedRequestThumbnail.shared.requestThumbnail(for: file.url, targetSize: 1024)
                    if let cgImage {
                        nsImage = NSImage(cgImage: cgImage, size: .zero)
                    } else {
                        nsImage = nil
                    }
                }
            }
        }
    }
}
