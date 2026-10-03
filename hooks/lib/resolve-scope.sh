#!/usr/bin/env bash
# Serel Memory scope resolver — READ-ONLY.
#
# Resolves which memory bank an invocation targets. Single-bank repos (no
# "scopes" in .serel-memory.json) always resolve to the repo root, exactly as
# before scopes existed. With scopes configured, one project bank can be
# selected explicitly or by cwd. See docs/workflow-contract.md
# "Resolving scope".
#
# Usage:
#   resolve-scope.sh [--root <repo_root>] [--scope <path>] [--cwd <dir>]
#   resolve-scope.sh [--root <repo_root>] --list
#
# Output (one line, tab-separated, paths relative to the repo root, "." = root,
# "-" = absent):
#   scope_root  bank_dir  rules_write  rules_read  inherited_rules  state
# --list prints "SCOPES: none" or one "P<TAB><project_root><TAB><state>" line
# per project (state = initialized | uninitialized).
#
# Exit: 0 resolved; 2 usage error or unknown --scope (valid selectors on stderr).
set -euo pipefail

ROOT=""; SEL=""; CWD=""; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)  ROOT="${2:-}"; shift 2 ;;
    --scope) SEL="${2:-}"; shift 2 ;;
    --cwd)   CWD="${2:-}"; shift 2 ;;
    --list)  LIST=1; shift ;;
    *) echo "usage: $0 [--root DIR] [--scope PATH] [--cwd DIR] | --list" >&2; exit 2 ;;
  esac
done
if [ -z "$ROOT" ]; then
  ROOT="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ROOT="$(cd "$ROOT" && pwd -P)"
[ -n "$CWD" ] || CWD="$PWD"

warn() { echo "resolve-scope: $*" >&2; }

# --- Configured scope roots ---------------------------------------------------
scopes=()
anchor="$ROOT/.serel-memory.json"
if [ -f "$anchor" ] && grep -q '"scopes"' "$anchor"; then
  if command -v jq >/dev/null 2>&1; then
    if stype="$(jq -r 'if has("scopes") then (.scopes | type) else "absent" end' "$anchor" 2>/dev/null)"; then
      if [ "$stype" = "array" ]; then
        raw="$(jq -r '.scopes[] | if type=="string" then . else "\u0001" end' "$anchor")"
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          if [ "$line" = $'\001' ]; then warn "\"scopes\" must be an array of strings — treating as single-bank"; scopes=(); break; fi
          scopes+=("$line")
        done <<<"$raw"
      elif [ "$stype" != "absent" ]; then
        warn "\"scopes\" must be an array of strings (got $stype) — treating as single-bank"
      fi
    else
      warn "cannot parse $anchor — treating as single-bank"
    fi
  else
    warn "jq is required to read \"scopes\" from .serel-memory.json — treating as single-bank"
  fi
fi

# Validate: relative, no '..', existing directories, non-overlapping. Any
# problem disables scopes entirely (conservative: never guess a bank).
# Normalize before validating so aliases ("./a", "a//b", "a/") cannot evade the
# overlap check or the cwd match: strip "./" prefixes, collapse "//", drop the
# trailing "/".
if [ "${#scopes[@]}" -gt 0 ]; then
  norm=()
  for s in "${scopes[@]}"; do
    # BSD sed needs each label/branch as its own -e expression.
    s="$(printf '%s' "$s" | sed -E -e 's#/+#/#g' -e 's#^(\./)+##' -e ':a' -e 's#/\./#/#' -e 'ta' -e 's#/\.$##' -e 's#/$##')"
    norm+=("$s")
  done
  scopes=("${norm[@]}")
  valid=1
  for s in "${scopes[@]}"; do
    case "$s" in
      /*|../*|*/../*|*/..|..|.|"") warn "invalid scope root '$s'"; valid=0 ;;
      *) [ -d "$ROOT/$s" ] || { warn "scope root '$s' is not a directory"; valid=0; } ;;
    esac
  done
  n="${#scopes[@]}"; i=0
  while [ "$i" -lt "$n" ]; do
    j=$((i + 1))
    while [ "$j" -lt "$n" ]; do
      a="${scopes[i]}"; b="${scopes[j]}"
      if [ "$a" = "$b" ]; then warn "scope roots overlap: '$a' listed twice"; valid=0
      else
        case "$b/" in "$a/"*) warn "scope roots overlap: '$a' contains '$b'"; valid=0 ;; esac
        case "$a/" in "$b/"*) warn "scope roots overlap: '$b' contains '$a'"; valid=0 ;; esac
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  if [ "$valid" -eq 0 ]; then warn "scopes disabled — single-bank behavior"; scopes=(); fi
fi

# --- Project roots: immediate child directories of each scope root -----------
projects=()
for s in "${scopes[@]:-}"; do
  [ -n "$s" ] || continue
  s="${s%/}"
  while IFS= read -r d; do
    [ -n "$d" ] && projects+=("${d#"$ROOT"/}")
  done < <(find "$ROOT/$s" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)
done

# Same effective-bank rule as selection: an overlay counts as a bank.
state_of() { { [ -d "$ROOT/$1/memory-bank.local" ] || [ -d "$ROOT/$1/memory-bank" ]; } && echo initialized || echo uninitialized; }

if [ "$LIST" -eq 1 ]; then
  if [ "${#projects[@]}" -eq 0 ]; then echo "SCOPES: none"; exit 0; fi
  for p in "${projects[@]}"; do printf 'P\t%s\t%s\n' "$p" "$(state_of "$p")"; done
  exit 0
fi

# --- Selection: explicit selector → cwd → root -------------------------------
scope_root="."
if [ -n "$SEL" ]; then
  SEL="${SEL%/}"
  if [ "$SEL" = "." ]; then
    scope_root="."
  else
    found=0
    for p in "${projects[@]:-}"; do [ "$p" = "$SEL" ] && found=1; done
    if [ "$found" -eq 0 ]; then
      echo "resolve-scope: unknown scope '$SEL'" >&2
      if [ "${#projects[@]}" -eq 0 ]; then
        echo "  no scopes are configured in .serel-memory.json (only '.' is valid)" >&2
      else
        echo "  valid selectors:" >&2
        for p in "${projects[@]}"; do echo "    --scope $p" >&2; done
      fi
      exit 2
    fi
    scope_root="$SEL"
  fi
elif [ "${#projects[@]}" -gt 0 ]; then
  cwd_abs="$(cd "$CWD" 2>/dev/null && pwd -P || echo "$CWD")"
  case "$cwd_abs/" in
    "$ROOT"/*)
      rel="${cwd_abs#"$ROOT"/}"
      for p in "${projects[@]}"; do
        case "$rel/" in "$p"/*) scope_root="$p" ;; esac
      done ;;
  esac
fi

# --- Effective bank inside the selected scope (overlay-aware) ----------------
sr="$scope_root"
pre=""; [ "$sr" != "." ] && pre="$sr/"
if [ -d "$ROOT/${pre}memory-bank.local" ]; then
  bank_dir="${pre}memory-bank.local"
  rules_write="${pre}memory-bank.local/.rules"
else
  bank_dir="${pre}memory-bank"
  rules_write="${pre}.rules"
fi
rules_read="-"
for cand in "$rules_write" "${pre}.rules"; do
  if [ -f "$ROOT/$cand" ]; then rules_read="$cand"; break; fi
done
inherited="-"
if [ "$sr" != "." ]; then
  for cand in "memory-bank.local/.rules" ".rules"; do
    if [ -f "$ROOT/$cand" ]; then inherited="$cand"; break; fi
  done
fi
state=initialized
[ -d "$ROOT/$bank_dir" ] || state=uninitialized

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sr" "$bank_dir" "$rules_write" "$rules_read" "$inherited" "$state"
