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
anchored in the parent before anyone reviews. ana and ben approve. The seal (the review's head) goes back
into the parent. This is the picture of the claim slide: every scope a short chain of its own, the seals
in the parent.

## 4. Is the review valid? plankton checks

`four-eyes.rq` runs over the review's nanopublications and the plankton lineage. It counts an approval
only if its signature verifies, its signer did not sign the foton, and michael declared the signer a
person. Four eyes means at least two such approvals and no reject.

```
ben      approve  counted
ana      approve  counted
approvals by people: 2
four eyes, people only: yes
```

The verdict is not a printout: it is a foton whose inputs are the query, the script, the lineage and
the review. Run it again on the same inputs and plankton compares the bytes: **L0**.

The script ends with a rehearsal that is not in the graph: ana and the llm approve.

```
llm      approve  not counted: software agent
ana      approve  counted
four eyes, people only: no
```

## Look at it

```
viewer.html?union=data/18-run-rerun-review/union.json&keys=data/18-run-rerun-review/keys.json&names=data/18-run-rerun-review/names.json
```

Every input and output carries a raw GitHub permalink pinned to a commit, so the viewer can fetch the
exact bytes. Keys are demo fixtures from fixed seeds and protect nothing; the names are labels, not
attested identities. The data are simulated.
