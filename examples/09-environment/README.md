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
runs and the docker runs happen in an executor elsewhere; here small files stand in for their
outputs, exactly the fotons such an executor would `plankton add`.

## The arc

### 1. Run it locally (unqualified)

```
plankton author --cmd "Rscript fit.R" --in pk.csv --in fit.R --out fit.out --sign author.key --add
```

You get a foton: inputs, command, output, all by hash. It is reproducible in the sense that the bytes
are pinned - but it says nothing about the R version, the packages, or the OS it ran under.

### 2. Pin the exact docker image (CARRIED)

You actually ran inside a digest-pinned image, `rocker/r-ver:4.3.2@sha256:...`. A digest fixes the
image byte-for-byte. But per **SPEC 6.5** this concrete environment data is **CARRIED, not covered**:
it must never change a foton id, because two different images that behave identically are not two
different results. So it does not go *into* the foton's identity; it rides in the nekton layer as
provenance - here a `prov:used` claim on the result:

```
{"subject":[{"hash":"<foton>"}],"predicate":"http://www.w3.org/ns/prov#used",
 "object":{"id":"oci://rocker/r-ver:4.3.2@sha256:..."}}
```

This records *which* image. It does **not** assert the image is right - a digest proves sameness, not
correctness. That is what the spectrum is for.

### 3. Specify a spectrum (COVERED)

A **spectrum** defines a tool or environment *structurally*: the set of reference fotons a conforming
stack must reproduce, plus an optional normalizer. We define the qualified environment as the R
package's test suite at exact versions - **one foton per test** (test fixture + script -> result):

```
plankton spectrum define --id "r-4.3.2-mypkg-1.2.0" \
  --of "R 4.3.2 + mypkg 1.2.0 (pinned deps): the whole test suite must reproduce" \
  --member "test-glm=sha256:..." --member "test-summary=sha256:..." --member "test-predict=sha256:..."
```

The spectrum's own content hash is its **env-spectrum id**. Now author the analysis *under* that
qualified environment:

```
plankton author --cmd "Rscript fit.R" ... --environment sha256:<envSpectrumId> --sign author.key --add
```

`--environment` rides inside the protocol descriptor, so it is **COVERED** - part of `protocol.ref`,
the action key, and the foton id. The unqualified foton and the qualified one have **different ids**:
"produced under a qualified-R environment" is a genuinely distinct computation. Crucially it names the
*qualification* (the spectrum), never a single image - any stack that fulfils the spectrum counts.

### 4. Verify the docker fulfils the spectrum

Run the suite inside the pinned image and check each result reproduces the reference set:

```
plankton spectrum check mypkg.spectrum.json \
  --candidate "test-glm=sha256:..." --candidate "test-summary=sha256:..." --candidate "test-predict=sha256:..."
#   test-glm       fulfilled (identical)
#   test-summary   fulfilled (identical)
#   test-predict   fulfilled (identical)
#   3/3 member(s) fulfilled
```

A wrong-version image where one test result differs is **refused**: partial fulfilment is
non-fulfilment (SPEC Clause 10), and `spectrum check` exits nonzero. `check` renders no verdict of its
own - "fulfilled" is a reproducible fact; whether you *accept* the image as qualified is a signed
claim on top. So sign it, binding the exact image to the env-spectrum:

```
{"subject":[{"hash":"sha256:<ociDigest>","uri":"oci://rocker/r-ver:4.3.2@sha256:..."}],
 "predicate":"https://kton.dev/v/qualifies-as",
 "object":{"id":"https://kton.dev/o/<envSpectrumId>"}}
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
