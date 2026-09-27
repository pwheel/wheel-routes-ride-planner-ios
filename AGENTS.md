# Agent Instructions — Wheel Routes (iOS)

SwiftUI/MVVM iOS app for planning cycle routes via the CycleStreets API, with local persistence for saved routes/locations. No user accounts.

**Read `docs/SPEC.md` first** for architecture, screens, the API contract, and current known limitations. This file is operational instructions only.

## Build & test

```
xcodebuild test -project "Wheel Routes.xcodeproj" -scheme "Wheel Routes" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```

- **`-skipMacroValidation` is required**, not optional, once the `maplibre/swiftui-dsl` package (added for OSM map tile rendering) is present: it ships a Swift Macro, and without this flag `xcodebuild` fails with "Macro ... must be enabled before it can be used" — a one-time interactive Xcode trust prompt that a CLI build can never satisfy. Add the flag to every `xcodebuild build`/`test` invocation (including CI's), not just the one above.
- **Supply-chain note:** `-skipMacroValidation` is a blanket, all-or-nothing bypass — there is no way to trust only a specific package's macro while still gating others. The actual remaining control is `project.pbxproj`'s exact-version pin (`swiftui-dsl` @ `0.25.0`, not a version range) plus the committed `Package.resolved`: a malicious/compromised macro could only enter the dependency graph via a version bump that shows up as a reviewable diff in a PR. Do not loosen that pin to a version range while this flag stays required — doing so would let a transitive dependency update silently start running new, unreviewed compile-time code in CI.
- **Ferrostar supply-chain note:** `stadiamaps/ferrostar` (turn-by-turn navigation, GitHub #20) is also pinned to an exact version (`0.57.0`), for a different reason. It isn't a macro and needs no extra `xcodebuild` flag, but its core is a **precompiled Rust XCFramework** (a checksum-pinned `binaryTarget` downloaded from GitHub Releases), so the navigation logic can't be reviewed as a source diff at all. The checksum only guarantees the binary matches the tagged release, not that the release is benign. Keep the exact pin, and treat any bump as a deliberate, reviewed change (read the release notes), never a version range. Ferrostar declares `swiftui-dsl` `from: 0.25.0`, so a Ferrostar bump that raises that floor forces a `swiftui-dsl` bump too. Review the two together.
- The simulator must be named exactly `iPhone 17` on this machine (`iPhone 16` isn't available) — check `xcrun simctl list devices` if the destination fails and adjust.
- **Stale incremental build gotcha:** `xcodebuild` has been observed to silently skip recompiling a changed test file, causing a rerun to report the *old* pass/fail state. If a newly-added test doesn't appear in the output, or a bug you just fixed still fails identically, compare the `.xctest` bundle's mtime (under `DerivedData/.../Products/Debug-iphonesimulator/*.app/PlugIns/*.xctest`) against your source file's mtime. If the bundle is older, `touch` the changed file(s) and rerun.
- Full-suite runs spin up 2–3 simulator "clones" for parallel testing — this is normal `xcodebuild` behavior, not a hang. Don't manually close/kill clones; let `xcodebuild` manage them.
- Be mindful of system resource load on heavy `xcodebuild` runs. Don't aggressively retry a cancelled or failed run in a tight loop if the failure looks resource-related (e.g. "Invalid device state", Mach IPC errors) rather than a genuine code error — one retry is fine, repeated rapid retries can compound an already-strained machine.

## Conventions

- **Swift Testing**, not XCTest: `import Testing`, `@Test func ...`, `#expect(...)`.
- **TDD**: write a failing test, confirm it fails for the right reason, implement minimally, confirm green. Pure-SwiftUI-wiring changes with no testable logic (navigation, `@State` resets) are build-verify-only — see `docs/SPEC.md` → Test coverage for the established list of what falls in that bucket.
- **Xcode 16+ `PBXFileSystemSynchronizedRootGroup`**: new source files placed under a synced folder are auto-included in the target. Don't hand-edit `project.pbxproj` to add/remove source files.
- `@Observable @MainActor final class` for ViewModels; plain `Codable, Equatable` structs/enums for models.
- Cross-tab state hand-off: see `docs/SPEC.md` → "Cross-tab hand-off pattern" before inventing a new mechanism for passing state/actions between tabs.

## Secrets

- Real API key: `Wheel Routes/Resources/APIKey_dev.txt`, protected via `git update-index --skip-worktree` — not `.gitignore`. Never `git add -f` it or drop the skip-worktree flag.
- `APIKey_live.txt` is gitignored outright, used for release builds only.
- **New-worktree gotcha:** `skip-worktree` is per-checkout, so a freshly created worktree checks out the tracked *placeholder* value (`YOUR_API_KEY_HERE`), not the real key from another checkout's working tree. Symptom: every live API call (search, journey planning) fails, and — because the API's error JSON (`{"error": "No valid API key..."}`) doesn't match the expected response shape — it surfaces as a generic decode error ("The data couldn't be read because it was missing") rather than an obviously key-related message. Fix: `cp` the real key file in from another checkout with the real key set, then re-run `git update-index --skip-worktree` on the copy in the new worktree.
- `Resources/ThunderforestAPIKey_dev.txt`/`ThunderforestAPIKey_live.txt` (the Thunderforest tile-provider key, used by the Map screen's OSM Standard/Cycle Map styles) follow the identical pattern and are subject to the identical rules above — same `skip-worktree` flagging, same never-`git add -f`, and the same new-worktree gotcha (a fresh worktree gets the tracked placeholder `YOUR_THUNDERFOREST_API_KEY_HERE`, not a real key from another checkout).

## Branching

Never commit directly to `main`. Use at least a branch for minor work (docs-only tweaks, one-line fixes); prefer a git worktree for everything else, so the change is isolated from whatever else is checked out in the primary working directory.

## Before finishing any change

Work through `docs/REVIEW_CHECKLIST.md`. In particular: **`docs/SPEC.md` must be updated in the same commit** as any change that adds/removes/materially changes a screen, ViewModel contract, API endpoint, persistence schema, or cross-cutting pattern. This is not optional — an out-of-date spec is worse than no spec, because future agents will trust it.
