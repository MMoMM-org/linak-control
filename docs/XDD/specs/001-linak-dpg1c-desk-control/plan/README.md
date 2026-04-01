---
title: "LINAK DPG1C macOS Desk Control"
status: draft
version: "1.0"
---

# Implementation Plan

## Validation Checklist

### CRITICAL GATES (Must Pass)

- [x] All `[NEEDS CLARIFICATION: ...]` markers have been addressed
- [x] All specification file paths are correct and exist
- [x] Each phase follows TDD: Prime → Test → Implement → Validate
- [x] Every task has verifiable success criteria
- [x] A developer could follow this plan independently

### QUALITY CHECKS (Should Pass)

- [x] Context priming section is complete
- [x] All implementation phases are defined with linked phase files
- [x] Dependencies between phases are clear (no circular dependencies)
- [x] Parallel work is properly tagged with `[parallel: true]`
- [x] Activity hints provided for specialist selection `[activity: type]`
- [x] Every phase references relevant SDD sections
- [x] Every test references PRD acceptance criteria
- [x] Integration & E2E tests defined in final phase
- [x] Project commands match actual project setup
- [x] All phase files exist and are linked from this manifest as `[Phase N: Title](phase-N.md)`

---

## Context Priming

*GATE: Read all files in this section before starting any implementation.*

**Specification**:

- `docs/XDD/specs/001-linak-dpg1c-desk-control/requirements.md` — Product Requirements (17 features, 48 acceptance criteria)
- `docs/XDD/specs/001-linak-dpg1c-desk-control/solution.md` — Solution Design (7 ADRs, BLE protocol, IPC spec, data models)
- `docs/XDD/specs/001-linak-dpg1c-desk-control/mockups.md` — Approved UI mockups (two-zone menu bar, popover, settings, first-run)

**Key Design Decisions**:

- **ADR-1**: Single Process — menu bar app IS the daemon; no separate binary
- **ADR-2**: Unix Domain Socket — length-prefixed JSON for CLI ↔ app IPC
- **ADR-3**: Swift Actor — `DeskManager` actor serializes all state access
- **ADR-4**: Hardware Presets — read from desk firmware on every connection, never cache
- **ADR-5**: SMAppService — login item registration (no LaunchAgent plist)
- **ADR-6**: Two-Zone Menu Bar — two NSStatusItems (desk icon + preset dropdown)
- **ADR-7**: No SPM Package — shared code via framework target or file inclusion

**Implementation Context**:

```bash
# Build
xcodebuild -scheme LinakControl -configuration Debug
xcodebuild -scheme LinakControl -configuration Release CODE_SIGN_IDENTITY="-"

# Test
xcodebuild test -scheme LinakControl -destination 'platform=macOS'

# Lint
swiftlint

# Run
open build/Build/Products/Debug/LinakControl.app
```

---

## Implementation Phases

Each phase is defined in a separate file. Tasks follow red-green-refactor: **Prime** (understand context), **Test** (red), **Implement** (green), **Validate** (refactor + verify).

> **Tracking Principle**: Track logical units that produce verifiable outcomes. The TDD cycle is the method, not separate tracked items.

- [ ] [Phase 1: Project Foundation & BLE Protocol](phase-1.md)
- [ ] [Phase 2: BLE Connection & Desk Management](phase-2.md)
- [ ] [Phase 3: IPC Layer](phase-3.md)
- [ ] [Phase 4: Menu Bar UI](phase-4.md)
- [ ] [Phase 5: CLI Tool (deskctl)](phase-5.md)
- [ ] [Phase 6: First-Run, Settings & Polish](phase-6.md)
- [ ] [Phase 7: Integration & E2E Validation](phase-7.md)

---

## Dependency Graph

```
Phase 1 (Foundation)
  ├──→ Phase 2 (BLE + DeskManager)
  │      ├──→ Phase 3 (IPC)
  │      │      ├──→ Phase 5 (CLI)
  │      │      └──→ Phase 4 (UI) [parallel with Phase 5]
  │      └──→ Phase 4 (UI)
  └──→ Phase 3 (IPC)
                 └──→ Phase 6 (First-Run, Settings)
                        └──→ Phase 7 (Integration & E2E)
```

Phases 4 and 5 can run in parallel after Phase 3 completes.

---

## Plan Verification

| Criterion | Status |
|-----------|--------|
| A developer can follow this plan without additional clarification | ✅ |
| Every task produces a verifiable deliverable | ✅ |
| All PRD acceptance criteria map to specific tasks | ✅ |
| All SDD components have implementation tasks | ✅ |
| Dependencies are explicit with no circular references | ✅ |
| Parallel opportunities are marked with `[parallel: true]` | ✅ |
| Each task has specification references `[ref: ...]` | ✅ |
| Project commands in Context Priming are accurate | ✅ |
| All phase files exist and are linked from this manifest as `[Phase N: Title](phase-N.md)` | ✅ |
