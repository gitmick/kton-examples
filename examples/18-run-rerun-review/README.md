# 18 - run, rerun, review

An agent runs it, a person reruns it, two people review it, one rule decides.

The whole cycle on one script, as small as it gets. `whales.R` simulates two years of plankton density
and whale sightings and draws one figure, `whales.svg`.

## 1. An agent runs it, with its own key

`llm` is an agent session with a key of its own. It runs `whales.R`, records the run as a foton and
signs two claims about it: a **description** (`dc:description`) and a **rationale**
(`ep-plan:hasRationale`). Because the key is the session's, the record shows which session ran what and
said what about it. The texts were written by an LLM session.

## 2. A person reruns it

michael deletes the figure and runs the script again in the same folder (in [COCKPIT.md](COCKPIT.md), each participant has a checkout of their own). Same bytes, so the same
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
into the parent: each scope is a short chain of its own, and its seal goes into the parent.

## 4. Is the review valid? One query decides, plankton records it

The whole rule is one SPARQL query, `four-eyes.rq`; its hash is what the review anchored. It reads
every claim through its own nanopublication: who signed it from that claim's provenance graph, verified
against the trusted keys, and which scope it is in from that claim's pubinfo graph. A triple that merely
appears in some other claim counts for nothing. Then:

- the **owner** is whoever signed the parent scope's genesis: michael;
- the **rule holds** only if the owner anchored the review scope in the parent and signed, in the
  review scope, the rule claim that names the hash of the `four-eyes.rq` being run;
- **who is a person** counts only as the owner declared it in the parent;
- an **approval counts** only from the review scope, if its signature verifies, the owner declared its
  signer a person and not a software agent, its signer did not sign the foton (neither the llm who ran
  it nor michael who reran it), and the same signer also approved every description and rationale said
  about the foton.

Four eyes means the rule holds, at least two such approvals and no reject.

`check.sh` is the check as one recorded step. Its inputs are the signed records themselves: the llm's
claims, the parent scope and the review scope (their `.nekton.jsonl`), the foton's record, the keys we trust (`trust/`),
the rule and the script. It projects them with the kernel's own projections (`plankton export --rdf`,
`nekton export --nanopub`, both with `--trust-keys`), loads them into Oxigraph, pinned by digest, tells
the query which review scope, which foton and which rule file it checks, and runs it. Those ids are the
kernel's, computed from the content (the foton's from its envelope, the review scope's from the genesis
claim that opens its file), never a file name. The foton's lineage sits in a graph of its own, and only
there does the rule read whether the foton verifies and who signed it. There is always one row: a foton
that does not verify, a rule that does not hold or a review without verdicts says `no` explicitly.

```
foton,fotonVerified,ruleAnchored,approvalsByPeople,rejects,textsOnFoton,reviewers,fourEyesPeopleOnly
…/a02917ea…,yes,yes,2,0,2,"ana approve, ben approve",yes
```

`textsOnFoton` counts the texts said about the foton (its description and rationale), the ones under
review, not the texts someone approved. The verdict is a foton over those inputs. Run the check again
and plankton compares the bytes: **L0**.

The script ends with four rehearsals that are not in the graph, and each must say no. ana and the llm
approve:

```
…/a02917ea…,yes,yes,1,0,2,"ana approve, llm approve (not counted: software agent)",no
```

ana and ben approve the run, but not the texts:

```
…/a02917ea…,yes,yes,0,0,2,"ana approve (not counted: did not cover the description and rationale), ben approve (not counted: …)",no
```

The llm runs a review of its own: it seeds the review scope, writes the rule, anchors it in the parent
and declares itself a person there. None of that is michael's word:

```
…/a02917ea…,yes,no,1,0,2,"ana approve, llm approve (not counted: software agent)",no
```

michael declares the llm a person by mistake, and the llm approves its own run. Whoever signed the foton
does not count, person or not:

```
…/a02917ea…,yes,yes,1,0,2,"ana approve, llm approve (not counted: signed the foton)",no
```

One approval per item rather than one claim with three subjects, so each is its own signed statement and
a reviewer can approve the run but not the texts.

The same cycle with the cockpit's verbs: [COCKPIT.md](COCKPIT.md).

## Look at it

```
viewer.html?union=data/18-run-rerun-review/union.json&keys=data/18-run-rerun-review/keys.json&names=data/18-run-rerun-review/names.json
```

Every input and output carries a raw GitHub permalink pinned to a commit, so the viewer can fetch the
exact bytes. Keys are demo fixtures from fixed seeds and protect nothing; the names are labels, not
attested identities. The data are simulated.
