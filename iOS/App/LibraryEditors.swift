import SwiftUI
import BetterWisprShared

struct VocabularyEditor: View {
    let model: AppModel
    let original: VocabularyEntry
    @State private var phrase: String
    @State private var replacement: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, entry: VocabularyEntry) {
        self.model = model; original = entry
        _phrase = State(initialValue: entry.phrase)
        _replacement = State(initialValue: entry.replacement)
    }
    var body: some View {
        Form {
            TextField("What recognition hears", text: $phrase)
            TextField("Replace with", text: $replacement)
            if original.learned { Text("Learned from a transcript correction.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Edit vocabulary")
            .toolbar {
                Button("Save") {
                    guard let index = model.library.vocabulary.firstIndex(where: { $0.id == original.id }) else {
                        model.message = "This entry was deleted on another device."; return
                    }
                    if phrase != original.phrase { model.library.vocabulary[index].phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if replacement != original.replacement { model.library.vocabulary[index].replacement = replacement }
                    Task { if await model.persist() { await model.synchronize(); dismiss() } }
                }.disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.isEmpty)
            }
    }
}

struct WritingModeEditor: View {
    let model: AppModel
    let original: WritingMode
    @State private var name: String
    @State private var enabled: Bool
    @State private var triggers: String
    @State private var cleanup: CleanupLevel?
    @State private var tone: StyleTone?
    @State private var instructions: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, mode: WritingMode) {
        self.model = model; original = mode
        _name = State(initialValue: mode.name); _enabled = State(initialValue: mode.isEnabled)
        _triggers = State(initialValue: mode.triggerWords.joined(separator: "\n"))
        _cleanup = State(initialValue: mode.cleanup); _tone = State(initialValue: mode.tone)
        _instructions = State(initialValue: mode.instructions)
    }
    var body: some View {
        Form {
            Section("Mode") {
                TextField("Name", text: $name)
                Toggle("Enabled", isOn: $enabled)
                Picker("Cleanup", selection: $cleanup) {
                    Text("Use default").tag(CleanupLevel?.none)
                    Text("None").tag(Optional(CleanupLevel.none))
                    Text("Light").tag(Optional(CleanupLevel.light))
                    Text("Medium, Light on iOS").tag(Optional(CleanupLevel.medium))
                }
                Picker("Tone", selection: $tone) {
                    Text("Use default").tag(StyleTone?.none)
                    ForEach(StyleTone.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            Section("Spoken triggers, one per line") { TextEditor(text: $triggers).frame(minHeight: 90) }
            Section {
                TextEditor(text: $instructions).frame(minHeight: 120)
                Text("\(instructions.count) / \(WritingMode.instructionLimit)").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Desktop polish instructions") } footer: {
                Text("Used by Medium cleanup on desktop. iOS currently applies Light cleanup. Desktop app and website matching rules are preserved.")
            }
        }.navigationTitle("Edit writing mode")
            .toolbar {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instructions.count > WritingMode.instructionLimit)
            }
    }
    private func save() {
        guard let index = model.library.modes.firstIndex(where: { $0.id == original.id }) else {
            model.message = "This mode was deleted on another device."; return
        }
        var mode = model.library.modes[index]
        if name != original.name { mode.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if enabled != original.isEnabled { mode.isEnabled = enabled }
        if triggers != original.triggerWords.joined(separator: "\n") {
            mode.triggerWords = triggers.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if cleanup != original.cleanup { mode.cleanup = cleanup }
        if tone != original.tone { mode.tone = tone }
        if instructions != original.instructions { mode.instructions = instructions }
        model.library.modes[index] = mode
        Task { if await model.persist() { await model.synchronize(); dismiss() } }
    }
}

struct MeetingEditor: View {
    let model: AppModel
    let original: Meeting
    @State private var title: String
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, meeting: Meeting) {
        self.model = model; original = meeting
        _title = State(initialValue: meeting.title); _notes = State(initialValue: meeting.notes)
    }
    private var current: Meeting { model.library.meetings.first { $0.id == original.id } ?? original }
    private var preview: Meeting {
        var meeting = current; meeting.title = title; meeting.notes = notes; return meeting
    }
    var body: some View {
        Form {
            Section("Meeting") { TextField("Title", text: $title) }
            Section("My notes") { TextEditor(text: $notes).frame(minHeight: 160) }
            if let summary = current.summary {
                Section("Summary") {
                    if preview.summaryNeedsUpdate { Text("The meeting changed since this summary was generated.").font(.caption).foregroundStyle(.orange) }
                    Text(summary.overview)
                    ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in Text(point) }
                }
                if !summary.actionItems.isEmpty {
                    Section("Action items") {
                        ForEach(summary.actionItems) { item in
                            Toggle(item.text, isOn: Binding(get: {
                                current.summary?.actionItems.first { $0.id == item.id }?.isDone ?? item.isDone
                            }, set: { done in
                                guard let meetingIndex = model.library.meetings.firstIndex(where: { $0.id == original.id }),
                                      let itemIndex = model.library.meetings[meetingIndex].summary?.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
                                model.library.meetings[meetingIndex].summary?.actionItems[itemIndex].isDone = done
                                Task { if await model.persist() { await model.synchronize() } }
                            }))
                        }
                    }
                }
            }
            Section("Transcript") { Text(current.transcript).textSelection(.enabled) }
            ShareLink("Share meeting", item: preview.markdown)
        }.navigationTitle("Meeting")
            .toolbar {
                Button("Save") {
                    guard let index = model.library.meetings.firstIndex(where: { $0.id == original.id }) else {
                        model.message = "This meeting was deleted on another device."; return
                    }
                    if title != original.title { model.library.meetings[index].title = title }
                    if notes != original.notes { model.library.meetings[index].notes = notes }
                    Task { if await model.persist() { await model.synchronize(); dismiss() } }
                }
            }
    }
}
