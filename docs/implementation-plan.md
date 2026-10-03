# Amid implementation plan

Goal: satisfy all locally achievable v0.1 requirements in PRD.md, with measured limitations and a runnable native app. Authority: GOAL.md; routine local decisions and delegation are approved.

1. Install and seed pinned Serel. Verify both adapters, payload hashes, complete bank, drift and preserved input documents.
2. Prove Phase 0 using libproc/Mach/public Foundation APIs, owned Node/Python/Swift fixtures, explicit coverage and identity tests. Resolve storage and safe action feasibility before enabling destructive UI.
3. Implement native SwiftUI/AppKit menu panel and seven destinations. Verify actual bundle launch and rendered views, with keyboard/accessibility inspection where consent permits.
4. Implement opt-in encrypted aggregates, retention/rollup/cap, rules/cooldowns, exclusions/aliases and explicit diagnostics. Verify failure, missing-data and synthetic-soak paths.
5. Integrate and review; run unit and real OS fixtures, privacy inspection/traffic checks and overhead measurements. Fix failures, document per-requirement evidence and Kit maps.
6. Package ad-hoc local build, publish repeatable local commands and prepare external release gates; refresh one resumable checkpoint.

## Ownership

Root integration owner controls Models.swift, Package.swift, UI, packaging, memory and integration. Bounded GPT-6.1 sol agents own collectors/C bridge, history/alerts/storage, and action feasibility/fixtures. No concurrent edits to shared models without integration-owner coordination.

## Architecture choices and self-review (Claude unavailable)

Use SwiftPM with no downloaded runtime libraries. Public Apple CryptoKit AES-GCM with a random per-install Keychain key is the candidate storage design; encrypt before atomic replacement and never serialize plaintext journals. Aggregate buckets preserve min/max/count/coverage. Explicit keys/settings cannot make collection start before onboarding.

Privacy review: no arguments, environments, source content, clipboard, payloads, socket probes or model APIs. Collector metadata paths are volatile unless needed in encrypted aliases. Exclusions apply before persistence. Redacted diagnostics preview is separate from export.

Action review: PID/start time is not an atomic process handle. A matching executable is insufficient evidence of a development server. Disable any adapter lacking acceptable assurance; no fallback force kill. Owned test servers only.

Risks: public API availability on macOS 15/current newer OS, Keychain consent failure, partial OS visibility, activity interference and UI permissions. Current host is arm64 macOS 27.0.1, Swift 6.4, SDK 27.0; minimum OS, reference M1 8GB, two-week beta and public signing remain unverified.

Independent cross-tool review was unavailable. Recorded review uses explicitly labeled self-review and same-model delegated review; no independent review is claimed.

## Excluded actions

No remote/push/PR/publication, legal agreement, machine consent, privileged tool install or edits to another app. No change to PRD scope.
