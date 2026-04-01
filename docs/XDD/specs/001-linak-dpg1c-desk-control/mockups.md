# UI Mockups — LINAK DPG1C Desk Control

## Menu Bar — Two Zones

The menu bar has two clickable zones separated by a visual divider:

1. **Desk icon** (left) — opens the full popover
2. **Active preset** (right) — shows current preset, click opens a mini dropdown to quick-switch

```
Zone 1 (popover)    Zone 2 (preset dropdown)
     ↓                    ↓
┌─────────┬─────────────────┐
│   ╥     │    2  110.5 cm  │    ← Connected, at Preset 2
└─────────┴─────────────────┘

┌─────────┬─────────────────┐
│   ╥     │    ── ·  85.3   │    ← Connected, not at any preset
└─────────┴─────────────────┘

┌─────────┬─────────────────┐
│   ╥̸     │    --           │    ← Disconnected
└─────────┴─────────────────┘

┌─────────┬─────────────────┐
│   ╥↕    │   →2  85.3→110.5│    ← Moving to Preset 2
└─────────┴─────────────────┘
```

### Preset Quick-Switch Dropdown

Clicking the preset zone (Zone 2) opens a compact dropdown:

```
┌─────────────────────┐
│  1    73.0 cm       │
│ [2   110.5 cm]  ✓   │  ← current/active, highlighted
│  3    90.0 cm       │
│  4   120.0 cm       │
└─────────────────────┘
```

- Clicking a preset immediately moves the desk (no confirmation).
- The active preset has a checkmark. During movement, the target shows a `→` indicator.
- If no preset is active, no checkmark is shown.

```
During movement to Preset 1:

┌─────────────────────┐
│ →1    73.0 cm   ... │  ← target, animating
│  2   110.5 cm       │
│  3    90.0 cm       │
│  4   120.0 cm       │
└─────────────────────┘
```

---

## Main Popover — Connected, Idle

```
╭──────────────────────────────╮
│                              │
│        110.5 cm              │
│        ─────────             │
│        current height        │
│                              │
├──────────────────────────────┤
│                              │
│     ┌──────────────────┐     │
│     │        ▲         │     │  ← Up button
│     │      (hold)      │     │    mode indicator: "hold" or "auto"
│     └──────────────────┘     │
│                              │
│     ┌──────────────────┐     │
│     │        ▼         │     │  ← Down button
│     │      (auto)      │     │
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│  Presets                     │
│                              │
│  ┌──────┐ ┌──────┐          │
│  │  1   │ │ [2]  │          │  ← Preset 2 highlighted (active)
│  │73.0cm│ │110.5 │          │
│  └──────┘ └──────┘          │
│  ┌──────┐ ┌──────┐          │
│  │  3   │ │  4   │          │
│  │90.0cm│ │120.0 │          │
│  └──────┘ └──────┘          │
│                              │
├──────────────────────────────┤
│  ⚙ Settings     Marcus (👤) │  ← Profile + settings access
╰──────────────────────────────╯
```

---

## Main Popover — During Movement (to Preset 2)

```
╭──────────────────────────────╮
│                              │
│      ↑ 85.3 cm               │
│      ─────────               │
│      moving to 110.5 cm     │
│      ━━━━━━━━░░░░  68%      │  ← progress bar
│                              │
├──────────────────────────────┤
│                              │
│     ┌──────────────────┐     │
│     │        ▲         │     │
│     │      (hold)      │     │
│     └──────────────────┘     │
│                              │
│     ┌──────────────────┐     │
│     │        ▼         │     │
│     │      (auto)      │     │
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│  Presets                     │
│                              │
│  ┌──────┐ ┌──────┐          │
│  │  1   │ │ (2)  │          │  ← Preset 2 pulsing (target)
│  │73.0cm│ │110.5 │          │
│  └──────┘ └──────┘          │
│  ┌──────┐ ┌──────┐          │
│  │  3   │ │  4   │          │
│  │90.0cm│ │120.0 │          │
│  └──────┘ └──────┘          │
│                              │
├──────────────────────────────┤
│  ⚙ Settings     Marcus (👤) │
╰──────────────────────────────╯
```

---

## Main Popover — Auto Mode Up (Stop Button)

```
╭──────────────────────────────╮
│                              │
│      ↑ 92.1 cm               │
│      ─────────               │
│      moving up               │
│                              │
├──────────────────────────────┤
│                              │
│     ┌──────────────────┐     │
│     │      ■ Stop      │     │  ← Up button transforms to Stop
│     └──────────────────┘     │
│                              │
│     ┌──────────────────┐     │
│     │        ▼         │     │  ← Down dimmed while moving up
│     │      (auto)      │     │
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│  ...                         │
╰──────────────────────────────╯
```

---

## Main Popover — Disconnected

```
╭──────────────────────────────╮
│                              │
│      ⚠ Disconnected          │
│      ─────────────           │
│      Reconnecting... (3s)    │
│                              │
│     ┌──────────────────┐     │
│     │   Retry Now      │     │
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│                              │
│     ┌──────────────────┐     │
│     │        ▲         │     │  ← dimmed / disabled
│     └──────────────────┘     │
│     ┌──────────────────┐     │
│     │        ▼         │     │  ← dimmed / disabled
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│  Presets (dimmed)            │
│  ┌──────┐ ┌──────┐          │
│  │  1   │ │  2   │          │
│  │ ---  │ │ ---  │          │
│  └──────┘ └──────┘          │
│  ┌──────┐ ┌──────┐          │
│  │  3   │ │  4   │          │
│  │ ---  │ │ ---  │          │
│  └──────┘ └──────┘          │
│                              │
├──────────────────────────────┤
│  ⚙ Settings     Marcus (👤) │
╰──────────────────────────────╯
```

---

## Main Popover — Desk Busy (Another Device Connected)

```
╭──────────────────────────────╮
│                              │
│      ✕ Desk Busy             │
│      ─────────               │
│      Connected to another    │
│      device. Quit the LINAK  │
│      app on your phone and   │
│      try again.              │
│                              │
│     ┌──────────────────┐     │
│     │   Retry           │     │
│     └──────────────────┘     │
│                              │
├──────────────────────────────┤
│  ⚙ Settings     Marcus (👤) │
╰──────────────────────────────╯
```

---

## First-Run — Welcome

```
╭──────────────────────────────╮
│                              │
│      ╥  DeskControl          │
│                              │
│   Control your LINAK desk    │
│   from the menu bar.         │
│                              │
│   We'll scan for your desk   │
│   and pair it now.           │
│                              │
│     ┌──────────────────┐     │
│     │   Get Started     │     │
│     └──────────────────┘     │
│                              │
╰──────────────────────────────╯
```

---

## First-Run — Scanning

```
╭──────────────────────────────╮
│                              │
│   Scanning for desks...      │
│   ◠◡◠ (spinner)              │
│                              │
├──────────────────────────────┤
│                              │
│   📶 ███░  LINAK DPG1C       │  ← strong signal
│                              │
│   📶 █░░░  LINAK Desk-B12    │  ← weak signal
│                              │
├──────────────────────────────┤
│                              │
│  Tap a desk to connect.      │
│                              │
╰──────────────────────────────╯
```

---

## First-Run — Connected / Setup Complete

```
╭──────────────────────────────╮
│                              │
│      ✓ Connected!            │
│                              │
│      LINAK DPG1C             │
│      Current height: 73.0 cm │
│                              │
│   Tip: Save your current     │
│   position as a preset in    │
│   Settings.                  │
│                              │
│     ┌──────────────────┐     │
│     │      Done         │     │
│     └──────────────────┘     │
│                              │
╰──────────────────────────────╯
```

---

## Settings Panel

```
╭──────────────────────────────╮
│  ← Back           Settings   │
├──────────────────────────────┤
│                              │
│  Display Unit                │
│  ┌──────┐ ┌──────┐          │
│  │ [cm] │ │ inch │          │  ← segmented control
│  └──────┘ └──────┘          │
│                              │
├──────────────────────────────┤
│                              │
│  Movement Mode               │
│                              │
│  Up:   ┌──────┐ ┌──────┐   │
│        │[hold]│ │ auto │   │
│        └──────┘ └──────┘   │
│                              │
│  Down: ┌──────┐ ┌──────┐   │
│        │ hold │ │[auto]│   │
│        └──────┘ └──────┘   │
│                              │
├──────────────────────────────┤
│                              │
│  Presets                     │
│  1: 73.0 cm   [Save current] │
│  2: 110.5 cm  [Save current] │
│  3: 90.0 cm   [Save current] │
│  4: 120.0 cm  [Save current] │
│                              │
├──────────────────────────────┤
│                              │
│  Connection                  │
│  Desk: LINAK DPG1C    ✓     │
│  ┌──────────────────┐       │
│  │  Forget & Re-scan │       │
│  └──────────────────┘       │
│                              │
├──────────────────────────────┤
│                              │
│  ☐ Start at login            │
│  ☐ Global hotkeys            │
│                              │
├──────────────────────────────┤
│                              │
│  About DeskControl v1.0      │
│  ┌──────────────────┐       │
│  │  Quit             │       │
│  └──────────────────┘       │
│                              │
╰──────────────────────────────╯
```

---

## CLI Output Examples

### `deskctl status`

```
DeskControl Daemon
  Status:     running (uptime: 2h 14m)
  Connection: connected
  Desk:       LINAK DPG1C
  Height:     110.5 cm
  Profile:    Marcus (owner)
  Presets:    1=73.0cm  2=110.5cm*  3=90.0cm  4=120.0cm
                                  (* = active)
```

### `deskctl height --json`

```json
{
  "height_mm": 1105,
  "height_display": "110.5",
  "unit": "cm"
}
```

### `deskctl preset 2`

```
Moving to preset 2 (110.5 cm)...
Done.
```

### `deskctl service status`

```
Daemon: running (pid 1234, uptime 2h 14m)
Connection: connected to LINAK DPG1C
```

### Error states

```
$ deskctl up
error: daemon not running
(exit code 2)

$ deskctl preset 1
error: desk not connected — reconnecting...
(exit code 3)
```

---

## State Diagram — Button Modes

```
Manual (Hold) Mode:
  idle → [press 150ms+] → moving → [release] → idle
  idle → [tap <150ms]  → ignored

Auto (Tap) Mode:
  idle → [tap] → moving → [tap again] → idle
  idle → [tap] → moving → [limit reached] → idle
```

---

## Visual Legend

| Symbol | Meaning |
|--------|---------|
| `[x]` | Selected / active state |
| `(x)` | Pulsing / in-progress |
| `---` | No data / unavailable |
| `↑` / `↓` | Direction indicator |
| `███░░` | Signal strength bar |
| `━━━░░` | Progress bar |

---

## Notes for Discussion

1. **Popover vs. full menu**: Using an NSPopover (like Bartender, iStatMenus) rather than a flat NSMenu. Gives room for buttons, live updates, and the preset grid.

2. **Two-zone menu bar**: Desk icon (left) opens the full popover. Active preset (right) opens a mini dropdown for quick-switching between presets — the most common action gets a one-click shortcut without opening the full popover.

3. **Height display prominence**: The current height is the hero element at the top of the popover — large font, always visible. During movement it shows direction + live value + target.

4. **Progress bar during preset moves**: Optional — shows how far along the move is. Requires knowing the start and target height. Could be omitted for simplicity.

5. **Preset grid vs. list**: 2x2 grid in the popover keeps it compact. The menu bar dropdown uses a simple list (4 items). Which layout for the popover?

6. **Settings as a separate "page"**: Navigates within the same popover (push/pop) rather than opening a separate window. Keeps everything in one place.

7. **Profile selector**: Shown in the footer bar. For MVP (owner-only), this could just show "Marcus" without a switcher.
