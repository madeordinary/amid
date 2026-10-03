# Repository hygiene

The public repository contains source, tests, original assets, build scripts, the MIT license and dependency notices, the PRD, reusable Serel Memory/Kit workflows, contributor instructions, architecture and testing documentation, and reviewed evidence summaries. Source publication is a development preview; it is not a signed/notarized application release or an acceptance pass.

The entire `memory-bank/` directory is private, local and gitignored, including core files, session checkpoints, working verification maps and archives. Both agent adapters can use the same local bank. Public clones do not need it to build or test; `AGENTS.md` describes the public documentation fallback. Keep durable public explanations in reviewed `docs/` files without copying private session history into them.

`.gitignore` also excludes SwiftPM/Xcode caches, generated app packages and reports, fixture dependency caches, editor state, environment files, private signing material, encrypted runtime stores, diagnostics/exports, raw logs and draft diffs. Keep reusable sample configuration, package manifests/lockfiles, test fixtures, assets and shared project rules tracked. Never ignore every JSON file.

Public `main` is a sanitized source snapshot with no memory-bank files in its reachable history. The original private implementation history and the earlier two-commit public history are preserved in local-only branches and verified ignored Git bundles; neither is an ancestor of public `main`. Do not push or merge those backup branches, mirror all refs, or upload the bundles. Public commits use a GitHub no-reply author address. Earlier short commit IDs in evidence describe the original local build chronology; source/executable hashes and recorded test limits remain available independently. A history rewrite cannot recall existing clones, forks or hosting caches of previously published files.

Raw run logs and drafting records remain local. Public summaries preserve failures, skipped checks and measurement limitations, and public test scripts allow reproduction. References marked “local record” are intentionally not public downloads. Personal checkout paths in recipes are replaced by `/path/to/amid`; use your actual checkout path.

Before staging new diagnostics, inspect their contents. `.gitignore` does not remove already tracked files or historical commits. Use `git check-ignore -v --no-index <path>` to check rules and `git diff --cached` to review the actual publication. Never force-add the working bank or private output.
