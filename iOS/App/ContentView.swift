import SwiftUI
import BetterWisprShared

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { capture }.tabItem { Label("Dictate", systemImage: "waveform") }
            NavigationStack { history }.tabItem { Label("History", systemImage: "clock") }
            NavigationStack { library }.tabItem { Label("Library", systemImage: "books.vertical") }
            NavigationStack { SettingsView(model: model) }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .alert("BetterWispr", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    private var capture: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Say it your way.").font(.largeTitle.bold())
                Text(model.settings.provider == "apple" ? "On-device transcription" : "Audio sent to your selected API provider")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Writing mode", selection: $model.selectedModeID) {
                    Text("Default").tag(UUID?.none)
                    ForEach(model.library.modes.filter(\.isEnabled)) { mode in Text(mode.name).tag(Optional(mode.id)) }
                }
                .disabled(model.phase != .idle)
                VStack(spacing: 16) {
                    Image(systemName: model.phase == .recording ? "waveform" : "mic.fill")
                        .font(.system(size: 60)).foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    Text(status).font(.headline)
                    if model.phase == .recording {
                        ProgressView(value: Double(model.recorder.level)).accessibilityLabel("Microphone level")
                        Text(model.recorder.elapsed, format: .number.precision(.fractionLength(0))) + Text(" seconds")
                        Button("Finish recording", systemImage: "stop.fill") { model.finish() }.buttonStyle(.borderedProminent)
                    } else if model.phase == .idle {
                        Button("Start dictation", systemImage: "mic.fill") { model.start() }.buttonStyle(.borderedProminent)
                            .disabled(!model.isLoaded)
                        Button("Record meeting clip") { model.start(meeting: true) }.disabled(!model.isLoaded)
                    } else { ProgressView() }
                    if model.phase != .idle { Button("Cancel", role: .cancel) { model.cancel() } }
                    Text("Clips are limited to 60 seconds in this first version. Keep the app open while transcribing.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(24).background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
                if !model.currentText.isEmpty {
                    Text("Latest transcript").font(.headline)
                    TextEditor(text: $model.currentText).frame(minHeight: 160)
                    HStack {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = model.currentText }
                        ShareLink(item: model.currentText)
                    }
                    Text("Edits here affect copy and sharing. Edit a saved entry in History to update your library.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }.navigationTitle("BetterWispr").navigationBarTitleDisplayMode(.inline)
    }

    private var status: String {
        switch model.phase {
        case .idle: "Ready when you are"
        case .preparing: "Preparing microphone"
        case .recording: "Listening"
        case .processing: "Transcribing"
        }
    }

    private var history: some View {
        List {
            if model.library.history.isEmpty { ContentUnavailableView("No dictations yet", systemImage: "waveform", description: Text("Record your first dictation to save it here.")) }
            ForEach(model.library.history) { item in
                NavigationLink {
                    TranscriptEditor(model: model, transcript: item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text).lineLimit(3)
                        Text(item.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { indices in
                model.library.history.remove(atOffsets: indices)
                Task { await model.persist(); await model.synchronize() }
            }
        }.navigationTitle("History").refreshable { await model.synchronize() }
    }

    private var library: some View {
        List {
            Section {
                NavigationLink("Vocabulary") { VocabularyView(model: model) }
                NavigationLink("Writing modes") { ModesView(model: model) }
            }
            Section("Usage") {
                let totals = UsageInsights(model.library.history).current
                LabeledContent("Dictations", value: "\(totals.dictations)")
                LabeledContent("Words", value: "\(totals.words)")
                LabeledContent("Words per minute", value: "\(totals.wordsPerMinute)")
            }
            Section("Meeting clips") {
                if model.library.meetings.isEmpty { Text("Meeting clips appear here.").foregroundStyle(.secondary) }
                ForEach(model.library.meetings) { meeting in
                    NavigationLink(meeting.displayTitle) {
                        MeetingEditor(model: model, meeting: meeting)
                    }
                }.onDelete { indices in
                    model.library.meetings.remove(atOffsets: indices)
                    Task { await model.persist(); await model.synchronize() }
                }
            }
        }.navigationTitle("Library")
    }
}

private struct TranscriptEditor: View {
    let model: AppModel
    let transcript: Transcript
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, transcript: Transcript) {
        self.model = model; self.transcript = transcript
        _text = State(initialValue: transcript.text)
    }
    var body: some View {
        Form {
            Section("Transcript") { TextEditor(text: $text).frame(minHeight: 200) }
            Section("Original recognition") { Text(transcript.rawText).textSelection(.enabled) }
            ShareLink(item: text)
        }.navigationTitle("Edit transcript")
            .toolbar { Button("Save") { Task { await model.edit(transcript, text: text); dismiss() } } }
    }
}

private struct VocabularyView: View {
    @Bindable var model: AppModel
    @State private var phrase = ""
    @State private var replacement = ""
    var body: some View {
        Form {
            Section("Add a correction") {
                TextField("What recognition hears", text: $phrase)
                TextField("Replace with", text: $replacement)
                Button("Add") {
                    model.library.vocabulary.append(VocabularyEntry(phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines), replacement: replacement))
                    phrase = ""; replacement = ""
                    Task { await model.persist(); await model.synchronize() }
                }.disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.isEmpty)
            }
            Section("Saved vocabulary") {
                ForEach(model.library.vocabulary) { entry in
                    NavigationLink {
                        VocabularyEditor(model: model, entry: entry)
                    } label: {
                        VStack(alignment: .leading) { Text(entry.phrase); Text(entry.replacement).foregroundStyle(.secondary) }
                    }
                }.onDelete { offsets in
                    model.library.vocabulary.remove(atOffsets: offsets)
                    Task { await model.persist(); await model.synchronize() }
                }
            }
        }.navigationTitle("Vocabulary")
    }
}

private struct ModesView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var trigger = ""
    @State private var tone = StyleTone.formal
    var body: some View {
        Form {
            Section("Add a writing mode") {
                TextField("Name", text: $name)
                TextField("Spoken trigger, optional", text: $trigger)
                Picker("Tone", selection: $tone) {
                    ForEach(StyleTone.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("Add mode") {
                    let word = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.library.modes.append(WritingMode(name: name, triggerWords: word.isEmpty ? [] : [word], tone: tone))
                    name = ""; trigger = ""
                    Task { await model.persist(); await model.synchronize() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Saved modes") {
                ForEach(model.library.modes) { mode in
                    NavigationLink {
                        WritingModeEditor(model: model, mode: mode)
                    } label: {
                        VStack(alignment: .leading) { Text(mode.name); Text(mode.triggerWords.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }.onDelete { offsets in
                    model.library.modes.remove(atOffsets: offsets)
                    Task { await model.persist(); await model.synchronize() }
                }
            }
        }.navigationTitle("Writing modes")
    }
}
