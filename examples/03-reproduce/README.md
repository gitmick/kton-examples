# 03 - reproduce

Record a computation, then independently re-derive its output and prove it matches.

## What `run.sh` does

- **Create:** record a foton whose output is a deterministic result.
- **Use:** re-run the same computation (byte-identical output) and check with `plankton
  reproduces <ref> <cand>`; then tamper the output as a negative control.

## Key idea

plankton compares by **hash**. Identical output bytes reproduce at **L0** (byte-identical). Different
bytes reproduce at **none** here. (Outputs that differ only cosmetically - a timestamp, an R version -
can still match at **L1** after a declared normalizer; that is a later example.) Reproduction is a
pure hash query: plankton never re-runs anything.

## Run

```
bash run.sh
```

## Expected output

```
recorded result hash = sha256:f0a78d0b...
reproduces (re-run):   reproduction: L0
reproduces (tampered): reproduction: none (no L0/L1 match - an L2 comparator verdict is required)
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/03-reproduce/union.json&keys=data/03-reproduce/keys.json&names=data/03-reproduce/names.json)
