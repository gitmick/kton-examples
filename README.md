# kton examples

Small, self-contained examples for the **kton** substrate (plankton + nekton). Each one both
**creates** records and **uses** them, and renders the resulting graph in a viewer so you see exactly
what came out. This repo also holds a curated set of example nekton **templates** (see the end).

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

The examples assume `plankton` and `nekton` are installed and on your PATH. Then just:

```
bash examples/01-hello-foton/run.sh
```

Each run writes its graph data under `docs/data/<name>/` and prints a `SEE IT:` line. To view
locally, serve `docs/` (`python3 -m http.server -d docs`) and open the printed URL; on GitHub Pages
the graphs are already live.

<details><summary>Not installed yet? Build once from source (contributors)</summary>

The binaries are Go, no dependencies. Build them from the
[plankton repo](https://github.com/gitmick/plankton) onto your PATH (or into this repo's `bin/`,
which the run scripts also add to PATH):

```
( cd reference        && go build -o ~/.local/bin/plankton ./cmd/plankton )
( cd nekton/reference && go build -o ~/.local/bin/nekton   ./cmd/nekton )
( cd kton/reference   && go build -o ~/.local/bin/kton     ./cmd/kton )
```
</details>

## What is NOT here

Private keys (`*.key`), the kton binaries, and the throwaway per-example working state (`.work/`) are
git-ignored, this is a public repo. Only the run scripts, the viewer, and the (public) graph
snapshots are published.

## Curated nekton templates

`templates/` + `aliases.json` are **application/example content, not the protocol.** The kton kernel
is ontology-free: it stores signed subject-predicate-object claims and treats every predicate as an
opaque IRI it never interprets (spec Clause 7). Which predicates exist, and any templates for
authoring them, are *federated data*, deliberately kept out of the protocol repo.

- **`aliases.json`** - CURIE/term sugar that resolves to canonical IRIs *before* a claim is built, so
  the signed wire form always carries the full IRI. Vocabulary policy: reuse a published ontology
  wherever one fits - **PROV** (lineage), **PAV** (`pav:reviewedBy` for general review), **DCAT**
  (`dcat:downloadURL` for location), **OWL/SKOS** (equivalence/hierarchy). The regulated **`gxp:*`**
  terms are reserved for actual GxP-validated processes; ordinary review uses `pav:reviewedBy`.
- **`templates/`** - example authoring templates (`kton.dev/template/v0`) consumed by `nekton
  annotate`: `prov-derived-from.json` (a plain PROV lineage claim, the minimal mechanism demo);
  `gxp-review.json`, `gxp-tool-validation.json`, `risk-accept.json` (regulated GxP examples);
  `election-vote-initialised.json`, `election-count-finished.json` (a liquid-democracy governance
  example); `pmx-model-role.json` (a pharmacometrics domain example).

```sh
NEKTON_TEMPLATES=./templates NEKTON_ALIASES=./aliases.json \
  nekton annotate <subject> --template prov/derived-from --set ... --sign key.key
```

These illustrate the template/alias *mechanism*. Curate additions deliberately: an example here is a
suggestion, not a standard, the normative vocabulary policy lives in the protocol's
`spec/vocabulary.md`.
