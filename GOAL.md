# Amid autonomous build goal

Work in this repository root only, apart from isolated temporary directories and normal dependency caches. Build **Amid by Made Ordinary**, a clear, local-first Mac activity monitor organized around applications, development projects and ports, from this project's `PRD.md`.

My goal is a complete, locally runnable and thoroughly tested v0.1 implementation, with Serel Memory and Serel Kit installed and used, a polished native GUI, reproducible build/package instructions, and an honest handoff for any remaining human-only release gates. Create and pursue an active goal if your environment supports that capability; otherwise maintain the equivalent milestone checklist. This is an implementation request, not a request to stop after producing a plan.

## Publication approval — 2026-10-02

The owner explicitly authorized publishing this project as the public GitHub repository `madeordinary/amid`. This supersedes the original source-repository creation/push prohibition only for that repository. A clean public initial snapshot preserves source, tests, licenses, shared Serel workflows and reviewed evidence; private local history, raw logs and session archives are retained locally. It does not authorize binary releases, signing/notarization, purchases, accounts, deployments or changes to other projects. Existing product acceptance gates remain open.

## Working-memory privacy approval — 2026-10-02

The owner subsequently approved keeping the entire working `memory-bank/` private and removing it from the published repository history. This supersedes the earlier version-controlled bank storage choice: both agents share the same local, gitignored bank; reusable Serel workflows, `AGENTS.md` and curated public documentation remain tracked. Preserve the prior public history in a local-only backup, then replace only public `main` using an exact force-with-lease. Do not upload either private history backup. Previously fetched copies and hosting caches cannot be recalled by rewriting the branch.

## Authority and working style

I authorize you to carry out the in-scope local work without asking me to approve each step. Inspect first, write a concise milestone plan, then execute it. Choose reasonable reversible engineering and UI defaults, record their rationale, and keep moving. Do not repeatedly ask which task to do next, whether to continue, or questions already answered by this prompt or the PRD.

This advance approval specifically covers the local Git initialization, scoped Serel installation, initial memory seeding, truthful memory updates, implementation plans, tests, dependency selection within the license/privacy constraints, project-owned documentation, verification maps, and applying meaning-preserving writing improvements described below. Still show or save the expected write list, seed proposals and diffs before applying them. For these enumerated actions, this explicit user approval replaces repeat confirmation waits in the project workflows; it does not remove their inspection, conflict, scope, evidence, or preservation checks. Do not edit Serel's upstream workflow files merely to remove approval language.

Continue from one milestone to the next automatically. Do not stop at a scaffold, a successful build, mock screenshots, or an initial unit-test pass while material in-scope work remains. Fix discovered regressions and repeat verification. Use parallel subagents for separable implementation or review tasks when available; give them bounded file ownership and consolidate changes through one integration owner. Do not start separate user-facing chats or modify the other Made Ordinary app.

Routine local commits of this task's reviewed changes are authorized if Git identity is already configured. Do not change global Git identity, commit unrelated files, create a remote repository, push, open PRs, upload artifacts, deploy, publish a release, or contact anyone.

## Start with the actual project state

Read `PRD.md` in full, `docs/naming-review.md`, `docs/serel-setup-notes.md`, and any applicable existing agent instructions. Inspect files, Git status/root, available toolchains, and installed Serel metadata. These handoff folders originally contained documents only; do not assume they are still blank if another session has started work.

The PRD defines accepted product scope. Code and observed tests define what works now. Never seed memory with planned features marked implemented, invent benchmark results, or silently change requirements to fit an easier implementation. The name is decided; do not reopen naming or buy a domain.

## Set up Serel Memory and Serel Kit

Use the official combined setup workflow at https://github.com/madeordinary/serel-memory and Kit instructions at https://github.com/madeordinary/serel-kit. Clone fresh upstream sources into unique temporary directories outside this project, inspect their READMEs, Memory's `docs/serel-setup.md`, the relevant seed workflows, and Kit's installer before executing them. Use the reproducible release baselines and provenance notes in `docs/serel-setup-notes.md`. Do not pipe downloaded scripts into a shell without inspection.

The setup answers are already decided:

- Scope: this project root.
- Stage: PRD with no implementation at initial handoff; if real code now exists, inspect that first.
- Capabilities: Memory and complete Kit `writing,verify` packs.
- Agents: both Claude Code and Codex, with their native adapters.
- Storage: originally shared, version-controlled project files; the later privacy approval keeps the working bank shared locally and gitignored, with reusable workflows tracked.
- Hooks: off.
- Seed source: `PRD.md`.
- Approval: initial installation, seed proposals and their application are explicitly authorized within this scope.

If needed, initialize an independent local Git repository in this exact project folder. Use Memory's non-clobbering existing-project installation procedure because the folder already contains important documents. Never export a whole template over the folder. Do not copy another application's bank, upstream maintainer memory, framework project metadata, framework CI, or framework tests into this app. Preserve upstream license notices.

Install Memory first, record truthful provenance, then run `from-prd` to seed the seven core files. Use `init-memory` with the PRD if implementation already exists. Preserve every populated file in a partial bank; resume rather than reseed an initialized bank. Install Kit through its documented installer, never by fabricating its receipt. The verify pack requires installed Memory and an initialized bank before use.

Inspect overlapping workflows by purpose, not only filename. Keep unrelated or complementary workflows. For a benign overlap, preserve both and record the project-local Serel entry as primary for this project's memory/verification lifecycle while retaining stricter applicable safety rules. Never delete, disable, move aside or overwrite a custom workflow to evade a collision check. If genuine same-path or behavior conflicts prevent a pack from installing, leave that affected unit unchanged, record the blocker, and continue unaffected app work.

Check both agents' installed entry points and the bank's completeness. If new skills are not dynamically available, read and follow the installed workflow files in the same session. Do not demand a restart solely to invoke a skill by name. Keep Memory's lifecycle separate from Kit's installation; Kit never owns the bank.

## Product constraints

Implement native Swift with SwiftUI and AppKit, Apple silicon first, targeting macOS 15 and supported newer versions as the PRD specifies. Pin and document the Xcode/SDK and dependency versions actually used. Prefer standard platform facilities and small, maintained, license-compatible dependencies. Original app code is MIT; preserve dependency notices and do not copy incompatible competitor implementations.

The app must work offline with no account, hosted backend, analytics, automatic crash uploads, cloud sync, subscription, web wrapper, AI inference or model download in v0.1. Optional update traffic follows the PRD's separate consent and documentation requirements. Serel is development tooling and must not become a runtime dependency of the shipped app.

## Product implementation order

1. Phase 0: prove unprivileged CPU/memory accounting, process identity and PID-reuse handling, application grouping, accessible working-directory/project-marker attribution, listening TCP ownership, safe supported-server stop isolation, encrypted history and monitoring overhead. Record supported and unsupported fields by OS and test fixture before making feature claims.
2. Core alpha: implement a menu-bar panel and full native window with Overview, Applications, Projects and Ports. Add CPU/memory measurements, honest missing-data states, process drill-down, native Node/Python/Swift project fixtures and recognized-runtime labels only when supported by permitted metadata. Keep it read-only until identity/action tests pass.
3. Workflow beta: implement the PRD's local aggregate history, retention choices, conservative alerts, exclusions, aliases, explicit diagnostics export, and narrowly supported graceful development-server stop adapters. Validate current target identity, preview affected processes and endpoints, request confirmation, then verify the result. Never silently force kill.
4. Finish History, Alerts and Settings, with onboarding, failure states, native tables, textual chart alternatives, keyboard/VoiceOver, light/dark appearance, scaling, reduced motion and contrast. Pick a restrained Made Ordinary visual direction without waiting for a design interview; use native controls and original assets.
5. Test measurements against reference observations, profile observer overhead, refine the UI, prepare a local app bundle and release tooling, and close all locally achievable PRD gates.

Specific non-negotiables: do not read command arguments, environment variables, credentials, prompts, editor buffers or network payloads. Do not add a root helper, private frameworks, broad disk access, arbitrary process killing, container/Docker socket access, or inferred agent state. Unknown coverage is not zero. Do not equate high RAM use with a problem or imply a causal diagnosis without evidence. Project/port attribution is essential, not something to silently drop if difficult.

Stop tests may target only disposable processes and servers created and owned by this test run, with recorded identities and safe cleanup. Never terminate the user's editors, terminals, databases, model runtimes, existing dev servers, or unknown processes for a test. Real stop UI must remain explicitly confirmed.

Create verification maps for onboarding/history opt-in; system/application metrics; project grouping; port ownership; history and gaps; alert cooldown/recovery; allowed graceful stops and identity races; diagnostics privacy; and accessibility. Keep unavailable hardware metrics or cross-OS measurements visibly unverified.

## Verification and progress

Create a requirement-to-evidence checklist covering every functional requirement and release gate in the PRD. For each entry distinguish implemented, automated-tested, manually-observed, unverified, blocked, or deferred-by-PRD. Link to the code, executable test, observation or blocker. A mock is useful for a unit test but does not prove an OS integration works.

Use synthetic fixtures and temporary app-owned storage. Include error/denial paths, recovery, migrations, lifecycle races, privacy boundaries and accessibility. Build and run the actual application when the environment permits, inspect the real rendered UI, and keep screenshots or logs free of personal data. Evaluate commands by their true exit codes. Do not lower a budget, skip a failing test, weaken assertions, or hide unsupported behavior just to get a green result.

Use Kit's verify-map workflow for the named features, with real Launch, Drive, Observe and Clean up steps and separate observation records. Show the diff, then apply under this explicit approval. For writing, let the polish workflow propose a diff without writing; separately apply only useful meaning-preserving edits under this approval. Never polish away uncertainty or change product scope.

Use the installed other agent CLI for a read-only second opinion on security-sensitive storage/action designs or a substantial review when it is available under the existing account. Send only task-relevant, non-secret context and never give that reviewer write authority. If unavailable, perform a clearly labeled self-review and continue; do not pretend an independent review happened. A reviewer is advisory, not permission to expand scope or weaken gates.

Keep `memory-bank/activeContext.md`, `progress.md`, and decisions truthful. Maintain one resumable checkpoint with completed work, current revision, exact commands and results, blockers, and the next action. Add only durable lessons to `.rules`. Update memory at meaningful milestones and before a context handoff; do not churn the bank after every small edit.

## Genuine boundaries

Use the toolchains and permissions already available. Project-local dependencies and caches are allowed; do not perform global package installs, replace system toolchains, accept legal agreements, run privileged installers, enable hooks or modify machine security settings without specific approval.

Never grant or bypass macOS Accessibility, clipboard, notification, screen-recording or other privacy consent on my behalf. Do not modify TCC databases, signing identities or the Keychain's existing credentials. A permission denial is a supported app state to test, not an obstacle to work around.

Do not purchase services/domains, create accounts, change billing, publish source/builds, enroll in Apple programs, submit to the App Store, notarize/upload with my credentials, or change other projects. Prepare scripts/checklists for those steps instead. A local unsigned or ad-hoc development build is acceptable for this milestone but is not a signed/notarized public release.

If a step truly needs my credentials, consent, unavailable hardware/OS, public-release authorization, a destructive change to existing user data, or a material change to the PRD, isolate it and document the smallest exact action needed. Continue independent safe work. Only pause when no meaningful authorized work remains. Do not ask permission for routine reversible choices, but do not invent permission where it is required.

A two-week real-use beta and unavailable-device checks cannot be simulated by generated logs or declared complete in a short session. Prepare the beta and its checklist, then report those as open external gates.

## Completion and handoff

The local implementation goal is complete only when all agent-achievable v0.1 requirements are implemented and tested, the app builds and runs locally where the environment supports it, Serel setup has been verified, no known critical privacy/data-loss/unsafe-action defect remains, and the following are ready:

- Source, tests, dependency/license inventory and repeatable build/test/package commands.
- A usable local app bundle when build tooling is available, with its actual signing status stated.
- An honest requirement/evidence matrix and verification maps.
- README instructions for development, permissions, limitations and local use.
- Release preparation, including a beta plan, compatibility gaps and signing/notarization steps.
- Current Serel memory and a compact handoff listing what works, what was observed, what is still blocked, and the next exact human action, if any.

If missing tools or a technical feasibility failure prevents those criteria, finish unaffected work and report the local goal as incomplete with evidence; do not relabel a source-only or stubbed deliverable as a completed app. External publication, real beta duration and hardware I do not have are separate release gates, not reasons to stop implementing the rest.

Start now: inspect the repository, present the short execution plan, perform the approved Serel setup, and continue through implementation and verification without waiting for another routine go-ahead.
