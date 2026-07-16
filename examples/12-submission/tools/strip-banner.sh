#!/usr/bin/env sh
# The normalizer POTENTIAL: strip the volatile banner lines (NONMEM version/timestamp, R session line)
# so two runs that differ only by them converge to one canonical form (L1). A pure recipe; an executor
# runs it, never plankton.
sed -E '/^NONMEM .* run at /d; /^session: pid=/d' "$1"
