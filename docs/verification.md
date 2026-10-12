# Verification record

2026-10-12: source commit `29a7470d648ea4b246f3177133bdd9912fbe2367` passed workflow [38297305846](https://github.com/adamfrank321/betterwispr-codex-dev/actions/runs/38297305846).

- Full patched desktop app compiled.
- All 172 upstream and desktop tests passed, including five desktop sync tests.
- All 10 shared-library tests passed.
- iOS app and keyboard compiled for the simulator.
- Three portable Python tests and source provenance checks passed.

Commit `8d91ded82bca18566595a456b3706c3412365a12` adds iOS library editors and a desktop folder-access adjustment. Its Apple verification is pending; GitHub had not created a push workflow run when this note was written. Do not treat it as already tested.

Physical-device capture, keyboard insertion, iCloud propagation and signing remain unverified. See testing.md for acceptance steps.
