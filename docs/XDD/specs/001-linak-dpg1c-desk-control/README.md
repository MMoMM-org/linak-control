# Specification: 001-linak-dpg1c-desk-control

## Status

| Field | Value |
|-------|-------|
| **Created** | 2026-04-01 |
| **Current Phase** | Ready |
| **Last Updated** | 2026-04-01 |

## Documents

| Document | Status | Notes |
|----------|--------|-------|
| requirements.md | completed | 17 features, 48 acceptance criteria, all sections complete |
| solution.md | completed | 7 ADRs confirmed, all sections complete |
| plan/ | completed | 7 phases, 43 tasks, dependency graph defined |

**Status values**: `pending` | `in_progress` | `completed` | `skipped`

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-01 | Spec initialized from existing linak-control-spec.md | User has a detailed specification document that needs to be analyzed and formalized into PRD → SDD → PLAN |
| 2026-04-01 | Guest mode deferred to Should Have (v1.1) | MVP targets solo owner-operator only; reduces complexity |
| 2026-04-01 | Unix domain socket chosen for IPC | Simpler, more secure than HTTP; no port conflicts; socket permissions enforce access |
| 2026-04-01 | Widget listed as Could Have | Focus on menu bar + CLI for MVP |
| 2026-04-01 | PRD completed with 6-perspective research | Requirements, Technical, Security, Performance, Integration, UX agents all contributed |
| 2026-04-01 | Two-zone menu bar design approved | Zone 1 (desk icon) opens full popover; Zone 2 (active preset + height) opens quick-switch dropdown for one-click preset changes |
| 2026-04-01 | UI mockups created (mockups.md) | ASCII mockups for all screens: main popover, movement states, first-run flow, settings, CLI output, menu bar zones |
| 2026-04-01 | SDD completed with 7 ADRs confirmed | ADR-1: single process, ADR-2: Unix socket IPC, ADR-3: Swift actor, ADR-4: HW presets as truth, ADR-5: SMAppService, ADR-6: two-zone menu bar (two NSStatusItems), ADR-7: no SPM package |
| 2026-04-01 | Implementation plan completed | 7 phases, 43 tasks, phases 4+5 parallelizable, all 48 PRD acceptance criteria mapped to tasks |
| 2026-04-01 | Post-review fixes applied (23 findings) | H1: crash restart → login-item restart; H2: conditional heartbeat (10 min idle); H3: profiles.json → config.json; H4: remove IPC subscribe; H5: add BLEControllerProtocol; M1: standardize on LinakControl; M2: CLI fire-and-forget; M3: typed IPC enums; M4: socket lifecycle; M5: remove getSettings/setSettings; +Clock injection, +64KB payload cap, +height bounds check |

## Context

macOS menu bar app + CLI for controlling LINAK DPG1C standing desks via Bluetooth Low Energy. Source spec: `linak-control-spec.md` (root). Targets Apple Silicon, no App Store distribution, local build only.

---
*This file is managed by the xdd-meta skill.*
