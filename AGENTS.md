# Working on BetterWispr Mobile

Read `HANDOFF.md` and `TASKS.md` first. Keep both current after each meaningful implementation or verification step. Check boxes only for completed work and distinguish source checks, compiled tests and device tests.

The shared package owns domain types, cleanup and synchronization. iOS owns capture, permissions, Keychain, SwiftUI and keyboard integration. Desktop adapters preserve upstream behavior and use the same shared package. Keep default speech recognition local. Cloud endpoints require explicit selection. Never sync API keys, audio or models. Preserve raw transcripts and unreadable files. Do not silently change the pinned upstream revision.

Run the source validator and portable script tests in Linux. On macOS also run shared Swift tests, iOS simulator builds and upstream desktop build/tests. Record exact failures in the handoff. Do not commit signing assets or personal data.
