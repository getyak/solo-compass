---
name: solo-compass
description: Repository-specific development guide for the solo-compass monorepo. Use when implementing, debugging, reviewing, or testing changes in this repository, especially SwiftUI iOS work, TypeScript workspace changes, schema parity updates, localization, or XcodeGen project changes.
---

# Solo Compass Development Guide

## Product Boundaries

- Treat `Experience`, not `Place`, as the core product unit.
- Keep the map as the iOS home screen. Do not introduce tabs or drawers without an explicit product decision.
- Keep `packages/core` platform-agnostic and free of UI dependencies.
- Apps may import shared packages; apps must not import each other.

Read `docs/PRODUCT_BRIEF.md`, `docs/PHASES.md`, and `docs/ARCHITECTURE.md` before changing product behavior or package boundaries.

## TypeScript Conventions

- Preserve `strict: true` and `noUncheckedIndexedAccess: true`.
- Use branded ID types instead of plain strings.
- Represent coordinates as `[longitude, latitude]`; convert external `[latitude, longitude]` values at integration boundaries.
- Store timestamps as ISO 8601 UTC strings and convert to local time for display.
- Prefer `interface` for object shapes and `type` for unions.

## iOS Conventions

- The native app lives under `apps/ios/SoloCompass`.
- Use SwiftUI and MapKit with MVVM-style boundaries: `Views/`, `ViewModels/`, `Models/`, `Services/`, and `Persistence/`.
- Preserve complete Swift concurrency checking. Follow existing `@MainActor` and `@Observable` patterns for services and view models.
- Avoid force unwraps in production paths; prefer `guard let` and explicit error handling.
- Route user-facing text through `NSLocalizedString` and update both English and Simplified Chinese resources.
- Add focused XCTest coverage under `apps/ios/SoloCompass/Tests`.
- Treat `apps/ios/SoloCompass.xcodeproj` as generated output. Update `apps/ios/project.yml` and run `xcodegen` when project configuration changes.

## Verification

Run the checks that match the changed surface:

```bash
# TypeScript workspace
pnpm typecheck
pnpm test

# Shared schema parity
pnpm parity:check

# Localization
pnpm localization:check
./scripts/check-hardcoded-strings.sh
./scripts/check-zh-punctuation.sh

# iOS project generation, build, and tests
cd apps/ios
xcodegen
xcodebuild build \
  -project SoloCompass.xcodeproj -scheme SoloCompass \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcodebuild test \
  -project SoloCompass.xcodeproj -scheme SoloCompass \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

- Run `pnpm parity:check` for shared model or schema changes.
- Run iOS build and relevant XCTest cases for native changes.
- Visually verify iOS UI changes in Simulator; previews alone are insufficient.

## Git Workflow

- Preserve unrelated worktree changes.
- Use conventional commits with lowercase scopes, such as `fix(ios): restore map sheet presentation`.
- Keep commit subjects at or below 72 characters.
