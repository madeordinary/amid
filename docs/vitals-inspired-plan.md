# Vitals-inspired additions — implementation plan

Status: independently reviewed draft, **REVISE**, 2026-10-04; batch-one steps 1–4 amended 2026-10-14 from the [Fable 5.1 review and qualified next steps](vitals-inspired-review.md). The REVISE verdict covers only the earlier frozen draft, not these amendments. The startup settings race the review found was reproduced and fixed at `df61fae`. Batch-two steps 5–6 still need the review’s readout/layout corrections and owner presentation choices. No feature implementation has started. Baseline: public `3d966dd`, runtime source `df61fae`. The existing [acceptance gaps](handoff.md#what-remains) remain open; this plan does not waive them or authorize a binary release.

## Goal

Add persistent favorites, unified search, an opening-view preference, richer menu readouts and configurable Overview/menu layouts while preserving Amid's privacy, identity, storage and sampling contracts.

The owner requested these additions and asked for a plan before a new session. The defaults below remain concrete proposals. Claude Code Fable 5.1 reviewed the frozen draft with `--effort xhigh` and returned REVISE; source-supported risks, untested hypotheses and remaining owner decisions are separated in the linked review. Later edits are not covered by that verdict.

## Scope and existing behavior

Amid already has menu-to-application navigation, inline project ports, collapsible System details and icon/CPU/memory-pressure menu choices. Preserve these and their tests rather than rebuilding them. The five additions below are new work.

Expected implementation areas:

- `Sources/AmidCore/History/HistoryTypes.swift`: compatible encrypted preferences.
- `Sources/AmidApp/AppModel.swift`: presentation, preference saves and navigation.
- `Sources/AmidApp/AmidApp.swift`: commands, window-opening behavior and menu readouts.
- `Sources/AmidApp/GroupsScreen.swift`, `MenuPanel.swift`, `MainWindow.swift`, `OverviewPresentation.swift`, `SettingsScreen.swift` and `Formatting.swift`: native controls and displays.
- New small search/presentation types where useful; localizable strings; affected core/app tests.
- [Requirements](requirements.md), feature verification maps and source-scoped evidence after implementation.

Avoid collector, attribution, action, encryption or aggregate-storage redesign. Review any necessary deviation before implementation.

## Steps and acceptance checks

### 1. Add compatible preferences

Add only batch-one preferences now: app/project pins and the opening view, including Last used. Add readout and layout preferences with batch two. Store them in the existing encrypted settings path with compatible defaults: existing installations open to Overview with no pins. Unknown display identifiers must fall back safely; missing fields must not reset retention, aliases, exclusions or alert choices. Preserve the existing serialized/coalesced save behavior. New preference writers must use the load guard: refused while saved settings load, never merged over them.

A display-only save must not disturb History. In the model, a pending History reply is discarded whenever `settingsRevision` changes, and that revision also drives save coalescing. Scope History invalidation to history-affecting changes (retention and application/project exclusions) without weakening coalescing. In the store, `updateSettings` always clears the query cache, advances the store revision, re-runs retention enforcement and persists. A display-only save that advances the store revision between `metadata()` and `history()` can make a pending query fail as unavailable. Display-only saves must still commit durably; retention and exclusion changes must still invalidate immediately.

Use namespaced app/project identifiers for saved pins. Never save a raw PID as a durable favorite. Keep transient process search selections separate from preferences. No migration of history aggregate data is planned; review any schema-version change before applying it.

→ Verify: decode prior settings, round-trip new settings, handle unknown identifiers and rapid successive saves, and demonstrate ciphertext-only persistence with history Off as well as enabled. Add regressions that saving a pin or opening preference leaves loaded History unchanged and lets a pending query publish without “History measurements unavailable”, while retention and exclusion changes still invalidate. A preference write during settings load is refused. Existing key/store failure tests must remain valid.

### 2. Pin applications and projects

Add Pin/Unpin to application and project rows or inspectors through visible, keyboard-accessible controls. In the Applications and Projects lists, pinned live rows sort ahead of unpinned rows; each partition retains the active ordering.

Pinning never changes a ranking. Overview’s “Largest observed applications” and the menu panel’s “Top observed memory” stay memory-ranked and unchanged. Show pins in a separate, bounded Favorites section in Overview and the menu panel, labelled so that a small favorite cannot look like a top consumer. Preserve pins across relaunch and ordinary process churn. Do not manufacture a live row or zero measurements when a pinned entity is absent; provide a settings list for removing saved pins.

Refuse persistent pins for `process:` fallback applications, which identify a single process rather than a durable application. Pins are preferences: Clear History keeps them, as it keeps aliases. Omit pins from the diagnostics export. Aliases change labels, not pin identity. Separate worktrees remain separate projects. Pinning does not change grouping, collection coverage or stop eligibility.

→ Verify: pin/unpin, aliases, relaunch, absent/reappearing entities, refused `process:` pins, pins kept through Clear History and absent from diagnostics, worktree separation, deterministic ordering, and unchanged rankings and measured totals with pins present. Observe keyboard operation and clear Favorites/top-consumer labels in the native app.

### 3. Add unified search with Command-F

Provide one in-window search surface from every destination. Group results by Applications, Projects, Processes and Ports. Search current permitted names, aliases and listening-port numbers; do not read process arguments, environments or file contents. Existing destination filters may remain.

Compute results synchronously from the current accepted snapshot and groups while the surface is open, bounded per section with a count of further matches. Add no asynchronous search service, index or process destination. Use existing routes: an application or project result calls `openGroup`; a process or listener result opens the existing process inspector through `selectedProcess`. That inspector is a sheet on the main window, so the search surface must not be a modal sheet, or it must dismiss before setting `selectedProcess`.

Typing `3000` must expose each observed matching listener with its app/project context; a shared port must not collapse distinct owners. Navigate to the selected current entity and clear any local filter that would hide it. Preserve the selected History time range when navigating to an entity’s history.

Hold the highlighted result by identity (group ID, or full process identity for processes and listeners), not by row position, PID or port. Re-resolve it against current state on activation. If it exited or changed, show that it is unavailable; do not select a replacement. Enter opens a result, Escape dismisses and restores focus, and arrow keys navigate. Before onboarding or while locked, the surface must not reveal cleared/stale data. Search state joins the existing reset list: lock, sleep, Clear History and quit dismiss it and drop its results.

→ Verify: aliases and case-insensitive matching, no matches, app/project/process matches, multiple owners of one port, section bounds, process exit/PID reuse between highlight and activation, inspector opening for process and listener results, hidden-filter navigation, and lock/sleep/clear invalidation. Observe Command-F, result selection, Escape and focus restoration natively.

### 4. Choose where the window opens

Offer Overview, Applications, Projects, Ports, History, Alerts and Last used; default to Overview. Last used remembers the last content destination the user selected, excluding Settings and transient sheets.

Do not save Last used on every navigation. `saveSettings()` invalidates a running GUI benchmark and each save rewrites the encrypted manifest. Record the value in memory and persist it at bounded points that do not invalidate a benchmark: window close, application hide, lock or sleep, and quit. Quit needs an explicit save step, because `prepareToQuit` flushes the store without saving settings. An abrupt termination may lose the latest value; it must never affect other settings.

Apply the preference once per main-window instance: at launch and when a closed window is reopened, after saved settings are imported. `fullWindowVisible` changes on hide, unhide, minimize, restore and occlusion; these keep the current destination and never reapply the preference. An explicit search result or menu-to-entity action (`openGroup` followed by opening the window) takes precedence, including when it occurs before settings finish loading. A late preference application must never overwrite it. Onboarding and store errors remain visible regardless of the preference. Reopening must not add another sampler task.

Whether “Open Amid” can produce a second main window is a native question, not a confirmed defect. Observe it before considering any scene-architecture change.

→ Verify: every option, launch and close/reopen, hide/unhide/minimize/occlusion preserving the current destination, Last used across relaunch without benchmark invalidation, invalid saved values, onboarding/store failure, and direct-navigation precedence, including menu-to-entity during settings load. Observe actual window opening, menu-to-entity opening and return from Settings.

### 5. Expand menu-bar readouts

Retain icon, CPU and memory-pressure choices. Add readouts from existing measurements: clearly defined physical-memory amounts, swap, startup-volume available capacity, battery charge and throughput for a chosen interface. Label OS-reported free memory precisely; do not treat it as total reclaimable memory or a health score. Never sum overlapping network interfaces.

Offer value, small graph, or both where the metric supports a numeric series. Categorical pressure remains labeled text/state. Use bounded points from existing samples, retain gaps and unknown values, and show missing batteries/interfaces as unavailable rather than zero. A graph cannot trigger extra sampling or materialize the full retained archive.

Proposed first presentation: one compact menu-bar item with selectable readouts. Separate independently draggable status-bar items are a later extension, not a prerequisite for this feature. The selector must make the chosen interface and units clear.

→ Verify: numeric formatting, missing/reset/stale values, unavailable hardware, selected-interface disappearance, bounded graph state and unchanged collection cadence. Observe narrow-width rendering, accessible names/units and menu responsiveness. Record any measured overhead change without claiming the old performance target passed.

### 6. Configure Overview and menu layouts

Provide independent show/hide/order preferences for existing Overview sections and menu-panel sections. Offer card and compact-list presentation plus Reset to defaults. Keep destinations and underlying metric definitions unchanged.

Use drag-to-reorder with equivalent Move up/Move down controls for keyboard and VoiceOver. Keep onboarding, store failures, stale/coverage warnings and required measurement explanations reachable; hiding a card cannot suppress a critical state. Normalize duplicate/unknown section IDs and append newly introduced sections in a documented default order.

→ Verify: persistence, independent window/menu choices, reorder/hide/reset, malformed saved layouts and newly added section defaults. Observe keyboard/VoiceOver paths, focus after moving/hiding a section, minimum window size, light/dark and available display settings.

### 7. Verify and package the integrated additions

Build in two feature batches: steps 1–4 first, then steps 5–6. Use focused tests for each change and a complete affected integration run for each candidate. Keep one integration owner; delegate only bounded implementation/review areas after the shared preference/navigation contracts are agreed.

Freeze the final source, record real exit codes/skips, package a separately named ad-hoc app and preserve its source/executable identity. Record actual native observations separately from automated checks. If native tooling remains unreliable, leave those acceptance checks unverified; a new chat does not prove the tool recovered.

Run a bounded overhead comparison only for an explicit feature-related question. A full PRD acceptance benchmark still needs the prescribed workload, cadence, duration and baseline. The proposed local-alpha performance exception is a separate owner decision and remains unapproved.

→ Verify: no lost prior behavior, no extra collector timers, no new network/permission requirements, unchanged stop boundaries, compatible encrypted settings, successful build/tests/package and honest native evidence for all five features.

## Risks and questions for review

- Favorites can expose project identifiers; keep preferences encrypted and preserve export/privacy rules.
- Search, opening preferences and existing asynchronous History queries can race. Direct navigation must win, and privacy transitions must invalidate pending results.
- Graphs and layouts can create avoidable redraw work. Bound presentation state and measure demonstrated concerns rather than assume zero cost.
- Confirm the proposed single compact status item, favorite placement and layout scope before implementing their detailed UI. Multiple independent status items add a separate AppKit lifecycle requirement.
- Native UI verification is currently blocked. Hardware/OS coverage, consent-dependent checks, real beta duration and signing/notarization remain governed by the existing release plan.

Original self-critique: preference compatibility and navigation precedence need explicit tests before UI polish. The layout feature is the largest part; ship it in the second batch without weakening its keyboard behavior. The later independent Fable review adds prerequisite corrections; its recommendations do not waive acceptance gates or silently narrow these proposals.

## Outside this feature batch

Fan/sensor control, per-app volume, Docker/container control, browser-content inspection, arbitrary quit/force quit, new telemetry/updater endpoints and new collection privileges. Existing PRD privacy and action boundaries remain in force.

## New-session handoff

Use a new session in this Amid project after the plan and reviewer feedback are resolved. Do not create a separate repository. Read `GOAL.md`, `PRD.md`, `AGENTS.md`, this plan and the local memory checkpoint. The public source baseline is `3d966dd`; inspect Git state before changing files.

Use GPT-6.1 sol as requested. Begin with preference/navigation contracts and batch one. Preserve the current candidate, unresolved original acceptance gates and performance decision. Do not restart the prior indefinite optimization effort or mark a feature native-tested from unit tests alone.

Inspiration: [Vitals changelog](https://vitalsmac.com/changelog), reviewed 2026-10-04. Vitals documents app pinning, Command-F app filtering, opening-view choices, menu readouts and layout controls. Amid’s project pinning and unified app/project/process/port search are proposed extensions, not claims about Vitals.
