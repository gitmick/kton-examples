# kton-examples

Curated **example** nekton templates and alias vocabulary for the [kton](https://github.com/gitmick/plankton)
protocol. This is **application/example content — not the protocol.** The kton kernel is ontology-free:
it stores signed subject–predicate–object claims and treats every predicate as an opaque IRI it never
interprets (see the spec, Clause 7). Which predicates exist, and any templates for authoring them, are
*federated data*, deliberately kept out of the protocol repo.

## Contents

- **`aliases.json`** — CURIE/term sugar that resolves to canonical IRIs *before* a claim is built, so
  the signed wire form always carries the full IRI. Vocabulary policy (protocol DECISIONS §20): reuse a
  published ontology wherever one fits — **PROV** (lineage), **PAV** (`pav:reviewedBy` for general
  review), **DCAT** (`dcat:downloadURL` for location), **OWL/SKOS** (equivalence/hierarchy). The
  regulated **`gxp:*`** terms are **reserved for actual GxP-validated processes** — ordinary review uses
  `pav:reviewedBy`, never `gxp:`.
- **`templates/`** — example authoring templates (`kton.dev/template/v0`) consumed by `nekton annotate`:
  - `prov-derived-from.json` — a plain PROV lineage claim (the minimal mechanism demo).
  - `gxp-review.json`, `gxp-tool-validation.json`, `risk-accept.json` — regulated (GxP) examples; they
    carry the reserved `gxp:*` terms because they *are* GxP claims.
  - `election-vote-initialised.json`, `election-count-finished.json` — liquid-democracy governance example.
  - `pmx-model-role.json` — a pharmacometrics domain example.

## Use

```sh
NEKTON_TEMPLATES=./templates NEKTON_ALIASES=./aliases.json \
  nekton annotate <subject> --template prov/derived-from --set ... --sign key.key
```

These are illustrations of the template/alias *mechanism*. Curate additions deliberately: an example
here is a suggestion, not a standard — the normative vocabulary policy lives in the protocol's
`spec/vocabulary.md`.
