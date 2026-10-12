# Verification record

2026-10-12: commit `6a10f56f0ae29095732f2f4c0e3c84b77af2ac3a` passed both jobs in workflow [38298119747](https://github.com/adamfrank321/betterwispr-codex-dev/actions/runs/38298119747). Its application source is identical to `8d91ded82bca18566595a456b3706c3412365a12`.

- Full patched desktop application compiled.
- All 172 upstream/desktop tests passed, including five desktop integration/recovery tests.
- All 10 shared-library tests passed.
- iOS app and keyboard compiled for the simulator, including the new vocabulary, writing-mode and meeting editors.
- Three portable Python tests and source provenance checks passed, also rerun locally before this documentation update.

Desktop job: `114974075852`. iOS/shared job: `114974076087`. The subsequent handoff commit changes documentation only; no additional native test run is required for it.

Physical-device capture, keyboard insertion, iCloud propagation and signing remain unverified. Automated round trips use temporary local folders and do not prove file-provider behavior. See [testing.md](testing.md) for acceptance steps.
