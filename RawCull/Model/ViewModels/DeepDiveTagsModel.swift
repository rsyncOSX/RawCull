//
//  DeepDiveTagsModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 25/02/2026.
//

import Foundation
import ImageIO
import Observation

@Observable
final class DeepDiveTagsModel {
    
    func printAllMetadata(for url: URL) {
        print("\n--- 📂 DEEP SCAN START: \(url.lastPathComponent) ---")

        // 1. Create the Image Source
        // We set 'shouldCache: false' because we only want the headers, not the pixels.
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            print("❌ Failed to create image source.")
            return
        }

        let count = CGImageSourceGetCount(source)
        let type = CGImageSourceGetType(source) ?? "unknown" as CFString
        print("File Type: \(type)")
        print("Number of Image Indices: \(count)")

        // 2. Iterate through every index (Index 0 is usually the RAW, 1+ are previews)
        for i in 0 ..< count {
            print("\n--- 📘 Index \(i) Properties ---")
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any] {
                printRecursive(dictionary: props, indent: 0)
            }

            // 3. Scan the XMP/Metadata Tree (sometimes contains tags missing from Properties)
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, i, nil) {
                print("\n--- 🌳 Index \(i) Metadata Tree (XMP) ---")
                CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                    if let value = CGImageMetadataTagCopyValue(tag) {
                        print("   [Tag] \(path): \(value)")
                    }
                    return true
                }
            }
        }
        print("\n--- ✅ DEEP SCAN COMPLETE ---")
    }

    /// Helper function to recursively print nested dictionaries with indentation
    private func printRecursive(dictionary: [String: Any], indent: Int) {
        let padding = String(repeating: "  ", count: indent)

        // Sort keys so the output is easier to read
        for key in dictionary.keys.sorted() {
            let value = dictionary[key]!

            if let subDict = value as? [String: Any] {
                print("\(padding)📂 [\(key)]")
                printRecursive(dictionary: subDict, indent: indent + 1)
            } else if let array = value as? [Any] {
                print("\(padding)🔢 [\(key)]: Array(\(array.count)) \(array)")
            } else {
                print("\(padding)🏷 \(key): \(value)")
            }
        }
    }
}
