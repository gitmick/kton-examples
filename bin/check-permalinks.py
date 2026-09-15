#!/usr/bin/env python3
"""Every carried permalink in a produced record must resolve to a file this repo actually tracks.

WHY THIS EXISTS. lib/common.sh attaches to every --in/--out a carried `uri`: the raw.githubusercontent
permalink of that path in this repo. That is the whole reason examples/*/.work/ is tracked at all -
a reader can fetch the exact bytes behind any node in the graph. The link and the tracking are one
mechanism, split across two files that know nothing about each other: common.sh mints the URL,
.gitignore decides whether the file behind it is published. Nothing connects them, so a plausible
edit to either - a new example locating a file under an ignored path, a broadened ignore rule, a
renamed working file - breaks every link it touches, silently. A 404 is not visible from inside a
run: the record is well-formed, signed, and wrong only to someone who follows the link months later.

So: check it. Reads every record the examples produced (their registries) plus the committed viewer
snapshots, collects the carried permalinks, and requires each one to name a tracked file.

Run it after the examples, from the repo root:  python3 bin/check-permalinks.py
Exit 0 = every permalink resolves. 1 = at least one does not. 2 = the check found nothing to check.
"""
import base64, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
# stop at whatever delimits the URL in its container: JSON quotes, TriG angle brackets, whitespace.
PERMALINK = re.compile(r"https://raw\.githubusercontent\.com/[^/]+/[^/]+/[^/]+/([^\"'\s\]>\\]+)")

def carried_uris(blob: bytes):
    """Permalinks in a file, both in the clear and inside base64 DSSE payloads."""
    for m in PERMALINK.finditer(blob.decode("utf-8", "replace")):
        yield m.group(1)
    for m in re.finditer(rb'"payload"\s*:\s*"([A-Za-z0-9+/=]+)"', blob):
        try:
            inner = base64.b64decode(m.group(1))
        except Exception:
            continue
        for mm in PERMALINK.finditer(inner.decode("utf-8", "replace")):
            yield mm.group(1)

# Where records live: the registries a run just wrote (mostly gitignored - that is the point, we are
# checking what they POINT AT) and the snapshots the viewer serves from the published site.
found = {}          # repo-relative path -> the file that referenced it
scanned = 0
# Everything that can hold a record, not just the example registries. docs/lens-paper is the
# second place carried permalinks appear: its corpus is built with --base pointing at the commit
# that holds the payload files, so the check that they are actually there is the same check - and
# the scanner used to walk past it, which would have made this guard silently partial the moment
# that tree landed.
for base in ("examples", "docs"):
    if not os.path.isdir(base):
        continue
    for dirpath, _dirs, files in os.walk(base):
        for fn in files:
            src = os.path.join(dirpath, fn)
            try:
                blob = open(src, "rb").read()
            except OSError:
                continue
            scanned += 1
            for path in carried_uris(blob):
                found.setdefault(path, src)

if not found:
    print("check-permalinks: found no carried permalinks at all in "
          f"{scanned} file(s) - run the examples first (bash examples/*/run.sh)", file=sys.stderr)
    print("  (refusing to report success for a check that had nothing to check)", file=sys.stderr)
    sys.exit(2)

# --against-ref <ref>: the RELEASE question, which is not the same one. The default check asks
# "is this path tracked HERE" - true on any branch, including one whose files have never been
# published. A carried permalink names a ref (KTON_RAW_COMMIT, `main` by default), and a reader
# follows it against THAT. Examples 15-17 are tracked here and absent from main, so their published
# links 404 until this branch lands. Opt-in rather than always-on, because until a merge that
# failure is expected and would only teach people to ignore a red check.
ref = None
if "--against-ref" in sys.argv:
    ref = sys.argv[sys.argv.index("--against-ref") + 1]
    print(f"check-permalinks: resolving against the ref a reader would follow: {ref}")
    tracked = set(subprocess.run(["git", "ls-tree", "-r", "--name-only", ref],
                                 capture_output=True, text=True, check=True).stdout.split("\n"))
else:
    tracked = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
                  .stdout.split("\n"))
broken = sorted((p, src) for p, src in found.items() if p not in tracked)

print(f"check-permalinks: {len(found)} distinct carried permalink target(s) across {scanned} file(s)")
if broken:
    print(f"  !! {len(broken)} permalink(s) point at a file this repo does NOT track - they will 404:",
          file=sys.stderr)
    for p, src in broken:
        where = f"on {ref}" if ref else "locally"
        state = (f"not {where}, though it exists in this checkout" if os.path.exists(p)
                 else f"does not exist {where}")
        print(f"     {p}  ({state})", file=sys.stderr)
        print(f"       referenced from {src}", file=sys.stderr)
    print("  Either track those files (see the .work/ rules in .gitignore) or stop locating them"
          " (lib/common.sh only attaches a uri to a path with a repo home).", file=sys.stderr)
    sys.exit(1)
print(f"  all {len(found)} resolve to tracked files")
sys.exit(0)
