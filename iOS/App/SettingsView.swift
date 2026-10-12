import SwiftUI
import BetterWisprShared
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var choosingFolder = false
    @State private var apiKey = ""
    var body: some View {
        Form {
            Section("Recognition") {
                Picker("Provider", selection: $model.settings.provider) {
                    Text("Apple on-device").tag("apple")
                    Text("Custom API").tag("api")
                }
                TextField("Language, e.g. en-US", text: $model.settings.language).autocorrectionDisabled().textInputAutocapitalization(.never)
                if model.settings.provider == "api" {
                    Text("Recording audio will be uploaded to the HTTPS endpoint below when you finish a clip.").font(.caption)
                    TextField("Full transcription URL", text: $model.settings.endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model ID", text: $model.settings.modelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key", text: $apiKey)
                    Button("Save API key on this device") {
                        do { try EndpointKeychain.save(apiKey, endpoint: model.settings.endpoint); apiKey = ""; model.message = "API key saved." }
                        catch { model.message = error.localizedDescription }
                    }
                }
            }
            Section("Writing") {
                Picker("Cleanup", selection: $model.library.preferences.cleanup) {
                    Text("None").tag(CleanupLevel.none)
                    Text("Light").tag(CleanupLevel.light)
                    if model.library.preferences.cleanup == .medium { Text("Medium, uses Light on iOS").tag(CleanupLevel.medium) }
                }
                Toggle("Save dictation history", isOn: $model.settings.saveHistory)
                Toggle("Learn vocabulary from edits", isOn: $model.settings.learnCorrections)
            }
            Section("Library sync") {
                Text(model.syncStatus)
                Button(model.syncFolder == nil ? "Connect shared folder" : "Change shared folder") { choosingFolder = true }
                if model.syncFolder != nil {
                    Button("Sync now") { Task { await model.synchronize() } }
                    Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
                }
                Text("Choose the same folder on each supported device. Transcripts, vocabulary, modes and meeting notes sync. API keys and audio stay out of the sync folder. Desktop integration is still in development.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Text("Add BetterWispr in Settings → General → Keyboard → Keyboards. Enable Full Access to read your shared transcript list. Record in this app, then switch keyboards to insert a saved transcript. The keyboard makes no network requests.")
                    .font(.caption)
            }
        }.navigationTitle("Settings")
            .disabled(model.phase != .idle)
            .onChange(of: model.settings) { _, _ in Task { await model.persist() } }
            .onChange(of: model.library.preferences) { _, _ in Task { await model.persist(); await model.synchronize() } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): Task { await model.connect(url) }
                case .failure(let error): model.message = error.localizedDescription
                }
            }
    }
}
