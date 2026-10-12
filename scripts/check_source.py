"""Validate source provenance and target inputs. This does not compile Swift."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def validate(root=ROOT):
    failures = []
    lock = json.loads((root / 'upstream-lock.json').read_text())
    for item in lock['files']:
        path = root / 'Shared/Sources/BetterWisprShared' / item['path']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != item['shared_sha256']:
            failures.append(f"Upstream source drift: {item['path']}")
    for name in ['LICENSE', 'AGENTS.md', 'TASKS.md', 'HANDOFF.md', 'project.yml',
                 'iOS/App/BetterWisprApp.swift', 'iOS/App/ContentView.swift',
                 'iOS/Keyboard/KeyboardViewController.swift',
                 'Shared/Tests/BetterWisprSharedTests/LibraryTests.swift']:
        if not (root / name).is_file():
            failures.append(f'Missing required input: {name}')
    keyboard = root / 'iOS/Keyboard/KeyboardViewController.swift'
    if keyboard.is_file():
        for prohibited in ['URLSession', 'AVAudioRecorder', 'UIPasteboard']:
            if prohibited in keyboard.read_text():
                failures.append(f'Keyboard unexpectedly uses {prohibited}')
    return failures

if __name__ == '__main__':
    failures = validate()
    for failure in failures:
        print(failure)
    if failures:
        raise SystemExit(1)
    print('Source provenance and target inputs passed. Swift compilation and device tests are separate gates.')
