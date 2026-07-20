#!/usr/bin/env bash
# 09 - environment: the whole arc, from "I just ran it" to "this exact container is a QUALIFIED
# environment". Four stages, each motivated by the gap in the one before:
#   1. run it locally               -> a result, but nothing said about the stack it ran in
#   2. pin the exact docker image   -> proves WHICH image (sameness), but not that the image is right
#   3. specify a spectrum           -> defines WHAT a qualified env must reproduce (one foton per test)
#   4. verify the docker fulfils it -> proves THIS image meets the definition, then signs the binding
#
# The spectrum here is concrete: the test suite of an R package at exact versions, ONE FOTON PER TEST.
# The environment is DEFINED by the set of test results a conforming stack must reproduce.
#
# Headless like 01-07: plankton compares fotons by hash and RUNS NOTHING. The R runs and the docker
# runs happen in an executor elsewhere; here we stand in for their outputs with small files, exactly
# the fotons such an executor would `plankton add`.
set -euo pipefail
cd "$(dirname "$0")"
source ../../lib/common.sh

# Two registries (both just directories): plankton = results, nekton = signed statements.
export PLANKTON_DIR="$PWD/.work/plankton"
export NEKTON_DIR="$PWD/.work/nekton"
export NEKTON_ALIASES="$PWD/../../aliases.json"
rm -rf "$PWD/.work"; mkdir -p "$PLANKTON_DIR" "$NEKTON_DIR" "$PWD/.work/keys"
cd "$PWD/.work"
plankton keygen keys/author >/dev/null    # produces the results
nekton  keygen keys/lab    >/dev/null     # signs the environment statements

# the exact container the analyst ran in (a digest-pinned image). Same one all the way through.
OCI="oci://rocker/r-ver:4.3.2@sha256:d34db33fcaf00000000000000000000000000000000000000000000000000beef"
OCIDIGEST="sha256:d34db33fcaf00000000000000000000000000000000000000000000000000beef"

echo "############ STAGE 1: run it locally, unqualified ############"
printf "id,conc\n1,4.2\n2,3.8\n" > pk.csv
printf 'd <- read.csv("pk.csv"); cat(sprintf("cl=%%.3f\\n", mean(d$conc)))\n' > fit.R
printf "cl=4.000\n" > fit.out                                   # what your local R produced
BARE=$(plankton author --cmd "Rscript fit.R" --in pk.csv --in fit.R --out fit.out \
  --sign keys/author.key --add | awk '/indexed foton/{print $3}')
echo "  foton: $BARE"
echo "  no environment recorded: reproducible BYTES, but silent about the R stack behind them."

echo; echo "############ STAGE 2: pin the exact docker image (CARRIED, opaque to plankton) ############"
echo "  you actually ran inside $OCI"
echo "  a digest pins WHICH image byte-for-byte. Per SPEC 6.5 this concrete env-data is CARRIED: it"
echo "  never changes a foton id (two different images that behave the same are not different results)."
echo "  so it rides in the nekton layer as provenance - here, prov:used on the result:"
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/prov#used","object":{"id":"%s"},"why":"produced inside this exact image","by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
  "$BARE" "$OCI" > used.spec.json
nekton claim used.spec.json keys/lab.key used.dsse.json --add >/dev/null
echo "  recorded. But a pin only proves SAMENESS - it does not say the image is CORRECT. For that:"

echo; echo "############ STAGE 3: specify a spectrum = the pkg test suite, ONE FOTON PER TEST ############"
echo "  define the qualified environment structurally: the exact-version test results it must reproduce."
for t in test-glm test-summary test-predict; do
  printf 'd <- readLines("%s.fixture"); cat("%s: PASS\\n")\n' "$t" "$t" > "$t.R"  # the test script (like fit.R)
  echo "fixture-$t" > "$t.fixture"
  printf "%s: PASS\n" "$t" > "$t.result"          # the gold result at the pinned versions (illustrative stand-in)
  # bind the test SCRIPT itself as a covered input - a foton whose --cmd names a script but does not --in
  # it would not actually pin the code that produced the result.
  plankton author --cmd "Rscript $t.R $t.fixture" --in "$t.R" --in "$t.fixture" --out "$t.result" \
    --sign keys/author.key --add >/dev/null
  echo "  reference foton: $t -> $(plankton hash "$t.result")"
done
plankton spectrum define --id "r-4.3.2-mypkg-1.2.0" \
  --of "R 4.3.2 + mypkg 1.2.0 (pinned deps): the whole test suite must reproduce" \
  --member "test-glm=$(plankton hash test-glm.result)" \
  --member "test-summary=$(plankton hash test-summary.result)" \
  --member "test-predict=$(plankton hash test-predict.result)" \
  -o mypkg.spectrum.json
SPECID=$(plankton hash mypkg.spectrum.json)
echo "  env-spectrum id: $SPECID"
echo
echo "  now author the analysis UNDER that qualified environment (--environment). It is COVERED:"
QUAL=$(plankton author --cmd "Rscript fit.R" --in pk.csv --in fit.R --out fit.out \
  --environment "$SPECID" --sign keys/author.key --add | awk '/indexed foton/{print $3}')
echo "    unqualified foton: $BARE"
echo "    qualified   foton: $QUAL"
echo "    -> different foton id and action key: 'produced under a qualified-R env' is a DISTINCT"
echo "       computation. It names the QUALIFICATION (the spectrum), never one image."

echo; echo "############ STAGE 4: verify a docker container FULFILS the spectrum ############"
echo "  run the suite inside the pinned image; check each test result reproduces the reference set."
echo "  -- the pinned image (rocker/r-ver:4.3.2) reproduces all three: --"
for t in test-glm test-summary test-predict; do printf "%s: PASS\n" "$t" > "cand-$t.result"; done
plankton spectrum check mypkg.spectrum.json \
  --candidate "test-glm=$(plankton hash cand-test-glm.result)" \
  --candidate "test-summary=$(plankton hash cand-test-summary.result)" \
  --candidate "test-predict=$(plankton hash cand-test-predict.result)" | sed 's/^/    /'
echo
echo "  -- a WRONG-version image (mypkg 1.3.0): one test result differs -> qualification refused: --"
printf "test-predict: FAIL (predict.glm output changed in 1.3.0)\n" > cand-test-predict.result
if plankton spectrum check mypkg.spectrum.json \
  --candidate "test-glm=$(plankton hash cand-test-glm.result)" \
  --candidate "test-summary=$(plankton hash cand-test-summary.result)" \
  --candidate "test-predict=$(plankton hash cand-test-predict.result)" 2>&1 | sed 's/^/    /'
then :; else echo "    (exit nonzero: partial fulfilment is NON-fulfilment, SPEC Clause 10)"; fi

echo; echo "############ STAGE 4b: SIGN the binding - this exact image qualifies-as the env-spectrum ##"
echo "  fulfilment is a reproducible FACT; ACCEPTING the image as qualified is a signed claim on top:"
printf '{"subject":[{"hash":"%s","uri":"%s"}],"predicate":"https://kton.dev/v/qualifies-as","object":{"id":"https://kton.dev/o/%s"},"why":"rocker/r-ver:4.3.2 reproduced the mypkg 1.2.0 suite 3/3","by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
  "$OCIDIGEST" "$OCI" "${SPECID#sha256:}" > qualifies.spec.json
nekton claim qualifies.spec.json keys/lab.key qualifies.dsse.json --add >/dev/null
nekton show qualifies.dsse.json | sed 's/^/    /'
echo
echo "  the join: fit.out --environment--> the env-spectrum <--qualifies-as-- the exact image."
echo "  anyone can compose them: the result names a qualification; the image is certified to meet it."

echo
cd "$OLDPWD"
snapshot 09-environment "$PWD/.work/keys" --reg "$PLANKTON_DIR" --reg "$NEKTON_DIR"
