"""Generate an isolated, pinned desktop checkout with the shared package and sync adapter."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f'Expected exactly one patch anchor in {path}: {old[:70]!r}')
    path.write_text(text.replace(old, new, 1))


def prepare(source, output):
    lock = json.loads((ROOT / 'upstream-lock.json').read_text())
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != lock['commit']:
        raise ValueError(f'Upstream revision mismatch: {revision}')
    if output.exists():
        raise ValueError(f'Output already exists; choose a fresh directory: {output}')
    # Validate originals before creating or changing anything in the output.
    for item in lock['files']:
        original = source / 'Sources/BetterWisprCore' / item['path']
        if hashlib.sha256(original.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError(f'Upstream source drift: {item["path"]}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as scratch:
        staging = Path(scratch) / 'desktop'
        subprocess.run(['git', 'clone', '--local', '--no-hardlinks', str(source), str(staging)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(staging), 'checkout', '--detach', lock['commit']], check=True, capture_output=True)
        transform(staging, output)
        staging.rename(output)
    return output


def transform(tree, final_output):
    shared_path = os.path.relpath(ROOT / 'Shared', final_output)
    package = tree / 'Package.swift'
    replace_once(package, '    dependencies: [\n', f'    dependencies: [\n        .package(path: "{shared_path}"),\n')
    product = '.product(name: "BetterWisprShared", package: "Shared")'
    replace_once(package, '.target(name: "BetterWisprCore", dependencies: [', '.target(name: "BetterWisprCore", dependencies: [\n            ' + product + ',')
    replace_once(package, 'dependencies: ["BetterWisprCore", .product(name: "Sparkle", package: "Sparkle")]', 'dependencies: ["BetterWisprCore", ' + product + ', .product(name: "Sparkle", package: "Sparkle")]')
    replace_once(package, 'dependencies: ["BetterWisprCore"])', 'dependencies: ["BetterWisprCore", ' + product + '])')
    replace_once(package, 'dependencies: ["BetterWisprCore", "BetterWispr"]', 'dependencies: ["BetterWisprCore", "BetterWispr", ' + product + ']')
    lock = json.loads((ROOT / 'upstream-lock.json').read_text())
    for item in lock['files']:
        path = tree / 'Sources/BetterWisprCore' / item['path']
        if item['path'] == 'Domain/WritingMode.swift':
            text = path.read_text(); marker = 'extension AppSettings {'
            path.write_text('import Foundation\n\n' + marker + text.split(marker, 1)[1])
        else:
            path.unlink()
    for base in ['Sources', 'Tests/BetterWisprCoreTests']:
        for path in (tree / base).rglob('*.swift'):
            imported = '@testable import BetterWisprShared' if base.startswith('Tests') else 'import BetterWisprShared'
            path.write_text(imported + '\n' + path.read_text())
    for folder, destination in [('Core', 'Sources/BetterWisprCore/Persistence'), ('App', 'Sources/BetterWispr/App'), ('Tests', 'Tests/BetterWisprCoreTests')]:
        for path in (ROOT / 'Desktop/Overlay' / folder).glob('*.swift'):
            shutil.copy2(path, tree / destination / path.name)

    local = tree / 'Sources/BetterWisprCore/Persistence/LocalStore.swift'
    replace_once(local, 'public func save(_ state: SavedState) throws {', 'public func save(_ state: SavedState, recoveringSync: Bool = false) throws {\n        if !recoveringSync { try DesktopLibraryStore.requireNoPending(in: directory) }')
    meeting = tree / 'Sources/BetterWisprCore/Persistence/MeetingStore.swift'
    replace_once(meeting, 'public func save(_ meeting: Meeting) throws {', 'public func save(_ meeting: Meeting, recoveringSync: Bool = false) throws {\n        if !recoveringSync { try DesktopLibraryStore.requireNoPending(in: directory.deletingLastPathComponent()) }')
    replace_once(meeting, 'public func delete(id: UUID) throws {', 'public func delete(id: UUID, recoveringSync: Bool = false) throws {\n        if !recoveringSync { try DesktopLibraryStore.requireNoPending(in: directory.deletingLastPathComponent()) }')

    app = tree / 'Sources/BetterWispr/App/AppModel.swift'
    replace_once(app, '@ObservationIgnored private let store: LocalStore', '@ObservationIgnored let store: LocalStore')
    replace_once(app, '@ObservationIgnored private var storageIsReadable = true', '@ObservationIgnored var storageIsReadable = true')
    replace_once(app, 'private func persist() throws {', 'func persist() throws {')
    replace_once(app, 'var isBusy: Bool { phase ==', 'var isBusy: Bool { librarySyncing || phase ==')
    replace_once(app, '    var modelRevision = 0', '''    var modelRevision = 0
    var librarySyncing = false
    var librarySyncStatus = "Sync off"
    var libraryFolder: URL?
    @ObservationIgnored var libraryFolderScoped = false
    @ObservationIgnored var librarySyncState = DesktopSyncState()
    @ObservationIgnored let libraryExchange = DesktopLibraryExchange()
    @ObservationIgnored var libraryPoll: Task<Void, Never>?''')
    replace_once(app, '        self.startsServices = startsServices\n', '''        self.startsServices = startsServices
        let recoveryFailure: String?
        do { try DesktopLibraryStore(directory: store.directory).recover(); recoveryFailure = nil }
        catch { recoveryFailure = error.localizedDescription }
''')
    replace_once(app, '        guard startsServices else { return }\n', '''        if let recoveryFailure { storageIsReadable = false; statusMessage = recoveryFailure }
        guard startsServices else { return }
        restoreLibraryConnection()
        startLibraryPolling()
''')
    settings = tree / 'Sources/BetterWispr/Features/Settings/SettingsView.swift'
    replace_once(settings, '                SettingsSection("Permissions") {', '                LibrarySyncSection(model: model)\n\n                SettingsSection("Permissions") {')
    meetings = tree / 'Sources/BetterWispr/App/MeetingModel.swift'
    replace_once(meetings, '    var activity: MeetingActivity = .idle', '    var librarySyncing = false\n    var activity: MeetingActivity = .idle')
    text = meetings.read_text().replace('guard activity == .idle else { return }', 'guard activity == .idle, !librarySyncing else { return }')
    meetings.write_text(text)
    replace_once(meetings, '    private func saveNow(_ id: UUID) {', '''    func flushForLibrarySync() throws {
        try DesktopLibraryStore.requireNoPending(in: store.directory.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: store.directory.path) {
            _ = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
        }
        guard store.load().unreadable.isEmpty else { throw DesktopSyncError.unreadableMeetings }
        for task in saves.values { task.cancel() }
        saves.removeAll()
        for meeting in meetings { try store.save(meeting) }
    }

    func acceptLibrarySync(_ values: [Meeting]) {
        for task in saves.values { task.cancel() }
        saves.removeAll()
        meetings = values
        if let id = selectedID, !values.contains(where: { $0.id == id }) { selectedID = nil }
    }

    private func saveNow(_ id: UUID) {''')
    reuse = tree / 'docs/oss-reuse.md'
    with reuse.open('a') as file:
        file.write('\n\n## BetterWispr iOS companion integration\n\nGenerated by betterwispr-codex-dev/scripts/prepare_desktop.py. Domain and cleanup definitions now come from the pinned BetterWisprShared package. The desktop-only AppSettings extension remains here. DesktopLibraryStore adds replayable sync persistence and LibrarySync adds folder selection and foreground exchange. Original Apache-2.0 license retained.\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, help='Clean checkout at the pinned upstream revision')
    parser.add_argument('--output', type=Path, default=ROOT / 'Desktop/Upstream')
    args = parser.parse_args()
    if args.source:
        prepare(args.source.resolve(), args.output.resolve())
    else:
        lock = json.loads((ROOT / 'upstream-lock.json').read_text())
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'upstream'
            subprocess.run(['git', 'clone', lock['repository'], str(source)], check=True)
            subprocess.run(['git', '-C', str(source), 'checkout', '--detach', lock['commit']], check=True)
            prepare(source, args.output.resolve())
    print(f'Desktop integration generated: {args.output}')

if __name__ == '__main__':
    main()
