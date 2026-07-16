# 11 - review template: the classical way to author a claim

[Example 04](../04-claim/) wrote a claim by hand, as raw JSON. That is the mechanism, but it is not how
you actually work. The classical way is a **template**: a named, typed, shareable form that turns
"approve or reject this foton and attach a comment" into one `nekton annotate` call - with the
vocabulary already chosen, aliases resolved, files hashed, and the timestamp stamped for you.

This example uses a `review/decision` template, has **three independent reviewers each approve** the
same foton, checks the review was done correctly (different participants, nothing overwritten), shows
the template itself **registered as a federated record**, and finally **exports the RDF and runs a
SPARQL query that tests the review is complete**.

## Reused vocabulary, no minted terms

The template commits to published vocabularies (per the repo's vocabulary policy):

- the review relation is **PAV** `pav:reviewedBy`;
- the verdict reuses **schema.org**: approve = `schema:AcceptAction`, reject = `schema:RejectAction`
  (as the type of the review node), so `approve`/`reject` are not local strings but standard IRIs;
- the comment is a **file**, hashed to a content ref and attached as `nk:evidence`.

```
nekton templates --show review/decision
#   predicate: http://purl.org/pav/reviewedBy
#   fields:  decision  enum  REQUIRED  {https://schema.org/AcceptAction|https://schema.org/RejectAction}
#            comment   file  optional  role=evidence
```

## Authoring a review

Each reviewer runs one command - no JSON, no `jq`, no `openssl`:

```
nekton annotate --foton foton.dsse.json --template review/decision \
    --set decision=https://schema.org/AcceptAction --set comment=alice.md \
    --by "CN=Alice" --sign alice.key --add
```

`--foton` resolves the subject to the foton's id (so the review joins plankton's index; `nekton about
<fotonId>` and plankton lineage align on the same hash). The claim comes out as
`foton pav:reviewedBy [ a schema:AcceptAction ; nk:evidence <comment> ]`, signed by Alice.

## Did we review it correctly?

Three reviewers - Alice, Bob, Carol - each approve. The run checks:

- **different participants:** three *distinct signing keyids* on the reviews (the `by` label is just
  text; the keyid is the cryptographic identity, see [example 07](../07-identity/)).
- **nothing overwritten:** three *distinct content-addressed claims* on disk. nekton is append-only;
  a second review never mutates a first. `nekton about <foton>` lists all three.
- **all on approve:** every verdict is `schema:AcceptAction`, none `schema:RejectAction`.

## The template is federated data, registered separately

A template is not part of the protocol - the kernel prescribes no vocabulary (spec Clause 7). It is
**data**, content-addressed like anything else, and it federates. The run registers the template in a
**separate** nekton registry (the publisher's), as a signed record - `<template hash> rdf:type
kton.dev/template/v0` - then a consumer `nekton mirror`s the two registries (as in
[example 02](../02-federation/)) so the template *definition* resolves by hash right next to the
reviews built from it. Anyone can fetch the exact form a reviewer used and verify who published it.

## Testing completeness with SPARQL

The run exports the merged RDF - `plankton export --rdf` (the foton's PROV lineage) plus each review as
a **nanopublication** (`nekton export --nanopub`) - and runs the shipped query
[`completeness.rq`](completeness.rq). Each review is its own named graph, so the query joins each
verdict to the reviewer in that graph's provenance and tallies distinct reviewers per verdict:

```
SELECT ?verdict (COUNT(DISTINCT ?reviewer) AS ?reviewers) WHERE {
  GRAPH ?review { ?foton pav:reviewedBy ?r . ?r rdf:type ?verdict . }
  ?review prov:wasAttributedTo ?reviewer .
  FILTER(?verdict IN (schema:AcceptAction, schema:RejectAction))
} GROUP BY ?verdict
```

The completeness policy (all required reviewers approve, no rejects) is applied to the tally:

```
approve (schema:AcceptAction): 3
reject  (schema:RejectAction): 0
REVIEW COMPLETE: True  (approvals=3/3, rejects=0)
```

A missing approval or any single reject flips it to incomplete - the query is the gate. (The SPARQL
step needs `rdflib`: `pip install rdflib`.)

**Boundary (honest):** this counts *distinct signing keys*, not verified enrolled reviewers - three
sock-puppet keys would satisfy "3/3". Turning a threshold count into a real required-set check needs a
sealed enrolment (who the required reviewers are) plus their `sec:controller` identities, vouched by an
authority - the enrolment boundary named in [example 12](../12-submission/) and the protocol's Trust
chapter. This example shows the *mechanism* (typed reviews + a re-derivable completeness query); the
enrolment authority on top is a separate step.

## Run it yourself

```
bash run.sh
```

Open the graph to see the foton with its three approving reviews (each a distinct signer) and the
registered template as one picture.
