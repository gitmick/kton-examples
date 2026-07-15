# 06 - export as RDF

Examples 01-05 kept everything inside kton. But the point of content-addressed records is that other
tools can consume them. Both layers **export to RDF**: plankton lineage as PROV, nekton claims as
nanopublications. They use the **same hash-based IRIs**, so when you load both into a triplestore, a
foton's provenance and the claims about it land on **one node**, ready for a reasoner. plankton
documents; it does not reason, the RDF is just a serialization you hand to something that does.

Assumes `plankton` and `nekton` are on your PATH. (See [04](../04-claim/) for what a claim is.)

## Walk through it, one command at a time

**1. Make a foton and a claim about it** (exactly as in example 04):

```
plankton keygen analyst ; nekton keygen reviewer
export PLANKTON_DIR=./plankton-data NEKTON_DIR=./nekton-data
echo raw > data.csv ; echo model > model.txt
plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key -o model.foton.json
plankton add model.foton.json           # foton id e.g. sha256:fba2a8ae...
# ... nekton claim pav:reviewedBy about that foton id, then nekton add (see example 04)
```

**2. Export the plankton lineage as RDF (Turtle / PROV).** Each foton becomes a `prov:Activity`,
inputs `prov:used`, outputs `prov:wasGeneratedBy`:

```
plankton export --rdf -o lineage.ttl
# pk:fba2a8ae... a prov:Activity ; ...
```

**3. Export the nekton claim as a nanopublication (Turtle / TriG):**

```
nekton export --nanopub review.dsse.json -o claim.trig
# pk:fba2a8ae... <pav:reviewedBy> ...
```

**4. See the join.** Look at the two files: the foton and the claim name the **same** node,
`pk:fba2a8ae...` (the object namespace `pk:` is `https://kton.dev/o/`, a content hash). Load both into
any RDF store and they merge there:

```
# with python + rdflib, for instance:
#   g = rdflib.Dataset(); g.parse("lineage.ttl"); g.parse("claim.trig")
# now one query can walk the model's provenance AND find the review on it.
```

The verifiable lineage (plankton) and the signed attestation (nekton) become one graph, joined at the
hash, without either layer knowing about RDF beyond emitting it.

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/06-nanopub-rdf/union.json&keys=data/06-nanopub-rdf/keys.json&names=data/06-nanopub-rdf/names.json)
