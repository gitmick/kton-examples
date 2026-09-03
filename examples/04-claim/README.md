# 04 - claim (nekton)

So far everything has been a **foton**: a machine-checkable record of a computation. But some things
cannot be re-run and verified, only *vouched for*: "I reviewed this", "this is approved". That is what
**nekton** adds. Its record is a **claim**: a signed statement *about* something. A machine can check
*who signed it*, never whether it is true, that is the whole difference between the two layers.

Assumes `plankton` and `nekton` are on your PATH. Do [01](../01-hello-foton/) first if `foton` is new.
Every command below is runnable in order (ids are captured into shell variables, nothing to retype).

## Walk through it, one command at a time

**1. Two identities and two registries.** plankton keeps its fotons; nekton keeps its claims.

```
plankton keygen analyst          # the analyst's keypair (they will author the foton)
nekton   keygen reviewer         # the reviewer's keypair (they will sign the claim)
export PLANKTON_DIR=./plankton-data NEKTON_DIR=./nekton-data
```

**2. The analyst records a foton, and we capture its id.**

```
echo raw > data.csv ; echo fit > model.txt
# --add authors + files the foton in one step; the id it prints is what we capture:
FOTON=$(plankton author --cmd "fit data.csv model.txt" --in data.csv --out model.txt \
    --sign analyst.key --add | awk '/indexed foton/{print $3}')
echo "$FOTON"                    # sha256:...
```

**3. The reviewer makes a claim about that foton.** A claim spec is a small JSON file; its **subject
is the foton's id**, so we splice in `$FOTON` (nothing to copy by hand). The subject is a *list*
because a claim can be about several things at once, here just one.

```
cat > review.spec.json <<JSON
{ "subject":  [{"hash": "$FOTON"}],
  "predicate": "https://kton.dev/v/reviewed",
  "object":    {"value": "looks correct"},
  "by": "CN=Reviewer", "when": "2026-07-16T00:00:00Z" }
JSON
nekton claim review.spec.json reviewer.key review.dsse.json --add
```

Three positional arguments, in that order: the **spec to sign**, the **key to sign it with**, and the
**file to write**. So `review.dsse.json` is the *signed claim* — a DSSE-wrapped JSON envelope, the
same shape example 01 called a foton's envelope, produced by signing `review.spec.json` with
`reviewer.key`. `--add` files it into the registry as it signs (the same `--add` / `--registry` flags
exist on `nekton claim`, `annotate` and `seed`); we keep the file too, so we can `show`/`verify` it
next. Leave the third argument off and `--add` still works — you just get no file to hand anyone.

The triple reads **subject** (the foton) — **reviewed** → **object** (the verdict, `"looks correct"`);
`by` is who is *making* that statement, and the signature is what establishes them.

`https://kton.dev/v/reviewed` is just a **label**. Specifically an *IRI* — an Internationalized
Resource Identifier ([RFC 3987](https://www.rfc-editor.org/rfc/rfc3987)), the Unicode-friendly
generalization of a URL and the standard way to name a thing in linked data. **Opaque** here means
the *kernel* — the part of kton that stores, indexes and verifies records, as opposed to any tool
built on top — keeps this string exactly as given and never tries to interpret or validate what it
means. That cuts both ways, and it is why the choice of predicate is yours to get right. The natural
first pick here is `pav:reviewedBy` — but that one is *passive*: "X was reviewed **by** Y", so its
object slot belongs to the reviewer's identity. Put the verdict there and the triple says the foton
was reviewed by "looks correct", while the reviewer appears nowhere in what is being asserted. Nothing
in the kernel will ever tell you: it stores predicates as opaque IRIs and does not interpret them. An
active, unary `reviewed` takes the verdict as its object and leaves the identity to the signature.

**4. Use it: ask what has been said about the foton.**

```
nekton about "$FOTON"
# sha256:...  predicate=https://kton.dev/v/reviewed  by=CN=Reviewer  declared-keyid=... (unverified)
nekton show   review.dsse.json      # the full claim
nekton verify review.dsse.json reviewer.pub
# signature: VALID - verified as keyid ... (the authoritative signer)
```

Because the claim's subject is the foton's hash, plankton (what was computed) and nekton (what people
say about it) **join at the same node**. The foton is machine-verifiable; the review is only as good
as the key that signed it.

> Note the `by: "CN=Reviewer"` is a **self-asserted label**, anyone can type any name there. What is
> cryptographically real is the **keyid** that `verify` reports; mapping that key to a
> real-world identity is a trust decision you make, not something the record proves.

The claim was already signed the moment step 3 wrote it — so what does step 4's `verify` add? Not the
signature: that was there. It adds *your* check of it. Until you run it you are reading the record's
own account of who signed it (`declared-keyid`, marked `unverified` in the `about` output above);
after it, you have re-computed the signature against a key **you** chose and hold. The point is not
that the record becomes trustworthy — it is that **anyone** can do this, independently, without
asking us or the reviewer. Same declared-vs-verified split as example 01's footnote, one layer up.

## Or just run the whole thing

```
bash run.sh
```

## See it

The viewer shows the foton and the claim as one graph, the claim attached to the foton it is about.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/04-claim/union.json&keys=data/04-claim/keys.json&names=data/04-claim/names.json)

*(a pre-generated snapshot of the canonical `run.sh`, checked into the repo — not your own local registry)*
