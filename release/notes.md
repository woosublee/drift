# Drift 0.1.3

Drift 0.1.3 improves the menu bar popover’s clarity, sizing, and interaction safety.

- Adds contextual help for Smart Motion and Silent Mode while keeping the two settings independent.
- Disables click-position actions when Click Mode is None without deleting the saved position, and keeps the popover available during position selection.
- Expands and contracts the popover with conditional stop controls while preserving scrolling on shorter displays.
- Refreshes Launch at Login state when the popover opens and shows feedback only after an attempted setting change fails.
- Reworks the application footer into a compact adaptive layout for normal and larger accessibility text.
- Consumes the first outside click, reconciles shield coverage across displays, and cleans up popover or selection state on application deactivation.
- On first launch, macOS Gatekeeper may block the app because it is self-signed. On macOS 13 and 14, open it from Finder with Control-click, choose **Open**, then confirm **Open** in the prompt. On macOS 15 or later, try launching the app once, then go to **System Settings > Privacy & Security > Security** and choose **Open Anyway**.
