# Verification

## Automated

1. `python3 scripts/check_source.py` checks extracted-source hashes and required target inputs. It does not prove Swift correctness.
2. `python3 -m unittest discover -s scripts/tests -v` runs three portable tests covering source validation and desktop patch anchors.
3. `swift test --package-path Shared` runs journal and pipeline tests on macOS. Cases cover two-device edits, deletion tombstones, repeated exchange, conflict ordering, malformed files, payload validation, vocabulary application, edits made during sync, cloud placeholders and missing previously seen events. There are ten shared tests.
4. `xcodegen generate` then the simulator build command in README compiles the application and keyboard. No signing assets are needed for that command.

5. `python3 scripts/prepare_desktop.py` generates the pinned desktop integration, then `swift build --package-path Desktop/Upstream` and `swift test --package-path Desktop/Upstream` compile it and run 172 upstream/desktop tests, including five integration/recovery tests. Use a fresh output directory for regeneration.

Exact checked commits and CI links are in [verification.md](verification.md).

## Device acceptance, pending

- Launch fresh, deny microphone and speech separately, then grant access in Settings. Confirm actionable errors and no stuck processing state.
- In airplane mode, dictate a supported language with downloaded Apple assets. Confirm recognition stays local. Try an unsupported language and verify no API fallback occurs.
- Record, stop, cancel during permission prompts and processing, hit the 60-second limit, switch apps and interrupt capture with a call.
- Edit a transcript, relaunch and verify edited plus raw text. Confirm vocabulary learning, spoken mode selection, disabled history and keyboard snapshot deletion behavior.
- Explicitly select a test API endpoint. Verify successful transcription, invalid key, timeout and HTTP redirect rejection. Confirm credentials never appear in the journal.
- On two devices sharing one iCloud Drive folder, create separate records, edit one record concurrently, delete, disconnect/reconnect and simulate unavailable files. Confirm convergence and retained tombstones.
- Edit existing vocabulary, writing modes and meeting notes; toggle action items, relaunch and confirm persistence. Verify failed saves show an error and retain the editor.
- On the patched desktop, connect/relaunch/disconnect both an ordinary folder and iCloud folder. Confirm idle sync resumes and corrupt storage is preserved.
- Enable the keyboard with and without Full Access. Insert a saved transcript into Notes. Test VoiceOver, larger text, landscape, iPad and the globe menu.
- A signed app must pass a separate TestFlight/device gate before any release claim. Simulator compilation alone does not validate microphone, Speech assets, iCloud bookmarks or App Group entitlements.
