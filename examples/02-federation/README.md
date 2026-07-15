# 02 - federation

Two people build on each other's work. The natural first thought is "put both of them on one shared
store", and that works. But often you *can't* share a store (different orgs, an air-gap, no server).
The lesson of this example is the contrast: **two separate registries still converge to the same
lineage**, by content hash, with no shared store. So we do it both ways and run the exact same query
at the end.

Three things could be "shared" here; keep them apart:

1. **the registry** (the records) - shared in Act 1, not in Act 2.
2. **the file bytes** - on one machine they just sit in the working folder the whole time; that is
   incidental. plankton stores no bytes, only hashes.
3. **nothing but hashes**, moved by `mirror` - that is Act 2.

Assumes `plankton` is on your PATH. (New to fotons? Do [example 01](../01-hello-foton/) first.)

You will see a registry named two ways below, they are interchangeable: the **`PLANKTON_DIR=<dir>`**
environment variable (prefix a single command), or the **`--registry <dir>`** flag (on the commands
that write to a store: `add`, and `author --add`). `--registry X` is simply `PLANKTON_DIR=X` for that
one command.

## Setup

```
plankton keygen alice
plankton keygen bob
echo "raw,data"     > dataset.csv
echo "cleaned,data" > cleaned.csv
echo "model=fit"    > model.txt
MODEL=$(plankton hash model.txt)     # the file we will query the lineage of, in both acts
```

## Act 1 - two people, one shared registry

**What is shared: the registry.** alice and bob both `plankton add` into the *same* `PLANKTON_DIR`,
like a shared database, or a git remote everyone pushes to.

```
mkdir shared
# alice cleans the dataset. --add files it into the shared store (--registry shared) in one step;
# -o keeps the envelope so Act 2 can re-file the SAME record elsewhere.
plankton author --cmd "clean dataset.csv cleaned.csv" \
    --in dataset.csv --out cleaned.csv --sign alice.key --add --registry shared -o alice.foton.json
# bob fits a model on alice's output, into the same store:
plankton author --cmd "fit cleaned.csv model.txt" \
    --in cleaned.csv --out model.txt --sign bob.key --add --registry shared -o bob.foton.json
```

The closing query - the full lineage of `model.txt`:

```
PLANKTON_DIR=shared plankton lineage "$MODEL"
# sha256:...  kind=script   <- bob's fit
# sha256:...  kind=script   <- alice's clean
```

## Act 2 - two separate registries, federated

Now the same two records, but each person keeps their **own** registry. Nothing is shared between the
two registries; bob's `reg-b` has never heard of alice's `reg-a`.

```
mkdir reg-a reg-b
plankton add alice.foton.json --registry reg-a    # alice's record -> registry A
plankton add bob.foton.json   --registry reg-b    # bob's record   -> registry B
```

**Federate:** registry B mirrors registry A. This moves **records (hashes)**, never the file bytes -
plankton has no bytes to move. (On this machine `cleaned.csv` still just sits in the working folder;
in reality bob would have obtained those bytes out-of-band. `mirror` did not carry them.)

```
PLANKTON_DIR=reg-b plankton mirror reg-a
# mirrored reg-a: 1 new; registry holds 2 fotons
```

Now the **same** closing query, from registry B:

```
PLANKTON_DIR=reg-b plankton lineage "$MODEL"
# sha256:...  kind=script   <- bob's fit
# sha256:...  kind=script   <- alice's clean   (arrived from A by hash)
```

**Identical to Act 1** - one merged lineage, with no shared store. That is federation: because every
record is named by the hash of its content, two independent registries converge the moment one mirrors
the other. No central server, no shared folder.

## Or just run the whole thing

```
bash run.sh
```

## See it

The viewer colours the two participants differently, so you see one federated graph from two
registries.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/02-federation/union.json&keys=data/02-federation/keys.json&names=data/02-federation/names.json)
