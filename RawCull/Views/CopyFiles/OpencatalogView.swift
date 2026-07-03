import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct OpencatalogView: View {
    @Binding var selecteditem: String
    @State private var isImporting: Bool = false
    @State private var selectionErrorMessage: String?
    let catalogs: Bool
    let bookmarkKey: String

    var body: some View {
        Button(action: {
            isImporting = true
        }, label: {
            if catalogs {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "text.document.fill")
                    .foregroundStyle(.blue)
            }
        })
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [uutype],
                      onCompletion: { result in
                          switch result {
                          case let .success(url):
                              Logger.process.debugMessageOnly("Selected URL: \(url.path)")

                              guard url.startAccessingSecurityScopedResource() else {
                                  Logger.process.errorMessageOnly(": Failed to start accessing security-scoped resource")
                                  clearBookmarkAndShowError("RawCull could not access the selected folder. Please choose the folder again.")
                                  return
                              }

                              do {
                                  let bookmarkData = try url.bookmarkData(
                                      options: .withSecurityScope,
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil,
                                  )
                                  UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
                                  selecteditem = url.path
                                  Logger.process.debugMessageOnly("Bookmark saved for key: \(bookmarkKey)")
                                  Logger.process.debugMessageOnly("Bookmark data size: \(bookmarkData.count) bytes")
                              } catch {
                                  Logger.process.errorMessageOnly(": Could not create bookmark: \(error)")
                                  clearBookmarkAndShowError("RawCull could not save access to the selected folder. Please choose the folder again.")
                              }

                              url.stopAccessingSecurityScopedResource()

                          case let .failure(error):
                              Logger.process.errorMessageOnly(": File picker error: \(error)")
                              selectionErrorMessage = error.localizedDescription
                          }
                      })
                      .alert("Folder Not Saved", isPresented: selectionErrorIsPresented) {
                          Button("OK", role: .cancel) {
                              selectionErrorMessage = nil
                          }
                      } message: {
                          Text(selectionErrorMessage ?? "")
                      }
    }

    var uutype: UTType {
        if catalogs {
            .directory
        } else {
            .item
        }
    }

    private var selectionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { selectionErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    selectionErrorMessage = nil
                }
            },
        )
    }

    private func clearBookmarkAndShowError(_ message: String) {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        selectionErrorMessage = message
    }
}
