# Decisions — linak-control
<!-- Architecture choices and rationale. Updated: 2026-04-01 -->
<!-- What goes here: why we chose X over Y, ADR links, significant tradeoff choices -->
<!-- Format: YYYY-MM-DD — Decision: [what] — Rationale: [why] -->

## 2026-04-01 — Xcode project via xcodegen for .app bundle

**Decision**: Use `project.yml` + `xcodegen` to generate `LinakControl.xcodeproj` alongside the Swift Package.

**Rationale**: SPM `executableTarget` produces raw binaries. A proper `.app` bundle is required for:
- `LSUIElement` / `NSBluetoothAlwaysUsageDescription` via embedded Info.plist
- CoreBluetooth entitlements
- `SMAppService` login item (requires bundle identifier)

**Approach**:
- `project.yml` at repo root, scheme `LinakControlApp`, ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`)
- `LinakControl/Package.swift` exposes `LinakControlKit` as an explicit library product so Xcode can link against it
- xcodegen 2.x bug: omits `package` back-reference in `XCSwiftPackageProductDependency`; fixed via `postGenCommand` sed patch in `project.yml`
- `make xcode-build` / `make xcode-build-debug` for app bundle; `make build` remains for CLI (`deskctl`) via SPM
- deskctl stays as a raw SPM binary — no bundle needed
