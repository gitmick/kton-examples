# 05 - review scope

A single signed claim (example 04) says one thing. A **review** is usually a *sequence* of decisions
that must hang together, and be tamper-evident as a whole. A **scope** is that: a chain of claims
where each one covers the previous, so one **head** id seals the entire history. Edit any earlier
claim and the head no longer matches.

Assumes `nekton` is on your PATH. (Claims are introduced in [example 04](../04-claim/).)

## Walk through it, one command at a time

**1. An identity and a registry.**

```
nekton keygen chair
export NEKTON_DIR=./nekton-data
```

**2. Open a scope with a seed.** The seed's id *is* the scope id, remember it.

```
nekton seed drug-review --sign chair.key --by "CN=Chair" -o seed.dsse.json
nekton add seed.dsse.json
# scope id = sha256:1ff2bb7c...
```

**3. Chain the first claim under the scope.** Every claim in the scope names the scope, and a `prev`.
For the first claim, `prev` is the scope id itself:

```
cat > c1.spec.json <<'JSON'
{ "subject":[{"uri":"urn:doc:protocol"}], "predicate":"pav:reviewedBy",
  "object":{"value":"protocol approved"}, "by":"CN=Chair", "when":"2026-07-15T00:00:00Z",
  "scope":"sha256:1ff2bb7c...", "prev":"sha256:1ff2bb7c..." }
JSON
nekton claim c1.spec.json chair.key c1.dsse.json    # -> sha256:849fdfd4...
nekton add c1.dsse.json
```

**4. Chain the second claim onto the first.** Now `prev` is the *first claim's* id:

```
# ...same shape, subject urn:doc:results, prev = sha256:849fdfd4...
nekton claim c2.spec.json chair.key c2.dsse.json    # -> sha256:85e362c8...
nekton add c2.dsse.json
```

**5. Seal it: read the head.** The head is the tip of the chain, the id you publish (or `kton anchor`)
to make the whole review tamper-evident.

```
nekton head sha256:1ff2bb7c...
# head:  sha256:85e362c8...   (2 claim(s) chained)
```

**6. See the tamper-evidence.** A claim whose `prev` points nowhere is refused, a gap in the chain is
treated as tampering:

```
# a forged claim with prev = sha256:deadbeef...
nekton add bad.dsse.json
# error: prev sha256:deadbeef... does not resolve in scope ... (chain gap / tamper)
```

Each claim's id is computed over its contents *including* its `prev`, so the head transitively commits
to every earlier link. Change one, and its id changes, which breaks the next `prev`, which changes the
head. Anyone holding the published head can detect it.

## Or just run the whole thing

```
bash run.sh
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/05-review-scope/union.json&keys=data/05-review-scope/keys.json&names=data/05-review-scope/names.json)
