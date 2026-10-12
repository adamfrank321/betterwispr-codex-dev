import Foundation

public struct DictationOutput: Sendable {
    public let text: String
    public let vocabularyFixes: Int
    public let effectiveMode: WritingMode?
}

public enum DictationPipeline {
    /// Medium requires an explicitly available notes model; this base pass always stays local.
    public static func process(_ raw: String, language: String, library: LibrarySnapshot,
                               selectedMode: WritingMode? = nil, tone: StyleTone = .formal) -> DictationOutput {
        let match = library.modes.match(transcript: raw)
        let mode = match?.mode ?? selectedMode
        let input = match?.transcript ?? raw
        let cleanup = mode?.cleanup ?? library.preferences.cleanup
        var text = cleanup == .none ? input.trimmingCharacters(in: .whitespacesAndNewlines)
            : TranscriptCleaner.clean(input, language: language)
        let commands = VocabularyProcessor.correctedCommands(library.vocabulary, in: text)
        text = commands.text
        if TranscriptCleaner.isEnglish(text, language: language) {
            text = VoiceCommands.apply(text)
            text = StyleFormatter.apply(mode?.tone ?? tone, to: text)
        }
        let corrected = VocabularyProcessor.corrected(library.vocabulary, in: text)
        return DictationOutput(text: corrected.text, vocabularyFixes: commands.fixes + corrected.fixes, effectiveMode: mode)
    }
}
