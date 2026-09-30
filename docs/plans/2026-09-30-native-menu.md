# Native menu implementation plan

> Implementation workflow: use superpowers:executing-plans, with test-first verification and a final code review. The user approved this design and implementation in the conversation.

**Goal:** Replace the custom menu panel with a native macOS menu, move maintenance to Settings, and publish matching screenshots and a 1.0.1 installer.

**Architecture:** AppKit owns the status item and native menu. SwiftUI renders the small Settings window. A value-type presentation model distinguishes idle, preparing/installing, cleaning, and original-audio states; the existing C engine and routing behavior are preserved. The menu renderer is shared by the app, structural tests, and screenshot tooling.

**Tech stack:** Swift 6, AppKit, SwiftUI, Swift Testing, existing C/Core Audio engine, Python/Pillow artwork tooling.

## Approved design and acceptance criteria

- Noise Removal is the first command, with a native checkmark when enabled.
- A short, noninteractive status line distinguishes Not running, Removing noise, and Passing original audio. The actual input is shown while routing.
- Settings…, How to Use LucidMic, About LucidMic, and Quit LucidMic appear in separated groups. Settings and Quit use Command-comma and Command-Q.
- Launch at Login and driver maintenance move to Settings. Remove Virtual Microphone… explicitly confirms before stopping routing or requesting administrator access.
- Busy states prevent duplicate operations. Permission failures offer a relevant action; detailed errors remain accessible without making the menu excessively wide.
- Native keyboard handling, accessibility labels, light/dark appearance, and long device names are checked.
- README previews show the implemented menu in both appearances. Any staged preview uses the real renderer with an explicitly documented sample state and never claims to be a live call.
- Preserve the private repository, credits cleanup, dependency notices, and v1.0.0 release. Publish 1.0.1 for the changed UI.

## Task 1: Presentation and native menu

Files: new `Sources/LucidMic/MenuState.swift`, `Sources/LucidMic/NativeMenu.swift`, `Tests/LucidMicUITests/MenuTests.swift`; update `Package.swift`.

1. Add tests for idle versus passthrough, checkmarks, busy-state disabling, permission remediation, long microphone names, keyboard commands, and the absence of maintenance on the main menu.
2. Run `swift test --filter MenuTests` and record the expected failure before implementation.
3. Implement a compact state model and an AppKit menu with stable menu items updated in place.
4. Run the targeted tests to green.

## Task 2: Application and Settings integration

Files: `Sources/LucidMic/LucidMicApp.swift`; new `AppState.swift`, `SettingsView.swift`.

1. Move existing audio/application state into its own file. Replace ambiguous status strings with the presentation states; preserve denoiser, bypass, restoration, and device-selection behavior.
2. Connect the native status item and menu commands, with truthful icon/accessibility state.
3. Implement Settings using system controls, actual login-item state, driver status, and a confirmation before removal.
4. Provide local usage help and a native About panel.
5. Run `scripts/check.sh`, then exercise the launched app and native menu without changing microphone routing or login settings for the user.

## Task 3: Screenshots and documentation

Files: new `scripts/render-menu.swift` and `scripts/render-menu.sh`; `scripts/make-art.py`, `docs/assets/menu-{light,dark}.png`, `docs/assets/hero-{light,dark}.png`, `docs/assets/README.md`, `README.md`, `CHANGELOG.md`, `docs/releases/1.0.1.md`.

1. Render the real native menu's command structure in a deterministic sample state without opening the microphone. Verify the resulting pixels in both appearances.
2. Regenerate the framed README previews; preserve the Bilby-style layout and existing branding.
3. Update usage and release instructions for the new command and Settings structure.

## Task 4: Verify and publish 1.0.1

Files: version defaults in `scripts/build.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, and current-distribution metadata/notices as necessary.

1. Run format, lint, build, tests via `scripts/check.sh`, plus workflow validation and `git diff --check`.
2. Obtain a focused review of state transitions, menu behavior, and driver-removal confirmation; resolve blocking findings.
3. Build the 1.0.1 DMG and source archives; verify signatures, mounted app, checksums, architecture, and resource completeness.
4. Fast-forward main, push, and verify CI. Tag and publish the private release, checking uploaded asset hashes.
5. Install the verified app while preserving a backup; retain final artifacts in the primary workspace and clean the isolated worktree.

## Validation limits

Accessibility access was unavailable during research. Use direct AppKit menu inspection and the app's own renderer for automated checks; report any live interaction or screenshot limitations honestly. No real call recordings are needed.

Screen Recording is also disabled. The user explicitly approved rendered previews instead of desktop screenshots. The preview tool reads the real NSMenu items but illustrates their layout using system fonts and colors; assets and README label this accurately. The actual Settings view was separately rendered for visual checks. Independent review's Settings-refresh and application-keyboard findings were fixed and tested.
