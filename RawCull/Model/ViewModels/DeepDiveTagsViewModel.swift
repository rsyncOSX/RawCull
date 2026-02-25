//
//  DeepDiveTagsViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 25/02/2026.
//

import ImageIO
import Observation
import SwiftUI

// MARK: - Data Models

enum MetadataValue: Identifiable {
    case scalar(String)
    case array([String])
    case group(String, [MetadataEntry])

    var id: UUID {
        UUID()
    }
}

struct MetadataEntry: Identifiable {
    let id = UUID()
    let key: String
    let value: MetadataValue
}

struct ImageIndexMetadata: Identifiable {
    let id = UUID()
    let index: Int
    let entries: [MetadataEntry]
    let xmpTags: [XMPTag]
}

struct XMPTag: Identifiable {
    let id = UUID()
    let path: String
    let value: String
}

// MARK: - ViewModel

@MainActor
@Observable
final class DeepDiveTagsViewModel {
    var imageMetadata: [ImageIndexMetadata] = []
    var fileName: String = ""
    var fileType: String = ""
    var isLoading = false
    var errorMessage: String?

    func load(url: URL) async {
        isLoading = true
        errorMessage = nil
        fileName = url.lastPathComponent

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            errorMessage = "Failed to create image source."
            isLoading = false
            return
        }

        fileType = (CGImageSourceGetType(source) as String?) ?? "unknown"
        let count = CGImageSourceGetCount(source)
        var results: [ImageIndexMetadata] = []

        for i in 0 ..< count {
            var entries: [MetadataEntry] = []
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any] {
                entries = parseRecursive(dictionary: props)
            }

            var xmpTags: [XMPTag] = []
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, i, nil) {
                CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                    if let value = CGImageMetadataTagCopyValue(tag) {
                        xmpTags.append(XMPTag(path: path as String, value: "\(value)"))
                    }
                    return true
                }
            }

            results.append(ImageIndexMetadata(index: i, entries: entries, xmpTags: xmpTags))
        }

        imageMetadata = results
        isLoading = false
    }

    private func parseRecursive(dictionary: [String: Any]) -> [MetadataEntry] {
        dictionary.keys.sorted().compactMap { key in
            guard let value = dictionary[key] else { return nil }
            if let subDict = value as? [String: Any] {
                let children = parseRecursive(dictionary: subDict)
                return MetadataEntry(key: key, value: .group(key, children))
            } else if let array = value as? [Any] {
                return MetadataEntry(key: key, value: .array(array.map { "\($0)" }))
            } else {
                return MetadataEntry(key: key, value: .scalar("\(value)"))
            }
        }
    }
}
