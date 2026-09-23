import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct OpencatalogView: View {
    @Binding var selectedItem: String
    @State private var isImporting: Bool = false
    @State private var selectionErrorMessage: String?
    let catalogs: Bool
    let bookmarkStore: CopyBookmarkStore

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
                      allowedContentTypes: [allowedContentType],
                      onCompletion: { result in
                          switch result {
                          case let .success(url):
                              Logger.process.debugMessageOnly("Selected URL: \(url.path)")

                              do {
                                  try bookmarkStore.saveDestination(url)
                                  selectedItem = url.path
                              } catch CopyBookmarkFailure.accessDenied {
                                  selectionErrorMessage = "RawCull could not access the selected folder. Please choose the folder again."
                              } catch {
                                  Logger.process.errorMessageOnly(": Could not create bookmark: \(error)")
                                  selectionErrorMessage = "RawCull could not save access to the selected folder. Please choose the folder again."
                              }

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

    var allowedContentType: UTType {
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
}
