#!/usr/bin/env bash
# After a full pass over the examples, what may a run legitimately have changed?
#
# B7 answered that - only what a run DERIVES is untracked, the data it reads stays tracked - but the
# answer lived in .gitignore rules and in a number measured by hand. Nothing enforced it, so when the
# 0.2 kernel started writing a durable sync cursor at <registry>/.seq (kton #97), a file class that no
# rule covered appeared in 15 examples, a `git add -A` tracked all 37, and each carried a fresh random
# `epoch` per run. 15 churning files became 52 and nobody noticed for three days.
#
# So: assert it. Two rules, both narrow enough to name what broke.
#
#   1. A run may not leave anything UNTRACKED that is not ignored. A new file class from a kernel
#      upgrade shows up here first, before someone sweeps it into the index.
#   2. A run may not modify a tracked file outside the two examples that are volatile ON PURPOSE.
#
# Rule 2 is coarse: it allows any churn inside 10-tool-spectrum and 12-submission, because those two
# print a pid and a wall clock (tests/test-predict.R, tools/fit.R, tools/pmxtest.R) and that volatility
# is what makes their L0-vs-L1 distinction demonstrable. A regression that only dirties files inside
# those two would slip past. Tightening it to a file list would trade that for breaking whenever those
# examples legitimately gain a file; the class of mistake this is built for - a new file class across
# many examples - is caught either way.
#
# Run from a CLEAN tree, after the examples:  bash bin/check-churn.sh
set -uo pipefail
cd "$(dirname "$0")/.."

VOLATILE='^(examples|docs/data)/(10-tool-spectrum|12-submission)/'
rc=0

untracked=$(git ls-files --others --exclude-standard)
if [ -n "$untracked" ]; then
  echo "  !! a run left $(printf '%s\n' "$untracked" | grep -c '') untracked file(s) that no rule ignores:" >&2
  printf '%s\n' "$untracked" | sed 's/^/       /' | head -20 >&2
  echo "     Either they are data an example reads (track them) or they are derived (add a rule to" >&2
  echo "     .gitignore). A new kernel version writing a new file class looks exactly like this." >&2
  rc=1
fi

changed=$(git diff --name-only | grep -Ev "$VOLATILE" || true)
if [ -n "$changed" ]; then
  echo "  !! a run modified $(printf '%s\n' "$changed" | grep -c '') tracked file(s) outside the two deliberately volatile examples:" >&2
  printf '%s\n' "$changed" | sed 's/^/       /' | head -20 >&2
  echo "     A committed snapshot is supposed to be a function of the repository, not of the clock." >&2
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  n=$(git diff --name-only | grep -c '' || true)
  echo "check-churn: clean - $n changed file(s), all inside 10-tool-spectrum/12-submission, nothing untracked"
fi
exit $rc
