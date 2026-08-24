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
