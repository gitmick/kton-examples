# 02 - environments + federation

Two independent registries (**environments**) that never share a folder. They exchange records by
content hash, then read as one lineage. This is the example for the two things people found unclear:
how environments are used, and how the files are named across them.

## What `run.sh` does

- **Create:** alice records a foton in **environment A** (`PLANKTON_DIR=.work/env-a`); bob
  records a foton in **environment B** (`.work/env-b`) that consumes alice's output.
- **FEDERATION:** environment B runs `plankton mirror <env-a-dir>` - it copies A's records in by
  hash. No server, no shared folder.
- **Use:** from B, `plankton uses` and `plankton lineage` now span both environments as
  one graph.

## Key idea

An **environment is just a directory**. You point plankton at it with `PLANKTON_DIR=<dir>`; a
different directory is a different, independent registry. `mirror` is how work moves between them -
it transfers content-addressed records, so two environments converge without ever sharing a
filesystem or a server.

**Naming convention shown here:** `env-a/`, `env-b/` (the registries), `<who>.key`/`.pub` (identities),
`<who>-<step>.foton.json` (the signed envelope, named by who made it and what it is).

## Run

```
bash run.sh
```

## Expected output (abridged)

```
mirrored .../env-a: 1 new; registry holds 2 fotons
-- who USED alice's cleaned.csv as input? --
sha256:e62bec06...  kind=script  in=1 out=1        # bob's fit, now visible in B
-- full backward lineage of bob's model.txt --
sha256:e62bec06...  kind=script                     # bob's fit
sha256:29f651ca...  kind=script                     # alice's clean (imported from A)
```

## See it

The viewer colours the two participants differently, so you see one federated graph built from two
environments.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/02-environments-federation/union.json&keys=data/02-environments-federation/keys.json&names=data/02-environments-federation/names.json)
