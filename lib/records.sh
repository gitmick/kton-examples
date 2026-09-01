# records_of <registry-dir> - print every stored record in a registry as one JSON object per line.
#
# A registry files a scope's claims as ONE FILE PER (SUB)NEKTON - objects/scope/<scope_id>.nekton.jsonl
# and objects/unscoped.nekton.jsonl, one record per line - and older stores kept one file per claim at
# objects/<algo>/<hash>.json. Reading both is what makes an example work across the change.
records_of() {
  local dir="$1"
  find "$dir/objects" -name '*.nekton.jsonl' -type f 2>/dev/null | sort | while read -r f; do
    grep -v '^[[:space:]]*$' "$f"
  done
  find "$dir/objects" -name '*.json' -type f 2>/dev/null | sort | while read -r f; do
    jq -c . "$f"
  done
}

# records_required <registry-dir> <what> [min] - records_of, but ABORT if it read fewer than `min`
# (default 1) records.
#
# This exists because the dangerous failure in this repo is not a check that fails, it is a check that
# reads NOTHING and reports success anyway. Both known instances had that shape: 05's gate found zero
# claims and printed BLOCKED behind a `|| true`, and 11 built a 21-byte reviews.trig and passed. A
# reader on a store it does not understand - see docs/briefing-2026-09.md B1 - returns an empty list,
# not an error, so "empty" has to be refused HERE or it is never refused at all.
#
# Use this, not bare records_of, wherever the records are the thing being checked.
records_required() {
  local dir="$1" what="${2:-records}" min="${3:-1}" n
  local tmp; tmp="$(mktemp)"
  records_of "$dir" > "$tmp"
  n=$(grep -c '' < "$tmp" || true)
  if [ "$n" -lt "$min" ]; then
    rm -f "$tmp"
    echo "  !! READ NOTHING: expected at least $min $what in $dir, read $n." >&2
    echo "     The store is empty, unreadable, or written in a layout this reader does not know." >&2
    echo "     Refusing to report a verdict over an empty read (see docs/briefing-2026-09.md B3)." >&2
    return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

# count_records <registry-dir> - how many records the reader can see. Prints a number, never fails.
count_records() { records_of "$1" | grep -c '' || true; }
