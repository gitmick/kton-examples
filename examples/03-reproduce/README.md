# 03 - reproduce

Example 01 said plankton *records* a computation but never runs it. So how do you ever check that a
result is real? You **re-derive it yourself and compare hashes.** Identical bytes reproduce at **L0**;
anything else does not. plankton never re-runs your code; it just compares fingerprints.

Assumes `plankton` is on your PATH. (Start with [example 01](../01-hello-foton/) if `foton` is new.)

## Walk through it, one command at a time

**1. Record a computation whose output is deterministic.**

```
plankton keygen me
echo "1 2 3 4" > input.txt
echo "sum=10"  > result.txt
plankton author --cmd "sum input.txt result.txt" \
    --in input.txt --out result.txt --sign me.key -o sum.foton.json
plankton add sum.foton.json
```

Remember the output's hash, that is what we will reproduce:

```
plankton hash result.txt
# sha256:...
```

**2. Re-derive the output and compare.** A real re-run would execute `sum` again; here, because it is
deterministic, we just recreate the same bytes. Then ask plankton if they reproduce:

```
echo "sum=10" > result_rerun.txt
plankton reproduces $(plankton hash result.txt) $(plankton hash result_rerun.txt)
# reproduction: L0
```

**L0** means byte-identical. That is the strongest form: the re-run produced exactly the recorded
output.

**3. Prove it is not just always saying yes.** Tamper with the output and try again:

```
echo "sum=999" > result_tampered.txt
plankton reproduces $(plankton hash result.txt) $(plankton hash result_tampered.txt)
# reproduction: none (no L0/L1 match - an L2 comparator verdict is required)
```

Different bytes, no match. `reproduces` is a pure hash comparison, so it cannot be fooled.

The `none` line mentions two levels plankton does *not* decide by hashing alone:

> **L1** is for outputs that differ only cosmetically (a timestamp, a library version): they match
> after a declared normalizer strips the noise, still a hash check, just after normalizing. **L2** is
> a human or tool judging two results "close enough" within a tolerance (say, numerically equal to 3
> digits); plankton cannot compute that, so it reports `none` and names L2 as the next option. L0 is
> the plain byte-identical case shown here.

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/03-reproduce/union.json&keys=data/03-reproduce/keys.json&names=data/03-reproduce/names.json)
