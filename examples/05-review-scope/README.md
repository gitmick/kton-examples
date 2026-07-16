# 05 - review scope

A single signed claim (example 04) says one thing. A **review** is usually a *sequence* of decisions
that must hang together and be tamper-evident as a whole. A **scope** is that: a chain of claims where
each one covers the previous, so one **head** id seals the entire history. Edit any earlier claim and
the head no longer matches.

Assumes `nekton` is on your PATH. (Claims are introduced in [example 04](../04-claim/).) This is the
fiddliest example, each claim points at the previous one by id. Every command below captures the id it
needs into a shell variable, so you can still paste them straight through.

## Walk through it, one command at a time

**1. An identity and a registry.**

```
nekton keygen chair
export NEKTON_DIR=./nekton-data
```

**2. Open a scope with a seed, and capture the scope id.** The seed's id *is* the scope id.

```
SCOPE=$(nekton seed drug-review --sign chair.key --by "CN=Chair" --add \
        | grep -oE 'sha256:[0-9a-f]+' | head -1)
echo "$SCOPE"                    # sha256:...
```

**3. Chain the first claim under the scope.** Every scoped claim names the scope and a `prev`; for the
first, `prev` is the scope id itself. We splice in `$SCOPE`, then capture the new claim's id as `$C1`.

```
cat > c1.spec.json <<JSON
{ "subject":[{"uri":"urn:doc:protocol"}], "predicate":"pav:reviewedBy",
  "object":{"value":"protocol approved"}, "by":"CN=Chair", "when":"2026-07-16T00:00:00Z",
  "scope":"$SCOPE", "prev":"$SCOPE" }
JSON
C1=$(nekton claim c1.spec.json chair.key --add | grep -oE 'sha256:[0-9a-f]+' | head -1)
echo "$C1"                       # sha256:...
```

**4. Chain the second claim onto the first.** Same shape, but now `prev` is `$C1`.

```
cat > c2.spec.json <<JSON
{ "subject":[{"uri":"urn:doc:results"}], "predicate":"pav:reviewedBy",
  "object":{"value":"results approved"}, "by":"CN=Chair", "when":"2026-07-16T00:01:00Z",
  "scope":"$SCOPE", "prev":"$C1" }
JSON
C2=$(nekton claim c2.spec.json chair.key --add | grep -oE 'sha256:[0-9a-f]+' | head -1)
```

**5. Seal it: read the head.**

```
nekton head "$SCOPE"
# head:  sha256:...   (2 claim(s) chained)
```

The **head** is the tip of the chain. Publish that one id (paste it in a report, an email, anywhere)
and the whole review is fixed: it transitively commits to every earlier link, because each claim's id
is computed over its contents *including* its `prev`. Optionally, `kton anchor` posts the head to a
public transparency log (Sigstore/Rekor) so that not even the chair can backdate it, `kton` is the
cockpit tool that adds network features on top of the two kernels; you do not need it here.

**Boundary - the head proves integrity, not currency.** A published head is tamper-evident, but by
itself it does not prove it is the *latest* head: an earlier, shorter chain (a **rewind**) verifies just
as cleanly. Knowing you hold the current head is a separate step - anchoring the head in a transparency
log (above) plus a consumer freshness check, laid out in the protocol's
[Trust chapter](https://github.com/gitmick/plankton/blob/main/docs/trust.md) (section 3, "freshness")
and made real in [example 08](../08-sigstore-github/).

**6. See the tamper-evidence.** A claim whose `prev` points nowhere is refused, a gap is treated as
tampering:

```
# a forged claim naming this scope but a prev that does not exist
printf '{"subject":[{"uri":"urn:doc:x"}],"predicate":"pav:reviewedBy","object":{"value":"forged"},"by":"CN=Chair","when":"2026-07-16T00:00:00Z","scope":"%s","prev":"sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' "$SCOPE" > bad.spec.json
nekton claim bad.spec.json chair.key --add
# error: prev sha256:deadbeef... does not resolve in scope ... (chain gap / tamper)
```

Change any earlier claim and its id changes, which breaks the next `prev`, which changes the head.
Anyone holding the published head can detect it.

**This fatality is a property of the *sealed scope*, a deliberately closed world.** It is NOT a general
rule: outside a sealed scope, on the open substrate, an unresolved reference is merely *incomplete*, not
invalid (a record referencing something you cannot yet see is still valid on its own hash and
signature). The scope buys a closed world on purpose - do not read "a dangling link is rejected" as
holding everywhere, or federation breaks.

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/05-review-scope/union.json&keys=data/05-review-scope/keys.json&names=data/05-review-scope/names.json)
