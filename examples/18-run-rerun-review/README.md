# 18 - run, rerun, review

The whole cycle on one script, as small as it gets. `whales.R` simulates two years of plankton density
and whale sightings and draws one figure, `whales.svg`.

## 1. An agent runs it, with its own key

`llm` is an agent session with a key of its own. It runs `whales.R`, records the run as a foton and
signs two claims about it: a **description** (`dc:description`) and a **rationale**
(`ep-plan:hasRationale`). Because the key is the session's, the record shows which session ran what and
said what about it. The texts were written by an LLM session.

## 2. A person reruns it

michael deletes the figure and runs the script again in the same checkout. Same bytes, so the same
foton: his signature lands on it as a co-signature.

```
plankton reproductions --trust-keys keys/ <hash of whales.svg>
# reproductions: 2 distinct verified signer(s) ... (↻2; 1 producer foton(s))
```

## 3. Two people review it, in a scope of its own

michael owns the review. Before anything else, he signs in the parent scope **who is who**: ana and
ben are `prov:Person`, llm is a `prov:SoftwareAgent`. A key is only a key; which keys count as people is
his decision, and it is on the record.

Then the review scope: seed, then the **rule** (the hash of `four-eyes.rq`, the query that will decide),
anchored in the parent before anyone reviews. ana and ben approve, and what they approve is named by
hash: the run (the foton) and the llm's description and rationale (their claim ids, hashes of the exact
texts). Each is one signed approval. If the llm changes its description later, that is a new claim,
and no approval covers it. The seal (the review's head) goes back
into the parent. This is the picture of the claim slide: every scope a short chain of its own, the seals
in the parent.

## 4. Is the review valid? plankton checks

The whole rule is one SPARQL query, `four-eyes.rq`; its hash is what the review anchored. It counts an
approval only if its signature verifies, its signer did not sign the foton, michael declared the
signer a person and not a software agent, and the same signer also approved every description and
rationale said about the foton. Four eyes means at least two such approvals and no reject.

`check.sh` is the check as one recorded step. Its inputs are the signed records themselves: the llm's
claims, the parent scope and the review scope (their `.nekton.jsonl`), the foton's record, the keys we trust (`trust/`),
the rule and the script. It projects them with the kernel's own projections (`plankton export --rdf`,
`nekton export --nanopub`), loads them into Oxigraph, pinned by digest, and runs the query:

```
foton,approvalsByPeople,rejects,textsReviewed,reviewers,fourEyesPeopleOnly
…/16adc85a…,2,0,2,"ben approve, ana approve",yes
```

The verdict is a foton over those inputs. Run the check again and plankton compares the bytes: **L0**.

The script ends with two rehearsals that are not in the graph. ana and the llm approve:

```
…/16adc85a…,1,0,2,"ana approve, llm approve (not counted: software agent)",no
```

ana and ben approve the run, but not the texts:

```
…/16adc85a…,0,0,2,"ben approve (not counted: did not cover the description and rationale), ana approve (not counted: …)",no
```

One approval per item rather than one claim with three subjects: a claim may name several subjects, but
`nekton export --nanopub` (v0.3.0) projects only the first, so the query would not see the others.

The same cycle with the cockpit's verbs: [COCKPIT.md](COCKPIT.md).

## Look at it

```
viewer.html?union=data/18-run-rerun-review/union.json&keys=data/18-run-rerun-review/keys.json&names=data/18-run-rerun-review/names.json
```

Every input and output carries a raw GitHub permalink pinned to a commit, so the viewer can fetch the
exact bytes. Keys are demo fixtures from fixed seeds and protect nothing; the names are labels, not
attested identities. The data are simulated.
