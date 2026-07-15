# 02 - federation

Two independent **registries** that never share a folder. They exchange records by content hash, then
read as one lineage. This is the example for the two things people found unclear: how a registry is
pointed at, and how the files are named across two of them.

> A **registry** is a *store*: the directory where plankton files its records, set by `PLANKTON_DIR`.
> It is **not** an execution environment (the container, OS, or tool that runs your code). Those are a
> separate concept plankton can record on its own; this example is only about two stores.

## What `run.sh` does

- **Create:** alice records a foton in **registry A** (`PLANKTON_DIR=.work/reg-a`); bob records a
  foton in **registry B** (`.work/reg-b`) that consumes alice's output.
- **Federation:** registry B runs `plankton mirror <reg-a-dir>` - it copies A's records in by hash.
  No server, no shared folder.
- **Use:** from B, `plankton uses` and `plankton lineage` now span both registries as one graph.

## Key idea

A registry is just a directory. You point plankton at it with `PLANKTON_DIR=<dir>`; a different
directory is a different, independent registry. `mirror` is how records move between them - it
transfers content-addressed records, so two registries converge without ever sharing a filesystem or
a server.

**Naming convention shown here:** `reg-a/`, `reg-b/` (the two registries), `<who>.key`/`.pub`
(identities), `<who>-<step>.foton.json` (the signed envelope, named by who made it and what it is).

## Run

```
bash run.sh
```

## Expected output (abridged)

```
mirrored .../reg-a: 1 new; registry holds 2 fotons
-- who USED alice's cleaned.csv as input? --
sha256:e62bec06...  kind=script  in=1 out=1        # bob's fit, now visible in B
-- full backward lineage of bob's model.txt --
sha256:e62bec06...  kind=script                     # bob's fit
sha256:29f651ca...  kind=script                     # alice's clean (imported from A)
```

## See it

The viewer colours the two participants differently, so you see one federated graph built from two
registries.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/02-federation/union.json&keys=data/02-federation/keys.json&names=data/02-federation/names.json)
