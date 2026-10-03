# Serel setup notes

These notes support the autonomous build prompt in `../GOAL.md`. They record the official setup guidance inspected on 2026-10-01. These are the original pre-installation planning notes. Installation and seeding subsequently completed; see [installation provenance](serel-installation.md). The populated bank is now private and shared locally between the two agents, under the owner’s subsequent [privacy policy](repository-hygiene.md).

## Sources and reproducibility

- [Memory combined setup prompt](https://github.com/madeordinary/serel-memory/blob/a407c994355cec892c061ceb9f247d359aae0a57/README.md#set-up-memory-and-kit-together)
- [Memory guided setup](https://github.com/madeordinary/serel-memory/blob/a407c994355cec892c061ceb9f247d359aae0a57/docs/serel-setup.md)
- [Kit setup and installer documentation](https://github.com/madeordinary/serel-kit/blob/0cb870dfe76489717a50353ddf898f33bfba73c1/README.md)
- [Memory released baseline](https://github.com/madeordinary/serel-memory/tree/v0.6.0): tag v0.6.0 resolved to commit `5f99244d648735db94429bf4e77571325160e5ec`.
- [Kit released baseline](https://github.com/madeordinary/serel-kit/tree/v0.2.0): tag v0.2.0 resolved to commit `a4b7b29b9b80e72294e601da2c264f8a9082a795`.

The newer Memory guide is on main and explicitly unreleased. Memory v0.6.0 does not install guided setup, its local installer, or its newer routing behavior. Read the guide from the inspected checkout and carry its setup decisions into the released workflows; do not claim those newer features are installed. Keep framework installation provenance distinct from the guide's provenance.

## Selected setup

- Scope: this project root, not the developer-projects parent or another app.
- Stage at handoff: approved PRD with no product implementation.
- Tools: Serel Memory plus complete Serel Kit `writing` and `verify` packs.
- Adapters: both Codex and Claude Code.
- Original storage selection: shared, version-controlled files for both tools. Superseded for working memory by the owner’s privacy approval: `memory-bank/` is now local and gitignored; reusable workflow files remain tracked.
- Hooks: off. Do not enable shell, session, or telemetry hooks automatically.
- Seed source: this project's `PRD.md`.
- Existing-data policy: inspect first, preserve populated banks and customized workflows, and never silently reinstall or upgrade.

The build prompt supplies explicit advance approval for this bounded setup, seeding, and routine project-memory updates. Still show the concrete write list and proposed seed contents. This is a project-specific authorization, not a claim that Serel's default workflow dispenses with review.

## Installation sequence

1. Inspect the project and its actual Git root, instructions, Serel anchors/receipts, and discovered workflows. Initialize an independent local Git repository here if absent. Never operate on an ancestor repository as the target.
2. Clone upstream into fresh temporary directories outside the project. Read the current official guide and compare it with these inspected references. Prefer the released baselines above for the initial shared payload; verify the tag commits before use. Record newer source changes without silently changing this approved installation plan.
3. Because this folder already contains important documents, use Memory's documented existing-project, non-clobbering shared-copy procedure, not an unchecked starter export into the folder. Copy the documented framework paths and blank templates from the release, preserving existing files. Keep upstream product metadata, maintainer memories, tests, research, and CI out of the app repository. Preserve required third-party license notices.
4. Record a truthful `.serel-memory.json` anchor using the actual installed release and upstream, following Memory's schema. Do not copy the upstream project's own anchor or invent completion metadata.
5. Read the installed `from-prd` skill/command and seed missing or blank core files from `PRD.md`. If actual product code appeared in the meantime, use the documented `init-memory` path instead. An initialized bank is resumed, not reseeded. Retain all real content in a partial bank.
6. Install Kit only after Memory exists. Inspect its installer first. The documented shared-install command is `bash <kit-checkout>/install.sh <this-project-root> --packs writing,verify`. This ordinary shared install applies immediately; do not invent a dry-run flag or assume `--apply` is required. Enumerate the payload and check conflicts before invoking it. Let the installer create its own `.serel-kit.json`; never handcraft or edit the receipt to bypass a refusal.
7. Inspect both agents' entry points after installation. Memory's `start`, `from-prd`, `breakdown`, and `update-memory`, and Kit's `polish` and `verify-map`, should have the expected native adapters. Do not import Claude commands into Codex to create duplicate skills. If the session cannot discover new skills dynamically, read and follow their installed files in the same session.
8. Confirm the seven core bank files contain project-specific content, state the implementation status honestly, and run the installed bootstrap and drift checks according to their documentation. Record unsupported checks rather than fabricating a successful result.

For an existing custom workflow with a similar purpose, preserve both and document which is primary if their behaviors can safely coexist. Same-path differences and incompatible instructions remain genuine conflicts; do not move or delete files merely to defeat the installer.

## Using the packs

`writing` proposes prose diffs only. Applying a chosen wording change is a separate project edit under the build prompt's authorization; it must not alter product requirements or evidence.

`verify` needs an initialized bank. Create a map per named workflow with an actual launch command and separate recipe and observation records. An unexecuted recipe is not verification. Store only observations the agent actually made, with revision, environment, logs or screenshots where available.

Use Memory's lifecycle for the rest of the bank, not Kit's installer or verification workflow. Keep known limitations and the exact next action current so a later coding session can resume without this conversation.
