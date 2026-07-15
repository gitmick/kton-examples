# 04 - claim (nekton)

So far everything has been a **foton**: a machine-checkable record of a computation. But some things
cannot be re-run and verified, only *vouched for*: "I reviewed this", "this is approved". That is what
**nekton** adds. Its record is a **claim**: a signed statement *about* something. A machine can check
*who signed it*, never whether it is true, that is the whole difference between the two layers.

Assumes `plankton` and `nekton` are on your PATH. Do [01](../01-hello-foton/) first if `foton` is new.

## Walk through it, one command at a time

**1. Two identities and two registries.** plankton keeps its fotons; nekton keeps its claims. Both
registries are just directories.

```
plankton keygen analyst          # makes the foton
nekton   keygen reviewer         # makes the claim
export PLANKTON_DIR=./plankton-data
export NEKTON_DIR=./nekton-data
```

**2. The analyst records a foton** (as in example 01):

```
echo raw > data.csv ; echo fit > model.txt
plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key -o model.foton.json
plankton add model.foton.json
plankton show model.foton.json          # note the foton id, e.g. sha256:4211c41f...
```

**3. The reviewer makes a claim about that foton.** A claim spec is a small JSON file. The important
part: its **subject is the foton's id**, so the claim attaches to exactly that record.

```
cat > review.spec.json <<'JSON'
{ "subject":  [{"hash": "sha256:4211c41f..."}],
  "predicate": "pav:reviewedBy",
  "object":    {"value": "looks correct"},
  "by": "CN=Reviewer", "when": "2026-07-15T00:00:00Z" }
JSON
nekton claim review.spec.json reviewer.key review.dsse.json
nekton add review.dsse.json
```

`pav:reviewedBy` is just an opaque IRI; the kernel stores it and never interprets what it means.

**4. Use it: ask what has been said about the foton.**

```
nekton about sha256:4211c41f...
# sha256:248d1930...  predicate=pav:reviewedBy  by=CN=Reviewer  keyid=ac5ed192...
nekton show   review.dsse.json      # the full claim
nekton verify review.dsse.json reviewer.pub
# signature: VALID - verified as keyid ac5ed192... (the authoritative signer)
```

Because the claim's subject is the foton's hash, plankton (what was computed) and nekton (what people
say about it) **join at the same node**. The foton is machine-verifiable; the review is only as good
as the key that signed it, and `verify` tells you exactly which key that was.

## Or just run the whole thing

```
bash run.sh
```

## See it

The viewer shows the foton and the claim as one graph, the claim attached to the foton it is about.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/04-claim/union.json&keys=data/04-claim/keys.json&names=data/04-claim/names.json)
