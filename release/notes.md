# Drift 1.0.0

Drift 1.0.0 is the first release signed with an Apple Developer ID and notarized by Apple.

- macOS now opens Drift without the Gatekeeper warning. You no longer need to Control-click **Open** or use **Open Anyway** in System Settings.
- Both the app and the DMG carry a stapled notarization ticket, so the first launch passes Gatekeeper even when you are offline.
- Updating from 0.1.6 or earlier works as usual through **Check for Updates**. Because the code-signing identity changed, you need to grant Drift Accessibility access once more after the update. Use **Open System Settings** in Drift and drag the app into the list. If an older Drift entry is still listed, remove it with the **−** button first.
