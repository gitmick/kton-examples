# 06 - export as RDF

The plankton lineage and the nekton claims export to RDF that **merges at the same `pk:<hash>`
IRIs**, so a reasoner sees a foton's provenance and the claims about it as one graph.

## What `run.sh` does

- **ANLEGEN (create):** a foton plus a claim about it.
- **VERWENDEN (use):** `plankton export --rdf` (lineage as Turtle / PROV) and `nekton export
  --nanopub` (claim as RDF/TriG), then show that both name the same node.

## Key idea

plankton renders each foton as a `prov:Activity` (inputs `prov:used`, outputs
`prov:wasGeneratedBy`); nekton renders each claim as a nanopublication. Both use the object namespace
`pk: <https://kton.dev/o/>` for a content hash, so a claim about a foton and that foton's provenance
resolve to **one node** when both files are loaded into a triplestore. plankton documents; it does
not reason - the RDF is a serialization you feed to a reasoner, not an inference step.

## Run

```
bash run.sh
```

## Expected output (abridged)

```
pk:fba2a8ae... a prov:Activity ;                 # plankton lineage (Turtle)
pk:fba2a8ae... <pav:reviewedBy> sub:o .          # nekton claim (TriG), SAME node
the JOIN: both name the same node pk:fba2a8ae...
    plankton: 1 activity
    nekton:   1 reference(s) to the same node
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/06-nanopub-rdf/union.json&keys=data/06-nanopub-rdf/keys.json&names=data/06-nanopub-rdf/names.json)
