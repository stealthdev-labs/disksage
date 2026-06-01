# Contributing to DiskSage

Thanks for helping out! DiskSage is open-core — the whole app lives here — so
contributions of all sizes are welcome. The highest-value contributions are
usually **new cleanup categories** and **corrections to safety verdicts**, and
those are deliberately easy to make.

## Getting set up

```sh
git clone https://github.com/stealthdev-labs/disksage.git
cd opensoursedisk
swift build      # debug build
swift run        # launch the app
Scripts/test.sh  # run the test suite
```

You need macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
Full Xcode is optional.

## How the code is organized

```
Sources/DiskSage/
  App/      DiskSageApp (entry point) · AppState (observable app state) ·
            LicenseManager · Links
  Core/     DiskScanner (concurrent FS walk) · SafetyEngine (the advisor) ·
            Cleaner (move-to-Trash) · ByteFormat
  Models/   FileNode (the scanned tree) · Categories (FileKind, SafetyLevel,
            CleanupCategory)
  Views/    SwiftUI — SunburstView, ExploreView, CleanupView, InspectorView,
            SettingsView, WelcomeView, ScanningView, Theme
```

The two files worth understanding first:

- [`Models/Categories.swift`](Sources/DiskSage/Models/Categories.swift) —
  defines `CleanupCategory`, including each category's **title**, **plain-language
  explanation** (the advice the user reads), default **safety level**, icon, and
  whether it's eligible for hands-off auto-clean.
- [`Core/SafetyEngine.swift`](Sources/DiskSage/Core/SafetyEngine.swift) — maps
  real filesystem paths to categories and verdicts. This is the "AI".

## Adding a cleanup category

Say you want DiskSage to recognize **Deno's cache** at `~/Library/Caches/deno`.

1. **Add the case** to `CleanupCategory` in `Categories.swift`, and fill in the
   four `switch` statements the compiler will point you to:
   - `title` → `"Deno Cache"`
   - `explanation` → one or two sentences: *what it is and why it's safe*. This
     is the product. Be honest and specific.
   - `defaultSafety` → `.safe`, `.caution`, or leave it in the `default: .safe`
     bucket. Use `.caution` if it can hold data the user might not be able to
     regenerate.
   - `systemImage` → an SF Symbol (reuse an existing group if it fits).
   - `autoCleanEligible` → add the case to the `true` list **only** if it is
     unambiguously regenerable junk *and* rated `.safe`.

2. **Teach the engine the path.** In `SafetyEngine.specificCategory(path:name:isDirectory:)`,
   add a match:
   ```swift
   if path == cachesRoot + "/deno" { return .deno }
   ```

3. **Add a test** in `Tests/DiskSageTests/SafetyEngineTests.swift`:
   ```swift
   #expect(engine.specificCategory(path: HOME + "/Library/Caches/deno",
                                   name: "deno", isDirectory: true) == .deno)
   ```

4. Run `Scripts/test.sh` and you're done.

### The safety rule that must always hold

**Anything `autoCleanEligible` must be rated `.safe`.** A scheduled, unattended
sweep should never touch something the advisor itself flags for review. There's
a test enforcing exactly this (`CategoryInvariantTests`) — if you break it, the
suite fails.

## Correcting a verdict

If DiskSage rates something wrong, the fix usually lives in `SafetyEngine`
(`assess(...)` for the live verdict, `collectSuggestions(...)` for what shows up
in the Clean-up tab) or in a category's `defaultSafety`. Add a test that pins
the corrected behavior so it can't regress.

## Coding conventions

- Match the surrounding style. Comments explain **why**, not what.
- Keep `Core/` and `Models/` free of SwiftUI imports where practical — the logic
  is plain Swift and is what the tests exercise.
- DiskSage **never hard-deletes**. All removal goes through
  `FileManager.trashItem`. Don't introduce `removeItem` for user-facing cleanup.
- No network calls in the app. DiskSage is offline by design.

## Submitting a PR

1. Fork, branch, commit with a clear message.
2. Make sure `swift build` and `Scripts/test.sh` both pass.
3. Open a PR describing the change and, for new categories, *why the verdict is
   correct* (a link to docs or the tool's own description is great).

By contributing you agree your work is licensed under the [MIT License](LICENSE).
