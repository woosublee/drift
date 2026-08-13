# Drift 0.1.1

Drift 0.1.1 fixes startup failures in the self-signed release and refreshes the app's visual identity.

- Fixes the launch failure that occurred when Hardened Runtime Library Validation blocked Sparkle.
- Adds startup smoke testing for the app mounted from the release DMG.
- Adds the new Drift app icon and active/inactive menu bar icons.
- Strengthens release verification for startup grace periods and malformed app icons.
- On first launch, macOS Gatekeeper may block the app because it is self-signed. On macOS 13 and 14, open it from Finder with Control-click, choose **Open**, then confirm **Open** in the prompt. On macOS 15 or later, try launching the app once, then go to **System Settings > Privacy & Security > Security** and choose **Open Anyway**.
