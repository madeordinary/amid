#!/usr/bin/env bash
# Serel Memory retention helper — READ-ONLY.
#
# Measures one bank file against its retention target and reports which
# historical entries would rotate to the archive to meet it. It never writes:
# /update-memory turns this report into diffs the user approves.
#
# Usage: hooks/lib/rotate-check.sh <file> <activeContext|progress>
#
# Targets (soft, per docs/workflow-contract.md "Retention"):
#   activeContext  <= 200 lines AND <= 12000 bytes
#   progress       "## Recent milestones" keeps its 10 newest entries
#
# Rotatable units, oldest LAST in file order (banks are newest-first):
#   activeContext  whole "## Recent changes (<suffix>)" sections, and
#                  top-level bullets under an unsuffixed "## Recent changes"
#   progress       top-level bullets under "## Recent milestones"
# Everything else is left untouched. Protected sections are never selected.
#
# Exit codes: 0 report produced (any RESULT), 2 usage error.
set -euo pipefail
export LC_ALL=C   # byte semantics for length() and wc -c

ACTIVE_MAX_LINES=200
ACTIVE_MAX_BYTES=12000
PROGRESS_KEEP=10

file="${1:-}"
kind="${2:-}"
if [ -z "$file" ] || [ -z "$kind" ] || [ ! -f "$file" ]; then
  echo "usage: $0 <file> <activeContext|progress>" >&2
  exit 2
fi
case "$kind" in
  activeContext|progress) ;;
  *) echo "usage: kind must be activeContext or progress" >&2; exit 2 ;;
esac

cur_lines="$(wc -l < "$file" | tr -d ' ')"
cur_bytes="$(wc -c < "$file" | tr -d ' ')"
base="$(basename "$file" .md)"

# One awk pass classifies the file:
#   H<TAB>heading           every H2 heading
#   P<TAB>lineno            pointer line ("Older entries: archive/...")
#   U<TAB>start<TAB>end<TAB>type<TAB>first-line
scan="$(awk -v kind="$kind" '
  function flush_unit() {
    if (ustart == 0) return
    printf "U\t%d\t%d\t%s\t%s\n", ustart, ulast, utype, utitle
    ustart = 0
  }
  BEGIN { ustart = 0; mode = ""; infence = 0 }
  # Fenced code is opaque: never a heading, bullet, or pointer. It is body
  # text of whatever unit encloses it (or nothing). A fence opens with 3+
  # backticks or tildes (up to 3 spaces of indent) and closes only with the
  # same character, at least as long, and nothing but whitespace after it —
  # so a ```` fence that quotes ``` examples stays one fence.
  /^ *(```|~~~)/ {
    m = $0; sub(/^ */, "", m)
    if (length($0) - length(m) <= 3) {   # more than 3 spaces of indent is not a fence
      ch = substr(m, 1, 1)
      n = 0; while (substr(m, n + 1, 1) == ch) n++
      if (!infence) { infence = 1; fch = ch; flen = n; if (ustart > 0) ulast = NR; next }
      rest = substr(m, n + 1); gsub(/[[:space:]]/, "", rest)
      if (ch == fch && n >= flen && rest == "") { infence = 0; if (ustart > 0) ulast = NR; next }
    }
  }
  infence      { if (ustart > 0) ulast = NR; next }
  # A sub-heading inside a bullet section is not a bullet continuation; the
  # structure is unsupported from there on, so stop collecting units.
  /^### / && mode == "bullets" { flush_unit(); mode = ""; print "X\t" NR; next }
  /^## / {
    flush_unit()
    print "H\t" $0
    mode = ""
    if (kind == "activeContext" && $0 ~ /^## Recent changes \(/) {
      ustart = NR; ulast = NR; utype = "section"; utitle = $0
      mode = "section"
      next
    }
    if (kind == "activeContext" && $0 == "## Recent changes") mode = "bullets"
    if (kind == "progress" && $0 == "## Recent milestones") mode = "bullets"
    next
  }
  /^Older entries: archive\// { print "P\t" NR }
  mode == "section" {
    if ($0 != "") ulast = NR
    next
  }
  mode == "bullets" && /^- / {
    flush_unit()
    ustart = NR; ulast = NR; utype = "bullet"; utitle = $0
    next
  }
  mode == "bullets" && ustart > 0 {
    if ($0 != "") ulast = NR
    next
  }
  END { flush_unit() }
' "$file")"

headings="$(printf '%s\n' "$scan" | awk -F'\t' '$1=="H"{print $2}')"
pointer="$(printf '%s\n' "$scan" | awk -F'\t' '$1=="P"{print $2; exit}')"
unsupported="$(printf '%s\n' "$scan" | awk -F'\t' '$1=="X"{print $2; exit}')"
units="$(printf '%s\n' "$scan" | awk -F'\t' '$1=="U"')"
unit_count=0
[ -n "$units" ] && unit_count="$(printf '%s\n' "$units" | wc -l | tr -d ' ')"

# Span bytes come straight from the line range so predictions match wc -c.
span_bytes() { sed -n "${1},${2}p" "$file" | wc -c | tr -d ' '; }

echo "FILE: $file"
echo "KIND: $kind"
if [ "$kind" = "activeContext" ]; then
  echo "TARGET: lines<=$ACTIVE_MAX_LINES bytes<=$ACTIVE_MAX_BYTES"
  echo "CURRENT: lines=$cur_lines bytes=$cur_bytes"
  protected="Current focus|Checkpoint|Next steps|Open questions|Notes for next session"
else
  echo "TARGET: milestones<=$PROGRESS_KEEP"
  echo "CURRENT: milestones=$unit_count lines=$cur_lines bytes=$cur_bytes"
  protected="Status|What works|In progress|What's left to build|Known issues"
fi

found=""
IFS='|' read -r -a prot_names <<<"$protected"
for p in "${prot_names[@]}"; do
  if printf '%s\n' "$headings" | grep -qx "## $p"; then found="$found; $p"; fi
done
echo "PROTECTED: ${found#; }"
if [ -n "$pointer" ]; then echo "POINTER: present (line $pointer)"; else echo "POINTER: missing"; fi
echo "ROTATABLE: $unit_count units (oldest last)"

[ -n "$unsupported" ] && echo "UNSUPPORTED: sub-heading at line $unsupported inside a bullet section; units after it are not collected"

i=0
first_section_seen=0
declare -a u_start u_end u_bytes u_prefix
while IFS=$'\t' read -r _ s e t title; do
  [ -n "$s" ] || continue
  prefix=""
  # The newest dated section keeps its heading line live — that is where the
  # archive pointer lives — so its span starts after the heading (and after
  # the pointer when it sits directly under it). The heading is still COPIED
  # to the archive (ARCHIVE-PREFIX) so the rotated bullets keep their date.
  if [ "$t" = "section" ] && [ "$first_section_seen" -eq 0 ]; then
    first_section_seen=1
    prefix="$s"
    s=$((s + 1))
    if [ -n "$pointer" ] && [ "$pointer" -eq "$s" ]; then s=$((s + 1)); fi
    if [ "$s" -le "$e" ] && [ -z "$(sed -n "${s}p" "$file")" ]; then s=$((s + 1)); fi
    if [ "$s" -gt "$e" ]; then continue; fi   # heading-only section: nothing to rotate
  fi
  i=$((i + 1))
  u_start[i]="$s"; u_end[i]="$e"; u_bytes[i]="$(span_bytes "$s" "$e")"; u_prefix[i]="$prefix"
  printf 'UNIT %d: %s-%s %s "%s"\n' "$i" "$s" "$e" "$t" "$title"
done <<<"$units"
unit_count="$i"

# --- Selection ---------------------------------------------------------------
sel_from=0   # first selected unit index (selection is a suffix: units sel_from..unit_count)
pred_lines="$cur_lines"
pred_bytes="$cur_bytes"
pointer_cost_lines=0
pointer_cost_bytes=0
if [ -z "$pointer" ]; then
  pointer_cost_lines=1
  pointer_cost_bytes=$(( ${#base} + 29 ))   # "Older entries: archive/" (23) + base + "-*.md" (5) + newline
fi

if [ "$kind" = "activeContext" ]; then
  over() { [ "$pred_lines" -gt "$ACTIVE_MAX_LINES" ] || [ "$pred_bytes" -gt "$ACTIVE_MAX_BYTES" ]; }
  if over; then
    j="$unit_count"
    # Rotation adds a pointer line once; account for it before removing units.
    pred_lines=$((pred_lines + pointer_cost_lines))
    pred_bytes=$((pred_bytes + pointer_cost_bytes))
    while over && [ "$j" -ge 1 ]; do
      pred_lines=$((pred_lines - (u_end[j] - u_start[j] + 1)))
      pred_bytes=$((pred_bytes - u_bytes[j]))
      sel_from="$j"
      j=$((j - 1))
    done
    if [ "$sel_from" -eq 0 ]; then
      # nothing rotatable: undo the pointer cost
      pred_lines=$((pred_lines - pointer_cost_lines))
      pred_bytes=$((pred_bytes - pointer_cost_bytes))
    fi
  fi
else
  if [ "$unit_count" -gt "$PROGRESS_KEEP" ]; then
    sel_from=$((PROGRESS_KEEP + 1))
    pred_lines=$((pred_lines + pointer_cost_lines))
    pred_bytes=$((pred_bytes + pointer_cost_bytes))
    j="$unit_count"
    while [ "$j" -ge "$sel_from" ]; do
      pred_lines=$((pred_lines - (u_end[j] - u_start[j] + 1)))
      pred_bytes=$((pred_bytes - u_bytes[j]))
      j=$((j - 1))
    done
  fi
fi

if [ "$sel_from" -gt 0 ]; then
  n=$((unit_count - sel_from + 1))
  spans=""
  j="$sel_from"
  while [ "$j" -le "$unit_count" ]; do
    spans="$spans ${u_start[j]}-${u_end[j]}"
    j=$((j + 1))
  done
  echo "SELECT: units $sel_from..$unit_count ($n) lines:${spans}"
  j="$sel_from"
  while [ "$j" -le "$unit_count" ]; do
    [ -n "${u_prefix[j]}" ] && echo "ARCHIVE-PREFIX: line ${u_prefix[j]} (copy this heading into the archive before span ${u_start[j]}-${u_end[j]}; it stays live as the pointer's home)"
    j=$((j + 1))
  done
  echo "ARCHIVE: archive/${base}-$(date +%Y-%m).md"
  if [ "$kind" = "activeContext" ]; then
    echo "PREDICTED: lines=$pred_lines bytes=$pred_bytes"
    if [ "$pred_lines" -gt "$ACTIVE_MAX_LINES" ] || [ "$pred_bytes" -gt "$ACTIVE_MAX_BYTES" ]; then
      echo "RESULT: OVERAGE-REMAINS (rotate $n; protected/current content alone still exceeds the target)"
    else
      echo "RESULT: ROTATE $n"
    fi
  else
    echo "PREDICTED: milestones=$PROGRESS_KEEP lines=$pred_lines bytes=$pred_bytes"
    echo "RESULT: ROTATE $n"
  fi
else
  if [ "$kind" = "activeContext" ] && { [ "$cur_lines" -gt "$ACTIVE_MAX_LINES" ] || [ "$cur_bytes" -gt "$ACTIVE_MAX_BYTES" ]; }; then
    echo "PREDICTED: lines=$cur_lines bytes=$cur_bytes"
    echo "RESULT: OVERAGE-REMAINS (no rotatable units: unsupported structure or protected content alone exceeds the target)"
  else
    echo "RESULT: NO-OP"
  fi
fi
