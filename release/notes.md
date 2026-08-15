# Drift 0.1.4

Drift 0.1.4 improves menu bar responsiveness by removing redundant state and icon work.

- Avoids republishing unchanged activity state for physical input while preserving motion cancellation and idle-delay resets.
- Updates the menu bar symbol only when the rendered glyph changes, including active phases that share the same icon.
- Caches rendered SVG assets and system symbols so repeated phase changes do not parse or rebuild the same image.
- On first launch, macOS Gatekeeper may block the app because it is self-signed. On macOS 13 and 14, open it from Finder with Control-click, choose **Open**, then confirm **Open** in the prompt. On macOS 15 or later, try launching the app once, then go to **System Settings > Privacy & Security > Security** and choose **Open Anyway**.
