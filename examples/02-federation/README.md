# 02 - federation

Two people, two **registries**, no shared folder and no server, yet they end up with one lineage. This
is the example for the two things people found unclear: how a registry is pointed at, and how records
move between two of them.

> A **registry** is the *store*: the directory where plankton files its records, set by `PLANKTON_DIR`.
> It is **not** an execution environment (a container, an OS, a tool). This example is only about two
> stores.

Assumes `plankton` is on your PATH. (New to fotons? Do [example 01](../01-hello-foton/) first.)

## Walk through it, one command at a time

**1. Two people, two identities.**

```
plankton keygen alice
plankton keygen bob
```

**2. Two registries.** A registry is just a directory. We keep two and never point at both at once;
we pick one per command with an inline `PLANKTON_DIR=...`.

```
mkdir reg-a reg-b
```

**3. Alice records a foton in registry A.** She cleans a dataset:

```
echo "raw,data"     > dataset.csv
echo "cleaned,data" > cleaned.csv
PLANKTON_DIR=reg-a plankton author --cmd "clean dataset.csv cleaned.csv" \
    --in dataset.csv --out cleaned.csv --sign alice.key -o alice-clean.foton.json
PLANKTON_DIR=reg-a plankton add alice-clean.foton.json
```

**4. Bob records a foton in registry B** that consumes alice's output (`cleaned.csv`). Note his
registry B knows nothing about A yet.

```
echo "model=fit" > model.txt
PLANKTON_DIR=reg-b plankton author --cmd "fit cleaned.csv model.txt" \
    --in cleaned.csv --out model.txt --sign bob.key -o bob-fit.foton.json
PLANKTON_DIR=reg-b plankton add bob-fit.foton.json
```

**5. Federate: registry B mirrors registry A.** This copies A's records into B by content hash, no
network, no shared directory.

```
PLANKTON_DIR=reg-b plankton mirror reg-a
# mirrored reg-a: 1 new; registry holds 2 fotons
```

**6. Use it: from B, the two registries are now one lineage.** Ask who consumed alice's cleaned file,
and walk bob's model back to its root:

```
PLANKTON_DIR=reg-b plankton uses    $(plankton hash cleaned.csv)   # -> bob's fit
PLANKTON_DIR=reg-b plankton lineage $(plankton hash model.txt)     # -> bob's fit, then alice's clean
```

Bob's fit references a file only alice produced, and because both are named by the same hash, the two
registries join into one graph the moment B mirrors A. That join is the whole point of federation: no
central server, records converge by content.

## Or just run the whole thing

```
bash run.sh
```

The script uses throwaway `reg-a/` and `reg-b/` folders and builds the graph snapshot.

## See it

The viewer colours the two participants differently, so you see one federated graph from two
registries.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/02-federation/union.json&keys=data/02-federation/keys.json&names=data/02-federation/names.json)
