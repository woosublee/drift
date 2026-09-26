# Drift 0.1.6

Drift 0.1.6 makes granting Accessibility access easier.

- **Open System Settings** now opens the Accessibility pane with a floating helper panel attached to the System Settings window. Drag Drift from the panel into the list to grant access, with no need to hunt for the app or use the `+` button.
- The settings button no longer shows the separate macOS permission prompt on top of the helper panel. The first-launch prompt is unchanged.
- On first launch, macOS Gatekeeper may block the app because it is self-signed. On macOS 13 and 14, open it from Finder with Control-click, choose **Open**, then confirm **Open** in the prompt. On macOS 15 or later, try launching the app once, then go to **System Settings > Privacy & Security > Security** and choose **Open Anyway**.
