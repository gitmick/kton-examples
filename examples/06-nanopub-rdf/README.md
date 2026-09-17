# 06 - export as RDF

Examples 01-05 kept everything inside kton. But the point of content-addressed records is that other
tools can consume them. Both layers **export to RDF**: plankton lineage as PROV, nekton claims as
nanopublications. They use the **same hash-based IRIs**, so when you load both into a triplestore, a
foton's provenance and the claims about it land on **one node**, ready for a reasoner. plankton
documents; it does not reason, the RDF is just a serialization you hand to something that does.

This is the advanced finale and it leans on semantic-web vocabulary. None of it is kton's invention,
and one line each is enough to follow along:

- **RDF** — the W3C model for data as *subject–predicate–object* triples, which is the shape a nekton
  claim already has: [RDF primer](https://www.w3.org/TR/rdf11-primer/).
- **IRI** — Internationalized Resource Identifier, the Unicode-friendly generalization of a URL and
  the standard way to name a thing in RDF: [RFC 3987](https://www.rfc-editor.org/rfc/rfc3987). kton's
  are hash-based (`pk:<sha256>`), which is why two exports meet on the same node.
- **PROV** (PROV-O) — the W3C ontology for saying how something was produced: who did it, from what,
  with which activity. A foton maps onto it almost directly:
  [PROV-O](https://www.w3.org/TR/prov-o/).
- **Turtle** and **TriG** — two text syntaxes for writing RDF down. TriG is Turtle plus *named
  graphs*, which is what lets each nanopublication keep its own graph:
  [Turtle](https://www.w3.org/TR/turtle/), [TriG](https://www.w3.org/TR/trig/).
- **nanopublication** — a small, self-contained publication: an assertion, its provenance, and its
  own publication info, each in its own named graph: [nanopub.net](https://nanopub.net/).
- **triplestore** — a database for triples, which you query with SPARQL (examples 11 and 12 do).

Assumes `plankton` and `nekton` are on your PATH; you have seen fotons ([01](../01-hello-foton/))
and claims ([04](../04-claim/)).

## Walk through it, one command at a time

**1. Make a foton and a claim about it** (this is example 04, condensed but fully runnable):

```
plankton keygen analyst ; nekton keygen reviewer
export PLANKTON_DIR=./plankton-data NEKTON_DIR=./nekton-data
echo raw > data.csv ; echo model > model.txt
FOTON=$(plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key --add --print-id)

cat > review.spec.json <<JSON
{ "subject":[{"hash":"$FOTON"}], "predicate":"https://kton.dev/v/reviewed",
  "object":{"value":"approved"}, "by":"CN=Reviewer", "when":"2026-07-16T00:00:00Z" }
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
grep nk:reviewed claim.trig
# pk:... nk:reviewed ...      (nk: = https://kton.dev/v/)
```

**4. See the join.** Both files name the **same** node, `pk:...` (the namespace `pk:` is
`https://kton.dev/o/`, a content hash). Load both into any RDF store and they merge there. This step
is the only one on the page that needs anything beyond the two binaries — `pip install rdflib`:

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

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
