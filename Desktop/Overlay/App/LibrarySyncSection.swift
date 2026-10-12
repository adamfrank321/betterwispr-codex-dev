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
            Text("Choose the same folder on Mac and iPhone. History, vocabulary, modes and meetings sync; audio, model files and API keys stay on each device. Sync runs every 30 seconds while the desktop app is running and idle, or when you click Sync now.")
        }
    }
}
