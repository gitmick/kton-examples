# 04 - claim (nekton)

plankton records a reproducible foton; **nekton** records a signed *opinion* about it. This shows the
two layers meeting.

## What `run.sh` does

- **ANLEGEN (create):** an analyst records a foton (plankton); a reviewer records a claim about that
  foton (nekton) whose **subject is the foton's id**.
- **VERWENDEN (use):** `nekton about <fotonId>` (what is said about it), `nekton show` (the claim),
  `nekton verify` (the reviewer's signature).

## Key idea

A **claim** is a signed subject-predicate-object statement. The predicate (`pav:reviewedBy` here) is
an opaque IRI the kernel never interprets. Because the claim's subject is the foton's content hash,
plankton and nekton **join by hash**: the same node carries the foton's provenance and the opinions
about it. A machine can *verify* a foton (re-run / hash); a person can only *vouch for* a claim (a
signature) - that is the dividing line between the two layers.

## Run

```
bash run.sh
```

## Expected output (abridged)

```
foton id = sha256:4211c41f...
-- what is said ABOUT the foton? --
sha256:248d1930...  predicate=pav:reviewedBy  by=CN=Reviewer  keyid=ac5ed192c7927918
signature:       VALID - verified as keyid ac5ed192c7927918 (the authoritative signer)
```

## See it

The viewer shows the foton and the claim as one graph, the claim attached to the foton it is about.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/04-claim/union.json&keys=data/04-claim/keys.json&names=data/04-claim/names.json)
