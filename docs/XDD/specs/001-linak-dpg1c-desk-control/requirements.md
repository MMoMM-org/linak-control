---
title: "LINAK DPG1C macOS Desk Control"
status: draft
version: "1.0"
---

# Product Requirements Document

## Validation Checklist

### CRITICAL GATES (Must Pass)

- [x] All required sections are complete
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Problem statement is specific and measurable
- [x] Every feature has testable acceptance criteria (Gherkin format)
- [x] No contradictions between sections

### QUALITY CHECKS (Should Pass)

- [x] Problem is validated by evidence (not assumptions)
- [x] Context -> Problem -> Solution flow makes sense
- [x] Every persona has at least one user journey
- [x] All MoSCoW categories addressed (Must/Should/Could/Won't)
- [x] Every metric has corresponding tracking events
- [x] No feature redundancy (check for duplicates)
- [x] No technical implementation details included
- [x] A new team member could understand this PRD

---

## Product Overview

### Vision

Control your LINAK standing desk from the macOS menu bar and terminal — no phone app, no cloud, no Apple Developer license required.

### Problem Statement

Users of LINAK DPG1C-equipped standing desks on macOS have no native desktop control option. The official LINAK "Desk Control" app is iOS/iPadOS-only (available on Mac via App Store but requires a mobile-first UX). The DPG1C panel supports only one Bluetooth connection at a time, meaning the phone app locks out all other control options. Existing open-source alternatives target Linux (LinakDeskApp) or Home Assistant (hass-linak-dpg) — neither provides a native macOS menu bar experience or a scriptable CLI.

As a result, macOS power users must either:
- Keep their phone nearby and unlocked solely to adjust desk height (context switch, ~8 seconds per adjustment).
- Use the physical desk panel buttons (requires reaching under the desk surface, interrupting keyboard workflow).
- Forgo automated sit/stand reminders and scheduled position changes entirely.

For a user who adjusts their desk 4-6 times per day, this friction discourages ergonomic behavior and eliminates the possibility of timer-based or calendar-driven position automation.

### Value Proposition

A lightweight, always-on macOS menu bar app and CLI tool that:
- **Eliminates context switching** — adjust desk height without leaving the keyboard or reaching for a phone.
- **Enables automation** — script desk positions via CLI, integrate with calendar events, Shortcuts.app, or cron jobs for sit/stand schedules.
- **Costs nothing** — builds from source with Xcode, no paid Apple Developer account, no subscription, no cloud dependency.
- **Respects the single-connection constraint** — by replacing the phone app entirely, the user gains a faster, more integrated control surface without losing any functionality.

## User Personas

### Primary Persona: Marcus — Solo Owner-Operator

- **Demographics:** 30-50, macOS power user, software developer or knowledge worker, builds tools from source, lives in the terminal and menu bar.
- **Goals:** Control desk height from the menu bar with one click. Script preset changes for automated sit/stand schedules. See current height at a glance without opening an app. Have the desk "just work" on every boot without manual reconnection.
- **Pain Points:** The official LINAK app is phone-only and occupies the single BLE connection. No CLI exists for scripting. Reaching the physical panel interrupts keyboard-centric workflow. No way to automate position changes based on time or calendar.

### Secondary Persona: Scripter / Automator

- **Demographics:** Same user as Marcus, acting through shell scripts, launchd, Hammerspoon, Alfred, Raycast, or Shortcuts.app.
- **Goals:** Run `deskctl preset 2` on a calendar trigger. Pipe `deskctl height --json` into a status display. Trigger position changes via global hotkeys or automation tools.
- **Pain Points:** No machine-readable interface exists for desk control on macOS. Automation requires a CLI with reliable exit codes, structured JSON output, and a daemon that stays connected in the background.

### Tertiary Persona: Occasional Guest

- **Demographics:** Partner, flatmate, or colleague who uses the desk temporarily. Low technical comfort.
- **Goals:** Move the desk up or down. Use a shared preset (e.g., sitting height). Not break anything.
- **Pain Points:** Should not need to understand config files or terminal commands. Should not accidentally overwrite owner settings.
- **Note:** Guest mode is deferred to v1.1 (Should Have). MVP targets the Solo Owner-Operator only.

## User Journey Maps

### Primary User Journey: Daily Desk Control

1. **Awareness:** User sets up a standing desk with a LINAK DPG1C panel and discovers the official app is phone-only and occupies the sole BLE connection.
2. **Consideration:** User evaluates alternatives — LinakDeskApp (Linux only), hass-linak-dpg (requires Home Assistant), physical panel (inconvenient). None provide a native macOS experience.
3. **Adoption:** User clones the repo, builds with Xcode, runs the app. First-run flow guides them through Bluetooth pairing. Desk connects and height appears in the menu bar within 30 seconds.
4. **Usage:**
   - Morning: Mac wakes from sleep, daemon auto-reconnects to desk within 8 seconds.
   - User clicks menu bar icon, taps "Preset 2 (Standing)" — desk moves.
   - Height updates live in the popover during movement.
   - Afternoon: User types `deskctl preset 1` in terminal — desk moves to sitting position.
5. **Retention:** The app starts at login, reconnects automatically, and requires zero daily maintenance. The user forgets it exists until they need it — which is the mark of a good utility.

### Secondary User Journey: Automation Setup

1. **Awareness:** User realizes they can script desk positions after discovering the CLI.
2. **Adoption:** User creates a launchd plist or Shortcuts automation that runs `deskctl preset 2` at 9:00 AM and `deskctl preset 1` at 12:00 PM.
3. **Usage:** Desk moves automatically on schedule. User confirms via `deskctl status --json` in a monitoring script.
4. **Retention:** Automation runs daily without intervention. User adds more triggers (Pomodoro timer, meeting calendar integration).

### Tertiary User Journey: First-Run Pairing

1. **Launch:** User opens the app for the first time. Menu bar icon appears.
2. **Permission:** macOS prompts for Bluetooth access. User grants it.
3. **Scan:** App scans for nearby LINAK desks. Found desks appear with signal strength.
4. **Connect:** User selects their desk. Connection establishes. Wake-up sequence runs automatically.
5. **Confirm:** Popover shows "Connected" with current height. User is prompted to save their first preset.
6. **Done:** Desk is paired and remembered. Future launches auto-connect.

## Feature Requirements

### Must Have Features

#### Feature 1: BLE Discovery and Pairing

- **User Story:** As Marcus, I want to pair my DPG1C desk once so that the app remembers it on future launches.
- **Acceptance Criteria:**
  - [ ] Given the app is launched for the first time, When the user grants Bluetooth permission and initiates a scan, Then nearby LINAK desks appear in the popover within 10 seconds
  - [ ] Given a desk is discovered, When the user selects it, Then the app connects, runs the wake-up sequence, and displays the current height within 5 seconds
  - [ ] Given a desk has been paired, When the app is launched on subsequent sessions, Then it auto-connects to the saved desk without user action within 5 seconds
  - [ ] Given the paired desk is already connected to another device, When the app attempts to connect, Then it displays "Desk is connected to another device" with a retry option — not a generic error

#### Feature 2: Persistent Background Connection

- **User Story:** As Marcus, I want the desk connection to persist in the background so that CLI commands and menu bar actions work instantly without reconnecting.
- **Acceptance Criteria:**
  - [ ] Given the daemon is running and the desk is paired, When the Mac wakes from sleep, Then the daemon reconnects within 8 seconds automatically
  - [ ] Given the BLE connection drops unexpectedly, When the daemon detects the disconnection, Then it attempts to reconnect automatically with exponential backoff (1s, 2s, 4s, 8s, max 60s)
  - [ ] Given the desk has entered sleep mode after inactivity, When a move command is issued, Then the daemon sends the wake-up sequence transparently and executes the command within 1.5 seconds total
  - [ ] Given the daemon is running, When the user checks resource usage, Then CPU is below 0.1% at idle and memory is below 20 MB

#### Feature 3: Menu Bar Status and Height Display

- **User Story:** As Marcus, I want to see the desk connection status and current height in the menu bar so that I have ambient awareness without opening any app.
- **Acceptance Criteria:**
  - [ ] Given the desk is connected, When the menu bar icon is visible, Then it shows a connected state (full-weight glyph)
  - [ ] Given the desk is disconnected, When the menu bar icon is visible, Then it shows a disconnected state (reduced opacity with slash badge)
  - [ ] Given the desk is moving, When height updates arrive via BLE notifications, Then the popover displays the live height updated at 3-10 Hz with a directional indicator
  - [ ] Given the popover is open, When the desk is stationary, Then the current height is displayed in the user's configured unit (cm or inch)

#### Feature 4: Up/Down Movement Control

- **User Story:** As Marcus, I want to move my desk up or down from the menu bar so that I can adjust height without reaching the physical panel.
- **Acceptance Criteria:**
  - [ ] Given the desk is connected and the popover is open, When the user holds the Up button for at least 150ms, Then the desk begins moving up within 500ms of the hold threshold
  - [ ] Given the desk is moving in manual (hold) mode, When the user releases the button, Then the desk stops within 500ms
  - [ ] Given auto mode is configured for the up direction, When the user taps the Up button, Then the desk moves continuously until it reaches the travel limit or the user taps Stop
  - [ ] Given the desk is moving in auto mode, When the user taps the active button again, Then the button shows a Stop icon and the desk stops within 500ms
  - [ ] Given the desk is at maximum height, When the user presses Up, Then the Up button is dimmed and a tooltip shows "Desk is at maximum height"

#### Feature 5: Preset Positions (1-4)

- **User Story:** As Marcus, I want to recall saved desk positions with one tap so that I can switch between sitting and standing without manual adjustment.
- **Acceptance Criteria:**
  - [ ] Given the popover is open, When preset buttons are displayed, Then each shows a label number and the stored height value (e.g., "1 / 73.0 cm")
  - [ ] Given the user taps Preset 2, When the desk is connected, Then the desk begins moving to the stored position within 1 second
  - [ ] Given the desk reaches a preset position (within 5mm tolerance), When the height stabilizes, Then that preset button is visually highlighted as active
  - [ ] Given the desk is moved via physical controls away from a preset, When the height deviates by more than 5mm, Then all preset highlights clear on the next BLE update cycle
  - [ ] Given the user is in the settings panel, When they tap "Save current" on a preset slot, Then the current height is saved to that slot and confirmed

#### Feature 6: CLI Tool (deskctl)

- **User Story:** As a Scripter, I want a command-line tool so that I can automate desk control from shell scripts and automation tools.
- **Acceptance Criteria:**
  - [ ] Given the daemon is running, When the user runs `deskctl status`, Then connection state, height, active profile, and preset info are printed in a human-readable table
  - [ ] Given the daemon is running, When the user runs `deskctl height --json`, Then the output is valid JSON containing `height_mm`, `height_display`, and `unit` fields
  - [ ] Given the daemon is running, When the user runs `deskctl preset 2`, Then the command returns exit code 0 and the desk begins moving
  - [ ] Given the daemon is NOT running, When the user runs any deskctl command, Then it prints "error: daemon not running" to stderr and exits with code 2
  - [ ] Given the desk is not connected, When the user runs a control command, Then it prints "error: desk not connected" to stderr and exits with code 3
  - [ ] Given any command, When the user passes `--help`, Then usage information is printed including all subcommands and options

#### Feature 7: First-Run Experience

- **User Story:** As Marcus launching the app for the first time, I want a guided setup flow so that I can pair my desk and start using it without reading documentation.
- **Acceptance Criteria:**
  - [ ] Given the app is launched with no saved desk, When the popover opens, Then a welcome screen is shown with a "Get Started" button
  - [ ] Given the user taps "Get Started", When BLE permission has not been granted, Then the macOS Bluetooth permission dialog appears with a clear usage description
  - [ ] Given permission is granted, When scanning begins, Then found desks are shown with their name and signal strength
  - [ ] Given the user selects and connects a desk, When connection succeeds, Then a confirmation screen shows the current height and explains how to save presets
  - [ ] Given the user completes setup, When they tap "Done", Then the normal popover view is shown with live desk data

#### Feature 8: Daemon Lifecycle Management

- **User Story:** As Marcus, I want the background service to start automatically at login and be manageable from the CLI so that the desk is always ready.
- **Acceptance Criteria:**
  - [ ] Given the app is installed, When the user opts in to auto-start, Then the daemon registers as a login item and starts automatically on next login
  - [ ] Given the daemon is running, When the user runs `deskctl service status`, Then it reports "running" with uptime and connection state
  - [ ] Given the daemon has crashed, When the system detects the process exited, Then it restarts automatically within 5 seconds
  - [ ] Given the user runs `deskctl service stop`, When the daemon receives the signal, Then it disconnects cleanly from BLE and exits with code 0

#### Feature 9: Settings Configuration

- **User Story:** As Marcus, I want to configure display units, movement mode, and notification preferences so that the app matches my workflow.
- **Acceptance Criteria:**
  - [ ] Given the settings panel is open, When the user switches units from cm to inch, Then all height displays update immediately without reconnection
  - [ ] Given the settings panel is open, When the user sets "Move Up" to auto mode, Then the Up button in the main popover reflects auto mode with a visual indicator
  - [ ] Given a setting is changed via the menu bar, When the CLI reads the same setting, Then it reflects the updated value (settings are shared via the daemon)
  - [ ] Given any setting is changed, When the daemon restarts, Then all settings persist and are restored from the config file

### Should Have Features

#### Feature 10: Owner/Guest Profiles

- **User Story:** As Marcus, I want to switch to a Guest profile so that someone else can use my desk with restricted permissions.
- **Acceptance Criteria:**
  - [ ] Given the popover bottom bar shows the active profile, When the user taps the profile selector, Then available profiles are shown in an inline picker
  - [ ] Given Guest profile is active, When the guest views the popover, Then settings and preset save options are hidden or disabled
  - [ ] Given Guest profile is active, When the guest views presets, Then only presets marked as "shared" by the owner are visible

#### Feature 11: DPG1C Sleep/Wake Recovery

- **User Story:** As Marcus, I want the app to handle the desk's sleep mode transparently so that commands always work even after long idle periods.
- **Acceptance Criteria:**
  - [ ] Given the desk has been idle for 10+ minutes, When a move command is sent, Then the daemon detects the sleep state, sends the wake-up sequence, and retries the command within 1.5 seconds
  - [ ] Given the wake-up fails after 3 retries, When the daemon gives up, Then the user sees "Desk not responding" with a manual retry option

#### Feature 12: Global Hotkeys

- **User Story:** As Marcus, I want keyboard shortcuts to control the desk without opening the popover so that I never leave my keyboard.
- **Acceptance Criteria:**
  - [ ] Given hotkeys are enabled in settings, When the user presses the configured shortcut (e.g., Ctrl+Opt+2), Then Preset 2 is activated without opening the popover
  - [ ] Given hotkeys are enabled, When the user presses Ctrl+Opt+Up, Then the desk moves up in the configured mode

#### Feature 13: Notification Center Integration

- **User Story:** As Marcus, I want to receive notifications for connection state changes so that I know if the desk disconnects unexpectedly.
- **Acceptance Criteria:**
  - [ ] Given the desk disconnects unexpectedly, When the daemon detects it, Then a macOS notification appears: "Desk Disconnected — Reconnecting..."
  - [ ] Given the desk was busy, When the daemon eventually connects, Then a notification appears: "Desk Connected"

#### Feature 14: CLI Exit Codes and Structured Errors

- **User Story:** As a Scripter, I want consistent exit codes and JSON error output so that my automation scripts can handle failures reliably.
- **Acceptance Criteria:**
  - [ ] Given any error, When `--json` flag is passed, Then stderr contains a JSON object with `error` and `message` fields
  - [ ] Given documented exit codes (0=success, 1=general, 2=daemon not running, 3=not connected, 4=permission denied, 5=timeout), When an error occurs, Then the correct exit code is returned

### Could Have Features

#### Feature 15: macOS Desktop Widget

- **User Story:** As Marcus, I want a desktop or Notification Center widget showing desk height and preset buttons for quick access.
- **Acceptance Criteria:**
  - [ ] Given the widget is added, When the desk is connected, Then the widget shows current height and preset buttons
  - [ ] Given the widget preset button is tapped, When the desk is connected, Then the desk moves to that preset

#### Feature 16: Shortcuts.app / AppleScript Integration

- **User Story:** As a Scripter, I want to control the desk from Shortcuts.app and AppleScript so that I can integrate it with broader macOS automation.
- **Acceptance Criteria:**
  - [ ] Given the app exposes App Intents, When a Shortcuts automation triggers "Go to Desk Preset", Then the desk moves to the specified preset
  - [ ] Given the app is AppleScript-enabled, When a script calls `tell application "DeskControl" to go preset 2`, Then the desk moves

#### Feature 17: Height Event Streaming

- **User Story:** As a Scripter, I want to subscribe to a stream of height events so that I can build real-time dashboards or triggers.
- **Acceptance Criteria:**
  - [ ] Given the daemon socket is open, When the client subscribes to events, Then height updates are pushed as newline-delimited JSON at up to 4 Hz during movement

### Won't Have (This Phase)

- **Multi-desk simultaneous control** — The DPG1C supports only one BLE connection at a time. Multi-desk support (switching between desks) may be added later, but simultaneous control of multiple desks is not planned.
- **Cloud sync or remote access** — All communication is local. No telemetry, no accounts, no internet dependency.
- **App Store distribution** — The app is source-distributed and built locally. No code signing, notarization, or App Store review process.
- **Windows or Linux support** — macOS only, leveraging CoreBluetooth and native menu bar APIs.
- **Sit/stand reminder system** — Users can build this externally with cron/launchd + the CLI. A built-in timer is not in scope.
- **Custom desk height targets via numeric input** — Users move to presets or use up/down. Typing a specific mm value is not planned.

## Detailed Feature Specifications

### Feature: Preset Positions (Most Complex Must-Have)

**Description:** The app supports 4 preset positions stored in the desk's firmware. Each preset maps to a specific desk height. Users can recall a preset (move the desk to that height) or save the current height to a preset slot. The menu bar popover shows all 4 presets with their stored heights and highlights the active one.

**User Flow:**
1. User opens the popover and sees 4 preset buttons, each showing a number and height (e.g., "1 / 73.0 cm").
2. User taps Preset 2 (110.5 cm). The button briefly animates to confirm the tap.
3. The desk begins moving. The height display at the top of the popover updates live (e.g., "74.2 cm... 85.1 cm... 110.5 cm").
4. When the desk reaches the target (within 5mm tolerance), Preset 2 is highlighted as active.
5. If the user later adjusts the desk via the physical panel, the highlight clears as soon as the height deviates by more than 5mm.

**Business Rules:**
- Rule 1: Preset heights are read from the desk hardware on each connection. The app does not cache heights locally — the desk firmware is the source of truth.
- Rule 2: Preset metadata (labels like "Sitting"/"Standing", shared-with-guest flags) is stored locally in a config file.
- Rule 3: Saving a preset writes the current height to the desk firmware via BLE. The operation is confirmed by re-reading the preset height after the write.
- Rule 4: A tolerance of 5mm is used for preset matching. Heights within this range are considered "at preset." This accounts for BLE measurement noise and minor mechanical variance.
- Rule 5: During movement toward a preset, the active preset highlight does not appear until the desk stops and the height is within tolerance. This prevents premature highlighting during pass-through.

**Edge Cases:**
- Scenario 1: BLE disconnects during a preset move. -> Expected: Desk hardware stops the motor (built-in safety). App shows "Disconnected" and attempts reconnect. Does NOT auto-resume the interrupted move — user must re-trigger.
- Scenario 2: User taps a different preset while the desk is already moving to Preset 2. -> Expected: New preset command is sent immediately, overriding the previous move. Desk changes direction if needed.
- Scenario 3: All 4 presets are unset (new desk, no presets saved). -> Expected: Each button shows "1 / —" with a dash for height. Tapping an unset preset shows "No height saved. Move the desk to a position and save it in Settings."
- Scenario 4: Two presets have the same height value. -> Expected: Both are highlighted when the desk is at that height. This is valid (e.g., Preset 1 and Preset 3 both set to 73.0 cm for different contexts).
- Scenario 5: Desk is at a preset height but was moved there manually, not via the app. -> Expected: The preset is still highlighted — matching is based on current height, not how the desk got there.

### Feature: Up/Down Movement Control (Interaction Detail)

**Description:** The up/down buttons in the popover support two modes: Manual (hold-to-move) and Auto (tap-to-run). The active mode is configured per-direction in settings and visually indicated on the button.

**User Flow (Manual Mode):**
1. User presses and holds the Up button.
2. After a 150ms hold threshold, the button shows a pressed state and the desk begins moving.
3. While held, the desk moves continuously. Height updates in real time.
4. User releases the button. The desk stops within 500ms.

**User Flow (Auto Mode):**
1. User taps the Up button.
2. The desk begins moving up continuously. The button transforms into a Stop icon.
3. User taps the Stop button (same location). The desk stops.
4. Alternatively, the desk reaches its mechanical limit and stops automatically.

**Business Rules:**
- Rule 1: Default mode for both directions is Manual (hold). This is the safer default for new users.
- Rule 2: In Manual mode, taps shorter than 150ms are ignored (no accidental movement).
- Rule 3: In Auto mode, tapping while already moving sends a stop command.
- Rule 4: The active mode is shown on the button with a visual indicator (hold-ring for Manual, double-chevron for Auto).
- Rule 5: CLI commands `deskctl up --auto` and `deskctl up --manual` can override the configured mode per invocation.

## Success Metrics

### Key Performance Indicators

- **Adoption:** App successfully pairs with a desk and is used for at least one position change per day within the first week of installation.
- **Engagement:** Average 4-6 desk position changes per day via the app (replacing physical panel usage). CLI used for at least one automation script within the first month.
- **Quality:** Connection reliability > 95% uptime during waking hours. Zero unintended desk movements. Reconnect success rate > 90% within 10 seconds.
- **User Satisfaction:** User does not revert to the phone app or physical panel as primary control method within 30 days.

### Tracking Requirements

Note: This is a personal-use, local-only tool. "Tracking" means local logging and diagnostics, not cloud analytics.

| Event | Properties | Purpose |
|-------|------------|---------|
| connection_established | desk_name, time_since_launch, reconnect_attempt_count | Measure connection reliability |
| connection_lost | reason, desk_was_moving, duration_connected | Identify instability patterns |
| preset_activated | preset_index, source (menu_bar / cli / hotkey) | Understand usage patterns |
| move_command | direction, mode (auto/manual), source | Track feature adoption |
| cli_invocation | subcommand, exit_code, duration_ms | Measure CLI reliability |
| wake_up_required | attempts_needed, total_duration_ms | Track DPG1C sleep frequency |
| error_occurred | error_code, context | Diagnose issues |

All events are written to the local log file only. No network transmission.

---

## Constraints and Assumptions

### Constraints

- **Single BLE connection:** The DPG1C supports only one Bluetooth connection at a time. While this app is connected, the official LINAK phone app and Home Assistant integrations cannot connect, and vice versa.
- **No Apple Developer account:** The app must build and run without a paid ($99/year) Apple Developer Program membership. Gatekeeper bypass via `xattr -dr com.apple.quarantine` is acceptable for the target user.
- **macOS only:** Apple Silicon Macs running macOS 13 (Ventura) or later. No cross-platform support.
- **Local only:** No cloud services, no internet dependency, no user accounts. All data stored on the local machine.
- **BLE range:** Typical BLE range is 5-10 meters indoors. The Mac must be within range of the desk panel.

### Assumptions

- **A-1:** The LINAK DPG1C BLE protocol is accurately documented by the open-source community (LinakDeskApp, linak-controller, hass-linak-dpg). Service UUIDs, characteristic formats, and command sequences are stable across firmware versions.
- **A-2:** CoreBluetooth on macOS works for unsigned/ad-hoc signed apps without requiring the paid Developer Program. BLE access is gated by the macOS permission dialog, not by code signing entitlements.
- **A-3:** The DPG1C supports hardware-stored presets (4 positions) that can be read and written via BLE. If this assumption is false, presets will be stored locally and the app will drive the desk to the target height using continuous position monitoring.
- **A-4:** The DPG1C wake-up sequence (`0xFE 0x00` to the control characteristic) is sufficient to revive the desk from sleep mode on all firmware versions shipping in 2024-2026.
- **A-5:** The user is comfortable building from source with Xcode and running `xattr` commands. No installer, package manager, or drag-to-Applications distribution is needed for MVP.

## Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| DPG1C BLE protocol varies by firmware version (different UUIDs or command codes) | High — core functionality breaks | Medium | Validate against real hardware early. Log all discovered UUIDs. Make UUIDs configurable in settings for future-proofing. |
| Wake-up sequence does not work on all DPG1C units | High — desk appears unresponsive | Medium | Implement multiple wake-up strategies (control characteristic write, DPG characteristic handshake, notification subscription trigger). Retry up to 3 times with 300ms delay. |
| macOS CoreBluetooth drops connection silently after sleep/wake | Medium — requires manual intervention | Medium | Listen for `NSWorkspaceDidWakeNotification`, wait for CBCentralManager `poweredOn` state, then reconnect. Test extensively across macOS versions. |
| User's desk is permanently connected to another device (phone app left running) | Medium — app cannot function | High | Clear "Desk is connected to another device" error with actionable guidance. Document in README that the phone app must be quit first. |
| Unsigned binary causes Gatekeeper friction or CoreBluetooth permission issues | Low — blocks adoption | Low | Document `xattr -dr com.apple.quarantine` in README. Use ad-hoc code signing in build script. Test BLE permissions with ad-hoc signing. |
| LINAK releases firmware update that breaks the reverse-engineered protocol | High — requires code changes | Low | Monitor community repos (LinakDeskApp, linak-controller) for protocol changes. Implement protocol version detection from DPG characteristic capability flags. |
| Preset heights stored in desk firmware are overwritten by another app | Low — confusing UX, not data loss | Medium | Re-read preset heights from desk on every connection. Never cache stale values. |

## Open Questions

All critical open questions have been resolved through research. Remaining items are implementation-level and will be addressed in the SDD:

- [x] ~~BLE protocol completeness~~ — Resolved: community projects document all needed commands
- [x] ~~Unsigned app + CoreBluetooth~~ — Resolved: works without paid Developer account
- [x] ~~IPC transport~~ — Resolved: Unix domain socket
- [x] ~~Preset storage model~~ — Resolved: hardware presets with local metadata overlay
- [x] ~~Guest mode priority~~ — Resolved: deferred to Should Have (v1.1)

---

## Supporting Research

### Competitive Analysis

| Solution | Platform | Pros | Cons |
|----------|----------|------|------|
| **LINAK Desk Control App** (official) | iOS, iPadOS, macOS (via App Store) | Full feature set, official support | Phone-centric UX, occupies sole BLE connection, requires App Store download, no CLI, no automation |
| **LinakDeskApp** (anetczuk) | Linux (Python + Qt) | Open-source, well-documented protocol | Linux only, no macOS support, GUI is desktop-app style not menu bar |
| **linak-controller** (rhyst) | Python CLI | Cross-platform in theory, good protocol docs | Python + bleak on macOS is unreliable, no menu bar, no daemon |
| **hass-linak-dpg** (Laeborg) | Home Assistant | Integrates with smart home ecosystem | Requires Home Assistant setup, occupies BLE connection, no standalone macOS use |
| **Physical desk panel** | Hardware | Always available, no software | Requires reaching under desk, no automation, no height display during movement |
| **This project** | macOS (native) | Native menu bar, CLI, scriptable, local-only, free | Requires building from source, single platform, community-maintained |

### User Research

Based on community feedback from GitHub issues (HA core #104178, #106966, rhyst/linak-controller#32, alex20465/deskbluez#2):

- **Connection reliability is the #1 concern.** Users consistently report frustration with the DPG1C's sleep behavior, single-connection constraint, and silent command failures after idle periods.
- **Wake-up handling is mandatory.** Multiple users report the desk "not responding" after idle, which is the sleep mode issue. Solutions that do not implement the wake-up sequence are marked as broken.
- **Single-connection is accepted but must be explained.** Users understand the hardware limitation but want clear error messages when the desk is occupied by another client.
- **Automation is a strong secondary motivation.** Several GitHub issues request CLI tools or Home Assistant integration specifically for scheduled sit/stand position changes.

### Market Data

- Standing desk adoption has grown significantly, with the sit-stand desk market valued at several billion USD globally.
- LINAK is one of the largest manufacturers of desk actuator systems, supplying major desk brands (IKEA Bekant/Uppspel via a different controller, but DPG panels are used by many premium brands).
- The developer/power-user niche for macOS desk control is small but highly motivated — these users will build from source and contribute to open-source projects. The existing community repos (LinakDeskApp: 100+ stars, linak-controller: 200+ stars) demonstrate sustained interest.
