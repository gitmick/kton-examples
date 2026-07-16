#!/usr/bin/env sh
# The normalizer POTENTIAL: strip the volatile "session:" line so two runs that differ only by that
# line converge to one canonical form (L1). A pure recipe - plankton never runs it, an executor does.
sed '/^session:/d' "$1"
