# Drift 0.1.5

Drift 0.1.5 fixes the update check reporting a false failure and the update dialogs not responding to clicks.

- Stops showing "The update check failed." when the app is actually already up to date, and clears the message when a new check starts.
- Fixes the menu bar popover's outside-click shield from blocking clicks on Sparkle's update dialogs (e.g. "You're up to date!").
- On first launch, macOS Gatekeeper may block the app because it is self-signed. On macOS 13 and 14, open it from Finder with Control-click, choose **Open**, then confirm **Open** in the prompt. On macOS 15 or later, try launching the app once, then go to **System Settings > Privacy & Security > Security** and choose **Open Anyway**.
