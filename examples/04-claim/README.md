# 04 - claim (nekton)

So far everything has been a **foton**: a machine-checkable record of a computation. But some things
cannot be re-run and verified, only *vouched for*: "I reviewed this", "this is approved". That is what
**nekton** adds. Its record is a **claim**: a signed statement *about* something. A machine can check
*who signed it*, never whether it is true, that is the whole difference between the two layers.

Assumes `plankton` and `nekton` are on your PATH. Do [01](../01-hello-foton/) first if `foton` is new.
Every command below is runnable in order (ids are captured into shell variables, nothing to retype).

## Walk through it, one command at a time

**1. Two identities and two registries.** plankton keeps its fotons; nekton keeps its claims.

```
plankton keygen analyst          # makes the foton
nekton   keygen reviewer         # makes the claim
export PLANKTON_DIR=./plankton-data NEKTON_DIR=./nekton-data
```

**2. The analyst records a foton, and we capture its id.**

```
echo raw > data.csv ; echo fit > model.txt
# --add authors + files the foton in one step; the id it prints is what we capture:
FOTON=$(plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key --add | awk '/indexed foton/{print $3}')
echo "$FOTON"                    # sha256:...
```

**3. The reviewer makes a claim about that foton.** A claim spec is a small JSON file; its **subject
is the foton's id**, so we splice in `$FOTON` (nothing to copy by hand). The subject is a *list*
because a claim can be about several things at once, here just one.

```
cat > review.spec.json <<JSON
{ "subject":  [{"hash": "$FOTON"}],
  "predicate": "pav:reviewedBy",
  "object":    {"value": "looks correct"},
  "by": "CN=Reviewer", "when": "2026-07-15T00:00:00Z" }
JSON
nekton claim review.spec.json reviewer.key review.dsse.json --add
```

`--add` files the claim as it signs it (the same `--add` / `--registry` flags exist on `nekton
claim`, `annotate`, and `seed`). We keep `review.dsse.json` here so we can `show`/`verify` it next.

`pav:reviewedBy` is just an opaque IRI; the kernel stores it and never interprets what it means.

**4. Use it: ask what has been said about the foton.**

```
nekton about "$FOTON"
# sha256:...  predicate=pav:reviewedBy  by=CN=Reviewer  keyid=...
nekton show   review.dsse.json      # the full claim
nekton verify review.dsse.json reviewer.pub
# signature: VALID - verified as keyid ... (the authoritative signer)
```

Because the claim's subject is the foton's hash, plankton (what was computed) and nekton (what people
say about it) **join at the same node**. The foton is machine-verifiable; the review is only as good
as the key that signed it.

> Note the `by: "CN=Reviewer"` is a **self-asserted label**, anyone can type any name there. What is
> cryptographically real is the **keyid** that `verify` reports; mapping that key to a
> real-world identity is a trust decision you make, not something the record proves.

## Or just run the whole thing

```
bash run.sh
```

## See it

The viewer shows the foton and the claim as one graph, the claim attached to the foton it is about.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/04-claim/union.json&keys=data/04-claim/keys.json&names=data/04-claim/names.json)
