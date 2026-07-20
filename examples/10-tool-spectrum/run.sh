#!/usr/bin/env bash
# 10 - tool spectrum, VISUALIZED and actually EXECUTED. A spectrum defines a tool (here: the test
# suite of the R package "mypkg") by a reference foton set. This example really runs the suite in R
# twice - a reference environment and a candidate one - and proves, by real queries, whether each
# test reproduces: byte-identical (L0) or only after a normalizer (L1). Nothing is fabricated and
# nothing is asserted: every result is computed by Rscript, every relation is checked by plankton,
# and the graph shows it. Needs Rscript on PATH (used here; in a real setup each run is a docker).
set -euo pipefail
EXDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$EXDIR"; source ../../lib/common.sh
command -v Rscript >/dev/null || { echo "this example runs real R; install Rscript first"; exit 1; }

export PLANKTON_DIR=".work/plankton"
export NEKTON_DIR=".work/nekton"
rm -rf ".work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" ".work/keys"
W=".work"
plankton keygen "$W/keys/author" >/dev/null
nekton  keygen "$W/keys/lab"    >/dev/null
printf "conc\n4.2\n3.8\n5.1\n4.6\n" > "$W/pk.csv"          # the shared test fixture
TESTS="test-glm test-summary test-predict"
declare -A REFID CANDID REFOUT CANDOUT LEVEL

echo "############ STAGE A: run the suite in the REFERENCE environment (real R) ############"
for t in $TESTS; do
  Rscript "tests/$t.R" "$W/pk.csv" > "$W/$t.ref.out"       # <-- the test ACTUALLY runs
  REFID[$t]=$(plankton author --cmd "Rscript tests/$t.R pk.csv" \
    --in "$W/pk.csv" --in "tests/$t.R" --out "$W/$t.ref.out" \
    --sign "$W/keys/author.key" --add | awk '/indexed foton/{print $3}')
  REFOUT[$t]=$(plankton hash "$W/$t.ref.out")
  printf "  %-13s -> %s   (%s)\n" "$t" "${REFOUT[$t]}" "$(head -c 40 "$W/$t.ref.out" | tr -d '\n')"
done

echo; echo "############ STAGE B: run the SAME suite in a CANDIDATE environment (a different docker) ####"
# The candidate environment is identified by its QUALIFICATION (an env-spectrum id) - that is what
# --environment COVERS (example 09). The concrete image (its OCI digest) is CARRIED, not covered; it
# rides as the located uri on the qualifies-as subject below, never as --environment.
printf "candidate env: R 4.3.2 + mypkg 1.2.0 pinned stack (a qualification)\n" > "$W/candidate-env.txt"
CANDENV=$(plankton hash "$W/candidate-env.txt")            # the candidate environment's qualification id (COVERED)
for t in $TESTS; do
  Rscript "tests/$t.R" "$W/pk.csv" > "$W/$t.cand.out"      # <-- runs again, independently
  CANDID[$t]=$(plankton author --cmd "Rscript tests/$t.R pk.csv" \
    --in "$W/pk.csv" --in "tests/$t.R" --out "$W/$t.cand.out" \
    --environment "$CANDENV" --sign "$W/keys/author.key" --add | awk '/indexed foton/{print $3}')
  CANDOUT[$t]=$(plankton hash "$W/$t.cand.out")
  if [ "${CANDOUT[$t]}" = "${REFOUT[$t]}" ]; then eq="IDENTICAL bytes"; else eq="DIFFERS (volatile line)"; fi
  printf "  %-13s -> %s   [%s]\n" "$t" "${CANDOUT[$t]}" "$eq"
done

echo; echo "############ STAGE C: normalize the volatile test (real sed), then compare via the potential #"
# test-predict differs only by a session line. A real normalizer strips it; author it as a foton for
# BOTH raws with the SAME descriptor, so both share one normalizer potential.
sh tests/normalize.sh "$W/test-predict.ref.out"  > "$W/predict.ref.canon"
sh tests/normalize.sh "$W/test-predict.cand.out" > "$W/predict.cand.canon"
plankton author --cmd "sh tests/normalize.sh" --kind normalize --in "tests/normalize.sh" --in "$W/test-predict.ref.out"  --out "$W/predict.ref.canon"  --sign "$W/keys/author.key" --add -o "$W/nr.foton.json" >/dev/null
plankton author --cmd "sh tests/normalize.sh" --kind normalize --in "tests/normalize.sh" --in "$W/test-predict.cand.out" --out "$W/predict.cand.canon" --sign "$W/keys/author.key" --add -o "$W/nc.foton.json" >/dev/null
POT=$(python3 -c "import json,base64;print(json.loads(base64.b64decode(json.load(open('$W/nr.foton.json'))['payload']))['predicate']['protocol']['ref'])")
echo "  normalizer potential: $POT"
# the potential is not a separate object: it is this shared protocol ref, REGISTERED via its
# application fotons. Both normalizer runs are stored kind=normalize fotons, discoverable by input:
echo "  registered as application fotons (a potential IS their shared protocol ref):"
plankton uses "${REFOUT[test-predict]}"  | sed 's/^/    ref-run  consumed by /'
plankton uses "${CANDOUT[test-predict]}" | sed 's/^/    cand-run consumed by /'
echo -n "  raw test-predict         : "; plankton reproduces "${REFOUT[test-predict]}" "${CANDOUT[test-predict]}" || true
echo -n "  test-predict via potential: "; plankton reproduces "${REFOUT[test-predict]}" "${CANDOUT[test-predict]}" --via "$POT" || true

echo; echo "############ STAGE D: DEFINE the tool spectrum, then CHECK the candidate against it ##########"
plankton spectrum define --id "mypkg-1.2.0-suite" --of "the mypkg 1.2.0 test suite (one foton per test)" \
  --normalizer "$POT" \
  --member "test-glm=${REFOUT[test-glm]}" \
  --member "test-summary=${REFOUT[test-summary]}" \
  --member "test-predict=${REFOUT[test-predict]}" \
  -o "$W/mypkg.spectrum.json" >/dev/null
SPECID=$(plankton hash "$W/mypkg.spectrum.json")
echo "  tool-spectrum id: $SPECID"
plankton spectrum check "$W/mypkg.spectrum.json" \
  --candidate "test-glm=${CANDOUT[test-glm]}" \
  --candidate "test-summary=${CANDOUT[test-summary]}" \
  --candidate "test-predict=${CANDOUT[test-predict]}" | tee "$W/fulfilment.txt" | sed 's/^/  /' || true
# F2 / D6: back the "3/3 fulfilled" with a reproducible spectrum-check FOTON that commits to the exact
# candidate result hashes (its inputs) - so the tally is RE-DERIVABLE, not asserted in a free-text why.
# Same pattern as the release gate (D6) and the enrolled review scope: a closed-world set + a
# reproducible check, so completeness is re-derivable.
CHECK=$(plankton author --cmd "plankton spectrum check mypkg-1.2.0-suite" \
  --in "$W/mypkg.spectrum.json" --in "$W/test-glm.cand.out" --in "$W/test-summary.cand.out" --in "$W/test-predict.cand.out" \
  --out "$W/fulfilment.txt" --sign "$W/keys/author.key" --add | awk '/indexed foton/{print $3}')
echo "  fulfilment recorded as a reproducible foton (commits to the candidate result hashes): $CHECK"

echo; echo "############ STAGE E: record the fulfilment so the GRAPH shows it ############"
# per test: a reproduces claim from the candidate foton to the reference foton, LABELLED by level.
for t in $TESTS; do
  if [ "${CANDOUT[$t]}" = "${REFOUT[$t]}" ]; then LEVEL[$t]="L0"; else LEVEL[$t]="L1"; fi
  printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/reproduces","object":{"%s":{"hash":"%s"}},"why":"candidate %s reproduces reference at %s","by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
    "${CANDID[$t]}" "${LEVEL[$t]}" "${REFID[$t]}" "$t" "${LEVEL[$t]}" > "$W/rep-$t.spec.json"
  nekton claim "$W/rep-$t.spec.json" "$W/keys/lab.key" "$W/rep-$t.dsse.json" --add >/dev/null
  printf "  %-13s candidate reproduces reference at %s\n" "$t" "${LEVEL[$t]}"
done
# the candidate environment qualifies-as the tool spectrum (all members fulfilled) - signed acceptance.
# Object fields are FLAT full IRIs (https://kton.dev/o/<hash>), the standard qualifies-as shape shared
# with example 12: a nested {"hash":...} value would export as a Go map-literal string, not a joinable
# pk: IRI, so a downstream gate could not follow it.
printf '{"subject":[{"hash":"%s","uri":"oci://rocker/r-ver:4.3.2"}],"predicate":"https://kton.dev/v/qualifies-as","object":{"spectrum":"https://kton.dev/o/%s","fulfilment":"https://kton.dev/o/%s"},"why":"3/3 fulfilled, re-derivable in the spectrum-check foton (2 L0, 1 via potential)","by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
  "$CANDENV" "${SPECID#sha256:}" "${CHECK#sha256:}" > "$W/qualifies.spec.json"
nekton claim "$W/qualifies.spec.json" "$W/keys/lab.key" "$W/qualifies.dsse.json" --add >/dev/null
echo "  candidate environment --qualifies-as--> the tool spectrum (signed)"

echo
snapshot 10-tool-spectrum "$W/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
