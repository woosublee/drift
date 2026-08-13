# Drift Dev manual verification checklist

Run this checklist against the development bundle built and installed with:

```text
make verify-app CONFIGURATION=debug BUILD_DIR=/tmp/drift-bundles/dev CODESIGN_IDENTITY=Drift
~/Applications/Drift Dev.app
com.woosublee.drift.dev
```

Every item is intentionally unchecked until a user performs it on macOS.

- [ ] **Menu bar only / no Dock icon**  
  Setup: launch `~/Applications/Drift Dev.app`.  
  Action: open and close the installed Drift Dev popover, then inspect the menu bar, Dock, and Force Quit window.  
  Expected: the popover shows the visible title `Drift Dev` and visible action `Quit Drift Dev`; the popover remains fully on-screen; Drift Dev remains running after opening and closing the popover; Drift Dev has a menu-bar icon with no Dock icon or normal app window.

- [ ] **Compact card layout in Active and Inactive states**  
  Setup: launch `~/Applications/Drift Dev.app` and leave Accessibility in its current user-controlled state.  
  Action: inspect the popover while Inactive, then turn Active on and inspect it again.  
  Expected: the popover is approximately 410pt wide and uses compact, consistent native macOS spacing; all nine cards (Status, Smart Motion, Silent Mode, Movement, Clicking, Stop Conditions, Behavior, Accessibility, and Application) remain present in both states; no repeated uppercase section-title row appears; Smart Motion and Silent Mode are independent cards, and Movement and Clicking require no disclosure click; the runtime name is `Drift Dev`; the status label, dot, shortcut, and Active switch remain legible; Active, Smart Motion, Silent Mode, Deactivate At, Battery Level, and Launch at Login are conventional native macOS switches, not checkbox-style toggles; Start Moving After, Move Every, Click Mode, and Deactivate At time controls share one visible width; body text and native switches remain readable; cards, rows, and full-width actions use compact, consistent vertical rhythm.

- [ ] **Development and production identity isolation**
  Setup: build both variants and launch `~/Applications/Drift Dev.app`.
  Action: inspect Bundle IDs, UserDefaults domains, Login Items, and Accessibility entries.
  Expected: development uses `com.woosublee.drift.dev`; production uses `com.woosublee.drift`; changing development settings or permission does not change production.

- [ ] **Accessibility blocked and recovery flow**  
  Setup: remove Drift Dev from Accessibility permission in System Settings.  
  Action: turn Active on, then use `Open System Settings`, grant permission, and retry.  
  Expected: Drift Dev requests the initial system prompt when access is first requested; activation is blocked with an explanation until permission is granted; after the dev-specific grant, the app shows `Accessibility Ready`.

- [ ] **Independent Silent Mode and Smart Motion combinations**<br>
  Setup: grant Accessibility, leave Click Mode as None, set a short practical idle delay, and use a single connected display.<br>
  Action: observe at least one idle cycle for each combination: both off, Silent Mode only, Smart Motion only, and both on.<br>
  Expected: both off uses distance-based linear movement lasting about 0.25–0.8 seconds with configured timing; Silent Mode only makes the minimal out-and-back movement without a noticeable visible jump; Smart Motion only follows bounded varied paths with varied timing; both on retains the minimal Silent movement while timing still varies.

- [ ] **Smart Motion click variation**<br>
  Setup: select a safe click position in a non-destructive app and use a click mode.<br>
  Action: compare a completed click cycle with Smart Motion off and on.<br>
  Expected: both settings move to the saved point, click, and then depart to a safe random position on the same display; Smart Motion off uses a distance-based linear path with no hold, while Smart Motion on uses a varied path and a short varied hold before release.

- [ ] **Physical mouse and keyboard idle reset**  
  Setup: activate Drift Dev and wait partway through `Start Moving After`.  
  Action: move the physical mouse, press a key, and wait again.  
  Expected: each real input resets the idle timer; Drift Dev waits the full configured delay before another cycle.

- [ ] **Physical input cancellation during movement**<br>
  Setup: turn Silent Mode off, turn Smart Motion on, and use a short idle delay.<br>
  Action: move the physical mouse or press a key while Drift Dev is moving.<br>
  Expected: the active sequence stops promptly and user control takes priority.

- [ ] **Left, Right, Alternating click**  
  Setup: select a safe click position in a non-destructive app, then exercise Left, Right, and Alternating modes separately.  
  Action: allow one successful sequence for each mode.  
  Expected: Left and Right generate their matching click; Alternating switches button only after a successful sequence.

- [ ] **Move away after clicking**<br>
  Setup: set a safe click position away from the current pointer and select a click mode.<br>
  Action: allow one click sequence to complete without input.<br>
  Expected: Drift Dev moves to the saved point, clicks, then moves to a different position within the same display's inset visible area and remains at least 96 points from the click position when the display permits it.

- [ ] **Invalid or disconnected display click position**  
  Setup: save a click point on a secondary display, then disconnect that display.  
  Action: wait for a would-be click sequence.  
  Expected: Drift Dev identifies the position as invalid and sends no click event until a valid point is selected.

- [ ] **Sleep, wake, and screensaver reset**  
  Setup: activate Drift Dev and begin waiting for idle.  
  Action: put displays to sleep and wake them; separately start and stop the screensaver.  
  Expected: active movement is cancelled while suspended and Drift Dev waits the full initial delay after resume.

- [ ] **Schedule stop by selected weekday and time**  
  Setup: enable `Deactivate At`, choose a near-future time and the current weekday, then activate Drift Dev.  
  Action: wait through the selected time.  
  Expected: Drift Dev becomes inactive once, saves the inactive intent, and shows the schedule stop HUD.

- [ ] **Conditional Stop Conditions controls and Reduce Motion**  
  Setup: open the Drift Dev popover, with Deactivate At and Battery Level initially off.  
  Action: toggle each condition on and off once with Reduce Motion disabled, then repeat with Reduce Motion enabled in System Settings.  
  Expected: Deactivate At and Battery Level switches share the same trailing edge; time and weekday controls exist only while Deactivate At is enabled; Battery Threshold exists only while Battery Level is enabled; battery percentage and Stepper remain readable and aligned; transitions are restrained normally and do not use pronounced motion when Reduce Motion is enabled.

- [ ] **Battery stop on battery and no stop while charging**  
  Setup: on a battery-equipped Mac, enable Battery Level at a threshold at or above the current percentage.  
  Action: test once on battery power and once while charging or on external power.  
  Expected: Drift Dev stops only on non-charging battery power at or below the threshold.

- [ ] **Launch at Login and previous Active restoration**  
  Setup: enable Launch at Login and make Drift Dev Active, then log out and back in or restart.  
  Action: inspect the restored app state; repeat after turning Drift Dev inactive.  
  Expected: Launch at Login is a native switch; system registration status matches the setting and only the prior active intent is restored; if macOS rejects or requires approval, the switch returns to the observed system state and one relevant inline error is shown.

- [ ] **Default and recorded shortcut**  
  Setup: activate Drift Dev with the default Command-Control-D shortcut, then record a different valid shortcut.  
  Action: use both shortcuts after recording.  
  Expected: each registered shortcut toggles Active/Inactive; a rejected shortcut reports its error without disabling menu-bar control.

- [ ] **Active/Inactive and stop-reason HUD**  
  Setup: use the global shortcut and separately trigger a schedule or battery stop.  
  Action: observe the HUD after each transition.  
  Expected: Active/Inactive HUD text is brief and the automatic-stop HUD identifies its reason.

- [ ] **Unconfigured Check for Updates disabled state**  
  Setup: use the development bundle built without deployment feed metadata.  
  Action: open the Drift Dev popover and inspect the application section.  
  Expected: `Check for Updates…` is disabled with `Updates aren’t configured for this build.` and opening the app starts no update check.

- [ ] **Light, dark, short-screen, and footer presentation**  
  Setup: inspect Drift Dev once in light appearance and once in dark appearance; use a short display or reduced resolution if available; compare the same setting state under a consistent display scale in light and dark appearance.
  Action: compare the popover width and vertical rhythm across light, dark, and short-screen conditions, then scroll from the Status card to the Application card.
  Expected: the width and vertical density remain compact and consistent; adaptive card surfaces, switch tracks/thumbs, and semantic states remain legible in light and dark appearance; enabled Stop Conditions add only their actual controls with no reserved placeholder space; no grid row, control, action, or larger-text content clips or overlaps; the popover stays fully on-screen; vertical scrolling reaches the Application footer, including `Check for Updates…`, `Quit Drift Dev`, and `Drift Dev 0.1.0`.

- [ ] **Aligned controls with keyboard and VoiceOver**<br>
  Setup: open Drift Dev with Full Keyboard Access and VoiceOver available; do not change Accessibility approval unless intentionally testing that existing checklist item.<br>
  Action: traverse Active, Smart Motion, Silent Mode, Movement, Clicking, Deactivate At, Battery Level, Launch at Login, shortcut controls, and Application actions using Tab/Shift-Tab and VoiceOver; press Space on each switch in a safe state.<br>
  Expected: each Boolean control is announced once as a labelled native switch with its current state; Smart Motion and Silent Mode are announced as separate controls; no duplicate static-label stop precedes the switch; Battery Threshold is announced once as an adjustable control with the current percentage; ordinary row labels remain available; focus order follows the visual card order; rows grow for larger text without clipping or overlap.

- [ ] **Clean quit with no residual process**  
  Setup: activate Drift Dev, open the popover, and begin a selectable operation if practical.  
  Action: choose `Quit Drift Dev`, then inspect Activity Monitor or `ps`.  
  Expected: overlays, shortcut, timers, cursor work, HUD, updater state, and status item clean up; no Drift process remains.
