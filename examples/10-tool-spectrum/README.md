# 10 - tool spectrum, executed and visualized

A **spectrum** defines a tool by a reference foton set: a candidate fulfils it when it reproduces
every reference output. This is the executed, graphed companion to
[example 09](../09-environment/): the same spectrum and `--environment` idea, but the tests **really
run** and you watch L0 vs L1 in the viewer. It takes a real tool - the test suite of an R package,
`mypkg`, **one foton per test** - and answers, in the graph, the three questions you should always ask:

- **did the tests really run?** Yes. `run.sh` executes each test with `Rscript` twice (a reference
  environment and a candidate one). Nothing is fabricated; the fotons record real outputs.
- **are they identical?** Two of the three are byte-identical across environments (**L0**).
- **were they normalized?** The third prints a volatile `session:` line (pid + wall-clock), so its two
  runs are *not* identical - they agree only after a real normalizer strips that line (**L1**). That
  normalizer is a **potential**: a content-addressed recipe, named by its own hash (more below).

Every result is computed by running R; every relation (`reproduces`, `via` a normalizer, spectrum
`fulfils`) is checked by a real `plankton` query, not asserted. Then it is recorded so the viewer
shows it. It needs `Rscript` on your PATH.

## What actually runs

```
STAGE A  reference env   Rscript tests/test-*.R pk.csv   -> 3 reference fotons  -> define the spectrum
STAGE B  candidate env   Rscript tests/test-*.R pk.csv   -> 3 candidate fotons  (--environment <candidate image>)
STAGE C  normalize       sh tests/normalize.sh           -> 2 normalizer fotons (strip the volatile line)
STAGE D  plankton spectrum check                         -> test-glm/summary identical, test-predict via potential = 3/3
STAGE E  nekton claims: reproduces (L0/L0/L1) + qualifies-as                    -> recorded for the graph
```

Real output from a run:

```
test-glm      -> sha256:1ebd..   (test-glm: mean-conc=4.4250 PASS)      reference
test-glm      -> sha256:1ebd..   [IDENTICAL bytes]                      candidate  -> L0
test-predict  -> sha256:b9a1..   (session: pid=5690 at=2026-07-16 ...)  reference
test-predict  -> sha256:467e..   [DIFFERS (volatile line)]             candidate  -> not L0
  raw test-predict         : reproduction: none
  test-predict via potential: reproduction: L1
```

## What you see in the graph

Open the graph and every node is re-verified in your browser (Ed25519/DSSE, green ring). Per test:

- the **reference run** and the **candidate run** are two foton nodes, both fanning out from the same
  `pk.csv` fixture and test script (shared source nodes) - so you can see both actually ran.
- a **`reproduces` claim** links the candidate run to the reference run, labelled **`L0`** (identical)
  or **`L1`** (only after the normalizer). That label is the answer to "identical or normalized?",
  drawn on the edge.
- for `test-predict`, two **`normalize.sh` fotons** sit between the raw runs and the canonical form -
  the normalization is a real recorded step, not a hand-wave.
- a **`qualifies-as` claim** carries a **`spectrum`** edge to the tool-spectrum node and a
  **`fulfilment`** edge to a reproducible **spectrum-check foton** whose inputs are the exact candidate
  result hashes: so "2 x L0, 1 x L1 = 3/3" is **re-derivable** (re-run the check over those inputs and
  you get the same tally), not asserted in a free-text note. The candidate environment is accepted as
  `mypkg-1.2.0`. (Same pattern as the release gate and the enrolled review scope: a closed-world set
  plus a reproducible check, so completeness is re-derivable.)

## Why two runs are two nodes

The candidate run is authored with `--environment <candidate env-spectrum>` - a COVERED *qualification*
(not the concrete image, which is CARRIED; see [example 09](../09-environment/)) - so it has a different
foton id from the reference run even when the output bytes are identical. That is the point of a tool spectrum: the *same result from a different
environment* is a distinct computation that nonetheless **reproduces** the reference - which is
exactly what qualifies the environment.

## Are the normalizers registered as potentials?

Yes - and it is worth being precise about what that means. A **potential is not a separate object
type** and there is no "register a potential" step. A potential is identified by its **protocol ref**
(the content address of the normalizer recipe), and it is registered *by virtue of its application
fotons being in the store*. Here both normalizer runs are `--add`ed as `kind=normalize` fotons and are
discoverable - `plankton uses <raw-output>` returns the normalize foton that consumed it - and both
carry the **same** `protocol.ref`. That shared ref **is** the potential: `spectrum define --normalizer
<ref>` records it in the spectrum, and both `plankton reproduces --via <ref>` and `plankton spectrum
check` (which reads the `normalizer` from the spectrum) resolve L1 by finding a registered foton whose
effective ref matches. (`--via` also accepts a normalizer foton id, which the registry resolves to that
ref; and `--normalizer`/`--normaliser` are accepted spellings of the same flag.) So the potential is
registered, discoverable, and content-addressed - just not as a standalone record.

## The kernel line

`plankton spectrum check` renders no verdict: "fulfilled (identical)" and "fulfilled (via potential)"
are reproducible facts about hashes. Naming that "validated at L0/L1" and *accepting* the tool as
qualified is a signed nekton claim on top - here the `reproduces` and `qualifies-as` claims. plankton
compares; it never ran the tests and never ran the normalizer. An executor (your R, your docker) did.

**L1 is only as honest as the normalizer.** A normalizer that strips too much (say, blanks the whole
result, not just the volatile `session:` line) would make anything "reproduce". kton does not judge
that - it pins *which* normalizer was used (a content-addressed foton, auditable byte-for-byte) so a
reviewer can see exactly what was normalized away and reject an over-normalizing recipe. The guarantee
is "these exact bytes agree after this exact, named transformation", not "the results are equivalent".

**The `qualifies-as` claim carries its corpus.** "3/3 fulfilled" does not ride as a bare adjective on
the claim: its object cites the **spectrum-check foton** (whose inputs are the spectrum plus the
candidate results), so a reader re-derives the tally instead of trusting it. [Example 12](../12-submission/)
makes a release gate *require* exactly this - a qualification with no such foton does not pass.

**Qualification is monotone, not a closed world.** A spectrum defines a *set*, and qualification asks
for completeness over it - which sounds closed-world, but is not. The member set is pinned by the
spectrum's hash (it travels, it is not discovered per source), and each member check is a *positive*
existence ("a fulfilling foton exists"). So reading more sources can only turn *incomplete* into
*complete*, never revoke a qualification - the same monotonicity the [federation example](../02-federation/)
relies on. "Not yet 3/3" means *not yet established*, not *failed*.

## Run it yourself

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/10-tool-spectrum/union.json&keys=data/10-tool-spectrum/keys.json&names=data/10-tool-spectrum/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
