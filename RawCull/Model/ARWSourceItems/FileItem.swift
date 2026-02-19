import SwiftUI
import UniformTypeIdentifiers

/*
 FileItem is the ARW-file.
 id = 9A332346-142B-4C13-926C-E333961BFDBD: Fr
 url = "file:///Users/thomas/Pictures_raw/2025/1_apr_2025/_DSC5925.ARW": NSURL
 name = "_DSC5925.ARW": String
 size = 53755904: Int64
 type = "Sony ARW raw image": String
 dateModified = 2025-04-01 06:09:43 UTC: Foundatio
 */

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let type: String
    let dateModified: Date
    let exifData: ExifMetadata?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/*
 The catalog name and URL-path to catalog like
 name = "1_apr_2025": String
 url = "file:///Users/thomas/Pictures_raw/2025/1_apr_2025/": NSURL
 */

struct ARWSourceCatalog: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
}
