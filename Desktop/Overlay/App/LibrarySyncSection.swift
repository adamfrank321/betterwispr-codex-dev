import SwiftUI
import AppKit

struct LibrarySyncSection: View {
    @Bindable var model: AppModel
    var body: some View {
        SettingsSection("Library sync") {
            SettingRow("Shared folder", caption: model.librarySyncStatus) {
                HStack {
                    Button(model.libraryFolder == nil ? "Connect…" : "Change…") { model.chooseLibraryFolder() }
                    if model.libraryFolder != nil {
                        Button("Sync now") { Task { await model.synchronizeLibrary() } }
                        Button("Disconnect") { model.disconnectLibrary() }
                    }
                }.disabled(model.isBusy || model.meetings.activity != .idle)
            }
        } footer: {
            Text("Choose the same folder on Mac and iPhone. History, vocabulary, modes and meetings sync; audio, model files and API keys stay on each device. Sync runs while Settings is open, or when you click Sync now.")
        }
        .task {
            while !Task.isCancelled {
                await model.synchronizeLibrary()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
}
