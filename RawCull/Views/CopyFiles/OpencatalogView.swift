import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct OpencatalogView: View {
    @Binding var selecteditem: String
    @State private var isImporting: Bool = false
    let catalogs: Bool
    let bookmarkKey: String

    var body: some View {
        Button(action: {
            isImporting = true
        }, label: {
            if catalogs {
                Image(systemName: "folder.fill")
                    .foregroundColor(Color(.blue))
            } else {
                Image(systemName: "text.document.fill")
                    .foregroundColor(Color(.blue))
            }
        })
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [uutype],
                      onCompletion: { result in
                          switch result {
                          case let .success(url):
                              Logger.process.debugMessageOnly("Selected URL: \(url.path)")
                              selecteditem = url.path

                              // Start accessing FIRST
                              guard url.startAccessingSecurityScopedResource() else {
                                  Logger.process.errorMessageOnly(": Failed to start accessing security-scoped resource")
                                  return
                              }

                              // Try to create bookmark
                              do {
                                  let bookmarkData = try url.bookmarkData(
                                      options: .withSecurityScope,
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil
                                  )
                                  UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                                  Logger.process.debugMessageOnly("Bookmark saved for key: \(bookmarkKey)")
                                  Logger.process.debugMessageOnly("Bookmark data size: \(bookmarkData.count) bytes")
                              } catch {
                                  Logger.process.warning("WARNING: Could not create bookmark, but path is still set: \(error)")
                                  // Path is still accessible via selecteditem
                              }

                              // Stop accessing (will be restarted when rsync runs)
                              url.stopAccessingSecurityScopedResource()

                          case let .failure(error):
                              Logger.process.errorMessageOnly(": File picker error: \(error)")
                          }
                      })
    }

    var uutype: UTType {
        if catalogs {
            .directory
        } else {
            .item
        }
    }
}
