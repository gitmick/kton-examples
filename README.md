# kton examples

Small, self-contained examples for the **kton** substrate (plankton + nekton). Each one both
**creates** records and **uses** them, and renders the resulting graph in a viewer so you see exactly
what came out.

Live viewer: **https://gitmick.github.io/kton-examples/**

## The one thing to understand first: environments

A plankton **environment is just a directory** that holds a registry. You point plankton at it with
`PLANKTON_DIR=<dir>` (and nekton with `NEKTON_DIR=<dir>`). A different directory is a different,
independent registry. Records move between environments by content hash with `plankton mirror` -
no server, no shared folder. Every example makes this explicit in its `run.sh`.

## Naming conventions used across the examples

- **Files** are ordinary files; plankton stores none of their bytes, only their `sha256:` content
  hash. `plankton hash <file>` prints that hash in the exact `sha256:<hex>` form the queries expect.
- **`<name>.foton.json`** - a signed foton envelope (a recorded computation).
- **`<who>.key` / `<who>.pub`** - one identity's private / public Ed25519 key.
- **Query by what you have:** `plankton producer <outputHash>` (who made it), `plankton uses
  <inputHash>` (who consumed it), `plankton lineage <hash>` (the whole ancestry).

## The examples

| # | example | teaches |
|---|---|---|
| 01 | `hello-foton` | the smallest create + use: record a foton, then show / verify / query it |
| 02 | `environments-federation` | two environments exchanging records by hash (mirror), read as one lineage |

## Run them yourself

The kton binaries are **not published in this repo**. Build them from the
[plankton repo](https://github.com/gitmick/plankton) and drop them in `bin/`:

```
# in a plankton checkout:
( cd reference       && go build -o /path/to/kton-examples/bin/plankton ./cmd/plankton )
( cd nekton/reference && go build -o /path/to/kton-examples/bin/nekton  ./cmd/nekton )
( cd kton/reference   && go build -o /path/to/kton-examples/bin/kton    ./cmd/kton )
```

Then:

```
bash examples/01-hello-foton/run.sh
```

Each run writes its graph data under `docs/data/<name>/` and prints a `SEE IT:` line. To view
locally, serve `docs/` (`python3 -m http.server -d docs`) and open the printed URL; on GitHub Pages
the graphs are already live.

## What is NOT here

Private keys (`*.key`), the kton binaries, and the throwaway per-example working state (`.work/`) are
git-ignored, this is a public repo. Only the run scripts, the viewer, and the (public) graph
snapshots are published.
