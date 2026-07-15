# 06 - export as RDF

Examples 01-05 kept everything inside kton. But the point of content-addressed records is that other
tools can consume them. Both layers **export to RDF**: plankton lineage as PROV, nekton claims as
nanopublications. They use the **same hash-based IRIs**, so when you load both into a triplestore, a
foton's provenance and the claims about it land on **one node**, ready for a reasoner. plankton
documents; it does not reason, the RDF is just a serialization you hand to something that does.

This is the advanced finale and it leans on semantic-web vocabulary (RDF, PROV, Turtle, TriG,
triplestore). Assumes `plankton` and `nekton` are on your PATH; you have seen fotons ([01](../01-hello-foton/))
and claims ([04](../04-claim/)).

## Walk through it, one command at a time

**1. Make a foton and a claim about it** (this is example 04, condensed but fully runnable):

```
plankton keygen analyst ; nekton keygen reviewer
export PLANKTON_DIR=./plankton-data NEKTON_DIR=./nekton-data
echo raw > data.csv ; echo model > model.txt
FOTON=$(plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key --add | awk '/indexed foton/{print $3}')

cat > review.spec.json <<JSON
{ "subject":[{"hash":"$FOTON"}], "predicate":"pav:reviewedBy",
  "object":{"value":"approved"}, "by":"CN=Reviewer", "when":"2026-07-15T00:00:00Z" }
JSON
nekton claim review.spec.json reviewer.key review.dsse.json --add   # file it + keep it for the export
```

**2. Export the plankton lineage as RDF (Turtle / PROV).** Each foton becomes a `prov:Activity`,
inputs `prov:used`, outputs `prov:wasGeneratedBy`:

```
plankton export --rdf -o lineage.ttl
grep prov:Activity lineage.ttl
# pk:... a prov:Activity ;
```

**3. Export the nekton claim as a nanopublication (Turtle / TriG):**

```
nekton export --nanopub review.dsse.json -o claim.trig
grep pav:reviewedBy claim.trig
# pk:... <pav:reviewedBy> ...
```

**4. See the join.** Both files name the **same** node, `pk:...` (the namespace `pk:` is
`https://kton.dev/o/`, a content hash). Load both into any RDF store and they merge there:

```
python3 - <<'PY'
import rdflib
g = rdflib.Dataset()
g.parse("lineage.ttl", format="turtle")
g.parse("claim.trig",  format="trig")
print(len(g), "triples, one graph")   # the model's provenance AND the review on it
PY
```

The verifiable lineage (plankton) and the signed attestation (nekton) become one graph, joined at the
hash, without either layer knowing about RDF beyond emitting it. A reasoner can now answer questions
like "is there a review on the thing this model was derived from?".

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/06-nanopub-rdf/union.json&keys=data/06-nanopub-rdf/keys.json&names=data/06-nanopub-rdf/names.json)
