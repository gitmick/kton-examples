# 09 - environment: from "I ran it" to a qualified environment

A result is only as trustworthy as the environment that produced it. This example walks the whole
arc, in four stages, each one fixing the gap in the stage before:

1. **run it locally** - you get a result, but nothing is recorded about the stack it ran in.
2. **pin the exact docker image** - now you know *which* image byte-for-byte, but a pin only proves
   sameness, not that the image is *correct*.
3. **specify a spectrum** - define what a qualified environment must *do*: reproduce a fixed set of
   results. Here that set is the **test suite of an R package at exact versions, one foton per test**.
4. **verify the docker fulfils the spectrum** - prove *this* image reproduces every test, then sign
   the binding so others can rely on it.

Like examples 01-07 it is headless: `plankton` compares fotons by hash and **runs nothing**. The R
runs and the docker runs happen in an executor elsewhere; here small files stand in for their outputs,
exactly the fotons such an executor would `plankton add`. (For the same spectrum idea *actually
executed* - real R runs, with L0 vs L1 shown in the graph - see
[example 10](../10-tool-spectrum/), the executed companion to this one.)

## The arc

The blocks below capture ids into shell variables and run in sequence (`plankton` and `nekton` on your
PATH, a writable scratch dir). This is exactly what `run.sh` does.

```
export PLANKTON_DIR=$PWD/reg NEKTON_DIR=$PWD/reg-n
plankton keygen author >/dev/null; nekton keygen lab >/dev/null
```

### 1. Run it locally (unqualified)

```
printf "conc\n4.2\n3.8\n"  > pk.csv
echo   "cl=4.000"          > fit.out          # a stand-in for what your local R produced
BARE=$(plankton author --cmd "Rscript fit.R" --in pk.csv --out fit.out \
        --sign author.key --add | awk '/indexed foton/{print $3}')
```

`$BARE` is a foton: inputs, command, output, all by hash. The bytes are pinned - but it says nothing
about the R version, the packages, or the OS it ran under.

### 2. Pin the exact docker image (CARRIED)

You actually ran inside a digest-pinned image. A digest fixes the image byte-for-byte, but this
concrete environment data is **CARRIED, not covered**: it must never change a foton id, because two
different images that behave identically are not two different results. So it does not go *into* the
foton's identity; it rides in the nekton layer as provenance - a `prov:used` claim on the result:

```
OCI="oci://rocker/r-ver:4.3.2@sha256:d34db33f...beef"     # the exact image you ran in
printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/prov#used","object":{"id":"%s"},"by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
  "$BARE" "$OCI" > used.spec.json
nekton claim used.spec.json lab.key --add
```

This records *which* image. It does **not** assert the image is right - a digest proves sameness, not
correctness. That is what the spectrum is for.

### 3. Specify a spectrum (COVERED)

A **spectrum** defines a tool or environment *structurally*: the set of reference fotons a conforming
stack must reproduce, plus an optional normalizer. We define the qualified environment as the R
package's test suite at exact versions - **one foton per test** (fixture + script -> result). First
author the reference test fotons, then define the spectrum from their output hashes:

```
for t in test-glm test-summary test-predict; do
  printf "%s: PASS\n" "$t" > "$t.result"; echo "fixture-$t" > "$t.fixture"
  plankton author --cmd "Rscript tests/$t.R" --in "$t.fixture" --out "$t.result" \
    --sign author.key --add >/dev/null
done
plankton spectrum define --id "r-4.3.2-mypkg-1.2.0" \
  --of "R 4.3.2 + mypkg 1.2.0 (pinned deps): the whole test suite must reproduce" \
  --member "test-glm=$(plankton hash test-glm.result)" \
  --member "test-summary=$(plankton hash test-summary.result)" \
  --member "test-predict=$(plankton hash test-predict.result)" -o mypkg.spectrum.json
SPECID=$(plankton hash mypkg.spectrum.json)      # the spectrum's content hash = its env-spectrum id
```

Now author the analysis *under* that qualified environment:

```
QUAL=$(plankton author --cmd "Rscript fit.R" --in pk.csv --out fit.out \
        --environment "$SPECID" --sign author.key --add | awk '/indexed foton/{print $3}')
```

`--environment` rides inside the protocol descriptor, so it is **COVERED** - part of `protocol.ref`,
of the **action key** (the reuse/cache key derived from a foton's inputs and protocol), and so of the
foton id. `$BARE` and `$QUAL` therefore have **different ids**: "produced under a qualified-R
environment" is a genuinely distinct computation. Crucially it names the *qualification* (the
spectrum), never a single image - any stack that fulfils the spectrum counts.

### 4. Verify the docker fulfils the spectrum

Run the suite inside the pinned image and check each result reproduces the reference set (here the
candidate outputs happen to match, so we reuse the reference `.result` files):

```
plankton spectrum check mypkg.spectrum.json \
  --candidate "test-glm=$(plankton hash test-glm.result)" \
  --candidate "test-summary=$(plankton hash test-summary.result)" \
  --candidate "test-predict=$(plankton hash test-predict.result)"
#   test-glm       fulfilled (identical)
#   test-summary   fulfilled (identical)
#   test-predict   fulfilled (identical)
#   3/3 member(s) fulfilled
```

A wrong-version image where one test result differs is **refused**: partial fulfilment is
non-fulfilment, and `spectrum check` exits nonzero. `check` renders no verdict of its own - "fulfilled"
is a reproducible fact; whether you *accept* the image as qualified is a signed claim on top. So sign
it, binding the exact image to the env-spectrum:

```
DIGEST="sha256:d34db33f...beef"                  # the image's own digest
printf '{"subject":[{"hash":"%s","uri":"%s"}],"predicate":"https://kton.dev/v/qualifies-as","object":{"id":"https://kton.dev/o/%s"},"by":"CN=Lab","when":"2026-07-16T00:00:00Z"}' \
  "$DIGEST" "$OCI" "${SPECID#sha256:}" > qualifies.spec.json
nekton claim qualifies.spec.json lab.key --add
```

## COVERED vs CARRIED, in one line

- **env-spectrum reference** (a *qualification*) is **COVERED**: it changes the foton id, because a
  result produced under a qualified environment is a different computation.
- **concrete env-data** (an OCI digest, a lockfile hash - *which exact stack*) is **CARRIED**: opaque
  to the kernel, never part of any identity, bound to a spectrum by a signed `qualifies-as` claim.

That split is the whole point: many concrete images can fulfil one qualification, so the qualification
is what a result commits to, and each image is separately certified to meet it.

## The join

```
   fit.out  --environment-->  env-spectrum  <--qualifies-as--  rocker/r-ver:4.3.2@sha256:...
   (the result names a          (the definition)                (the exact image, certified
    qualification)                                               to meet the definition)
```

Anyone can compose these independently authored records: the result names a qualification; the image
is proven to fulfil it. No central authority, no shared server - just content-addressed records that
meet at shared hashes. Open the graph to see all five fotons and both claims as one picture.

## Run it yourself

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/09-environment/union.json&keys=data/09-environment/keys.json&names=data/09-environment/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
