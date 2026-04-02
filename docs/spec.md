# Linak DPG1C macOS Desk Control -- Specification

## 1. Goal and Scope

This document describes the **spec-driven design** of a macOS solution for controlling a height-adjustable desk with LINAK motors and a DPG1C control panel via Bluetooth.

The solution comprises:

- Menu bar app (Menu Bar App)
- Command-line interface (CLI)
- Optional: Widget (Desktop/Notification Widget)

The application is designed for **personal use** and should be usable **without a paid Apple Developer licence** where possible (local build, Gatekeeper bypass).

---

## 2. Constraints and Assumptions

- Target platform: macOS (Apple Silicon).
- Communication is exclusively local; no cloud dependencies.
- Bluetooth Low Energy (BLE) connection directly to the DPG1C desk panel.
- The DPG1C can only hold one Bluetooth connection at a time (iPhone/Mac/Home Assistant etc.).
- The app is intended for personal use; distribution via source code, not the App Store.

---

## 3. System Architecture (High Level)

### 3.1 Component Overview

1. **Core Service (Daemon / Background Process)**
   - Implements:
     - BLE handling (scan, pairing, connect, disconnect).
     - Desk protocol (up/down, presets, read height, auto-run behaviour).
     - Ownership/profile logic (owner/guest).
     - Persistence of settings and profiles.
   - Provides a **local JSON-based API** (e.g. via Unix socket or localhost HTTP).

2. **Menu Bar App**
   - UI client for the core service.
   - Display:
     - Connection status.
     - Current height.
     - Unit (cm/inch).
   - Controls:
     - Up/down (manual/auto).
     - Presets 1--4.
     - Owner/guest mode, units, auto-run configuration.

3. **CLI Tool (deskctl)**
   - Command-line tool using the same internal JSON API of the core service.
   - For scripting, automation, integration with other tools.

4. **Widget (optional)**
   - Widget extension that retrieves data from the core service via the JSON API.
   - Focus on height display and simple actions (preset or auto-move).

---

## 4. Functional Requirements

### 4.1 Bluetooth and Connection

**Features:**

- Desk discovery:
  - Scan for BLE devices with LINAK-typical services (based on reverse-engineering from open-source projects).
  - Display found desks with name/address in the menu bar app.

- Pairing and storage:
  - One-time pairing with the selected desk (DPG1C).
  - Storage of identity/address in the user profile (e.g. in a local config).

- Reconnect:
  - Automatic reconnection on core service start.
  - Manual "Reconnect" action via menu bar app or CLI.

- Conflict detection:
  - Detection when the desk is already connected to another client (DPG1C "busy"), displaying a corresponding status.

### 4.2 Up/Down Control

**Actions:**

- Manual movement:
  - `startUp`, `stopUp`, `startDown`, `stopDown`.
  - Implemented as BLE writes to specific characteristics per the community project protocol.

- Automatic movement (auto-run):
  - Modes:
    - `manual` (hold): moves only while the command is active.
    - `auto` (tap): moves continuously until the target is reached or stopped.
  - Configuration:
    - Configurable per direction (up/down) whether `auto` or `manual` is preferred.
    - Saved in a local settings file; optionally mapped to desk-side options if available.

**UI/CLI:**

- Menu bar app:
  - Buttons "up" and "down" with configurable behaviour (auto/manual).
- CLI:
  - `deskctl up [--auto|--manual]`
  - `deskctl down [--auto|--manual]`

### 4.3 Presets (4 Memory Positions)

**Features:**

- Recall presets 1--4:
  - `goPreset(1..4)` -- moves to defined height positions.
- Save presets (if protocol is known):
  - `savePreset(1..4)` -- saves the current height to a preset.

**UI/CLI:**

- Menu bar app:
  - Buttons "1", "2", "3", "4" with height readings from presets.
- CLI:
  - `deskctl preset <1-4>` -- recalls a preset.
  - `deskctl preset <1-4> --save` -- saves the current height as a preset (optional).

### 4.4 Height Display and Units

**Basis:**

- The desk typically reports height in an internal unit (presumably mm or steps).
- The core service converts to the desired display unit.

**Requirements:**

- Periodic or event-based height updates (polling e.g. every 1 s when connected).
- Configurable display unit:
  - `cm` (default).
  - `inch`.

**Conversion:**

- Internal:
  - `height_mm` as the base unit.
- Display:
  - cm: `height_cm = height_mm / 10.0`.
  - inch: `height_in = height_mm / 25.4`.

**UI/CLI:**

- Menu bar app:
  - Display e.g. "110.5 cm" or "43.5 in".
- CLI:
  - `deskctl height` -- text output.
  - `deskctl height --json` -- JSON with numeric height and unit.

### 4.5 Owner/Guest Concept

Since the desk panel itself has no real user roles, this concept is modelled **locally** within the application. The software always registers as owner on the desk panel.

**Profiles:**

- Owner:
  - Full control over:
    - Preset definitions (local metadata).
    - Default settings (unit, auto-run, selected desks).
  - Can mark presets as "shared" for guests.

- Guest:
  - May:
    - Move the desk up/down.
    - Select shared presets.
  - May not:
    - Change owner settings unless explicitly allowed.

**Persistence:**

- Local profiles (e.g. `profiles.json`) in the user directory.
- Example structure:
  ```json
  {
    "profiles": [
      {
        "name": "Marcus",
        "role": "owner",
        "defaultDesk": "Desk-1234",
        "unit": "cm",
        "autoRun": { "up": "manual", "down": "auto" }
      },
      {
        "name": "Guest",
        "role": "guest",
        "unit": "cm"
      }
    ],
    "activeProfile": "Marcus"
  }
  ```

**CLI/GUI:**

- `deskctl profile list`
- `deskctl profile set <name>`
- Menu bar app: dropdown "Owner / Guest / Select profile".

### 4.6 Configurable Automatic Movement

**Requirements:**

- The user can decide per action whether:
  - Auto-run (tap) or
  - Manual (hold)
  is used, provided this is compatible with the DPG behaviour.

**Design:**

- Global default settings (owner only).
- Per CLI call and UI action, the mode can be temporarily overridden (e.g. button "Auto Up").

---

## 5. Non-Functional Requirements

- **No paid Apple Developer licence required:**
  - The project must be buildable locally from source with Xcode.
  - The app may remain unsigned; usage is possible via Gatekeeper bypass.
- **Robustness:**
  - Clean error handling for:
    - Connection drops.
    - Unreachable desks.
    - Wake-up issues (some DPG1C desks go to sleep and need to be "woken").
- **Performance:**
  - Resource-efficient polling intervals.
  - Core service as a lightweight background process.
- **Logging:**
  - Configurable log levels (error, info, debug).
  - Optional logging of BLE frames for development purposes.

---

## 6. Internal JSON API (Draft, High Level)

The following endpoints are suggested and may later be formalised into an OpenAPI-style specification.

**Basis:**

- Transport:
  - Local: Unix socket or `http://127.0.0.1:<port>`.
- Format:
  - JSON for requests and responses.

### 6.1 Examples

#### GET /status

- Response:
  ```json
  {
    "connected": true,
    "deskName": "LINAK DPG1C",
    "height_mm": 1105,
    "height_display": "110.5 cm",
    "unit": "cm",
    "profile": "Marcus",
    "role": "owner"
  }
  ```

#### POST /move

- Request:
  ```json
  {
    "direction": "up",
    "mode": "auto"
  }
  ```
- Response:
  ```json
  { "ok": true }
  ```

#### POST /preset

- Request (recall):
  ```json
  {
    "index": 1,
    "action": "go"
  }
  ```
- Request (save):
  ```json
  {
    "index": 2,
    "action": "save"
  }
  ```

#### POST /settings

- Request:
  ```json
  {
    "unit": "inch",
    "autoRun": {
      "up": "manual",
      "down": "auto"
    }
  }
  ```

---

## 7. CLI Specification (Draft)

Command-line tool `deskctl`:

- `deskctl status`
  - Shows connection, active profile, height.

- `deskctl height [--json]`
  - Outputs current height.

- `deskctl up [--auto|--manual]`
- `deskctl down [--auto|--manual]`

- `deskctl preset <1-4> [--save]`

- `deskctl unit cm|inch`

- `deskctl profile list`
- `deskctl profile set <name>`

All commands use the JSON API of the core service internally.

---

## 8. Menu Bar App (UI Spec)

**Status display:**

- Icon (e.g. desk symbol).
- Colour/badge for:
  - Connected.
  - Disconnected.
  - Error status.

**Menu content:**

- Current height (e.g. "110.5 cm") shown with buttons only.
- Buttons:
  - "up" -- up (mode-sensitive: auto/manual).
  - "down" -- down.
  - "1", "2", "3", "4" -- presets.
    - Displayed as height; active button highlighted.
    - Height display during movement.
    - If the desk is not at a preset height (due to manual adjustment at the desk etc.), revert to button display.
- Settings submenu:
  - Preset / manual (up / down).
  - Unit: cm / inch.
  - Auto-run: up/down each auto/manual.
  - Active profile: owner/guest/others.
  - Select connected desk.

---

## 9. Widget (optional)

**Content:**

- Display:
  - "Desk: 110.5 cm".
- Actions (as permitted by the Widget API):
  - Tap: moves to the last used preset or toggles a simple move command.
  - Small buttons: Preset 1 / Auto Up / Auto Down (with platform limitations).
    - Similar to the menu bar app.

---

## 10. External References / Starting Points

### 10.1 Official LINAK Resources

- LINAK Desk Control App -- Product page
  https://www.linak.com/products/controls/desk-control-app/

- Desk Control App -- Apple App Store (iPhone / iPad / Apple Silicon Mac)
  https://apps.apple.com/de/app/desk-control/id1203254365

- Desk Control Basic Software -- PC/Mac
  https://www.linak-us.com/products/controls/desk-control-basic-software/

- DPG Desk Panels & Desk Control App -- User Manual (DE)
  https://cdn.linak.com/-/media/files/user-manual-source/de/deskline-dpg-desk-panels-und-desk-control-app-montageanleitung-dt.pdf

- DPG Desk Panels & Desk Control App -- User Manual (EN)
  https://cdn.linak.com/-/media/files/user-manual-source/en/deskline-dpg-desk-panels-and-desk-control-app-user-manual-eng.pdf

### 10.2 Open Source and Reverse Engineering

- **LinakDeskApp** -- Desktop app (Linux) with DPG1C support
  https://github.com/anetczuk/LinakDeskApp

- **linak-controller** -- Python script for controlling Linak desks
  https://github.com/rhyst/linak-controller

- **hass-linak-dpg** -- Home Assistant integration for DPG
  https://github.com/Laeborg/hass-linak-dpg

- **linak_desk** -- Home Assistant custom component
  https://github.com/mdrwiega/linak_desk

- Discussion/issue threads on DPG1C compatibility:
  - DPG1C support in `linak-controller`: https://github.com/rhyst/linak-controller/issues/32
  - DPG1C in Home Assistant (errors, "wake up"): https://github.com/home-assistant/core/issues/104178
  - Further DPG1C error reports: https://github.com/home-assistant/core/issues/106966
