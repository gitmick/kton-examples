# 07 - identity

Every record so far was signed, and we kept saying "signed by a key" and "the keyid is what is real".
This example is about that: **a key is an identity**. It answers two different questions:

1. *Which model (or person) made this claim?* - trace it by keyid. Give a model its own key and every
   claim it makes is attributable to it.
2. *Who is that key, really?* - a separate, signed statement binds a key to a named principal. You
   believe it only if you trust whoever signed that binding.

Assumes `nekton` is on your PATH. (Claims are introduced in [example 04](../04-claim/).) **Parts 1 and
2 below run today.** Tier 3 (authority-backed identity) is described in the concept section and is now
real for a person in [example 08](../08-sigstore-github/) - signing with a GitHub identity via
Sigstore; SSH `allowed_signers` and a model-CA are still pending.

## Part 1 - a key is an identity (self-asserted)

**1. Give each model its own key, and capture its keyid.** The **keyid** is the fingerprint of the
public key: it *is* the cryptographic identity.

```
OPUS=$(nekton keygen opus     | grep -oE 'keyid=[0-9a-f]+' | cut -d= -f2)
SONNET=$(nekton keygen sonnet | grep -oE 'keyid=[0-9a-f]+' | cut -d= -f2)
echo "$OPUS $SONNET"          # e.g. <opus keyid> <sonnet keyid>
```

**2. Each model signs a claim with its key.** A claim spec is a small JSON file. (`nk:` is kton's
native namespace, `https://kton.dev/v/`; the kernel stores the predicate as an opaque term and never
interprets it.) `--add` files each claim as it signs it.

```
cat > opus.spec.json <<'JSON'
{ "subject":[{"uri":"urn:result:auc"}], "predicate":"nk:assessed",
  "object":{"value":"AUC is within the expected range"},
  "by":"claude-opus-4-8", "when":"2026-07-16T00:00:00Z" }
JSON
cat > sonnet.spec.json <<'JSON'
{ "subject":[{"uri":"urn:result:auc"}], "predicate":"nk:assessed",
  "object":{"value":"AUC looks plausible"},
  "by":"claude-sonnet-5", "when":"2026-07-16T00:00:00Z" }
JSON
nekton claim opus.spec.json   opus.key   --add
nekton claim sonnet.spec.json sonnet.key --add
```

**3. Trace which claims came from which model, by keyid.**

```
nekton by signer "$OPUS"
# sha256:...  predicate=nk:assessed  by=claude-opus-4-8  keyid=<opus keyid>
nekton by signer "$SONNET"
# sha256:...  predicate=nk:assessed  by=claude-sonnet-5  keyid=<sonnet keyid>
```

That is the whole mechanism: **give a model a key, and every claim it makes is attributable to that
key.** `by=claude-opus-4-8` is a self-asserted *label*, anyone could type it; the keyid is the
cryptographic fact.

## Part 2 - binding a key to a named model (attested)

Part 1 shows *that* a key made a claim, not *who* the key is. Who says keyid `$OPUS` really belongs to
`claude-opus-4-8`? An **authority** signs an identity claim ABOUT the key. That claim is a lightweight
**Verifiable Credential**: *this key `sec:controller` this principal*. Two decisions make it merge with
the rest of the graph:

- the **key** is named by its content-addressed IRI `https://kton.dev/o/<full key hash>` (the same
  `pk:` namespace file/foton hashes use), typed `sec:Multikey`. The `keyid` is just that hash's first
  16 hex - a display fingerprint, not a separate identifier.
- the **predicate** is `sec:controller` from the **W3C Security Vocabulary** (the same vocabulary DIDs
  and Verifiable Credentials use), and the **principal** is a real IRI (`model:...`, or `did:web:...`
  for a person), not a bare string - so it joins the RDF export in [example 06](../06-nanopub-rdf/).

```
nekton keygen deployer
# the key's IRI is its full content hash; keyid = its first 16 hex
KEYIRI="https://kton.dev/o/$(python3 -c "import hashlib;print(hashlib.sha256(bytes.fromhex(open('opus.pub').read().strip())).hexdigest())")"
printf '{"subject":[{"uri":"%s"}],"predicate":"https://w3id.org/security#controller","object":{"id":"model:anthropic/claude-opus-4-8"},"by":"CN=Deployment","when":"2026-07-16T00:00:00Z"}' \
  "$KEYIRI" > identity.spec.json
nekton claim identity.spec.json deployer.key --add
nekton about "$KEYIRI"
# sha256:...  predicate=https://w3id.org/security#controller  by=CN=Deployment  keyid=<deployer keyid>
```

The predicate is written as a full IRI because the bare `nekton claim` path stores it verbatim; the
`sec:controller` / `actsAs` aliases in `aliases.json` resolve to exactly this IRI when you author via
`nekton annotate` instead. A consumer resolves key -> principal via the claim, and **believes it only
if they trust the deployer's key**. It is still one claim, one signer; no new machinery.

## How identity works in kton

- **The kernel binds a record to a key, nothing more.** It knows keyids, never who a key belongs to.
  A pubkey is itself content-addressed (`keyid = fingerprint`), so it can be a subject of claims,
  pinned, and federated like anything else.
- **Identity is a separate, single-signed claim:** *key K acts as principal P, vouched by authority
  A.* One claim, one signer. Two parties vouching for the same key is just two matching claims, not a
  multi-signature, so nothing about the kernel changes.
- **Three assurance tiers**, weakest to strongest:
  - **self-asserted** - the `by` label (Part 1). Zero proof.
  - **attested** - a signed `sec:controller` claim (a Verifiable Credential) by someone you trust (Part 2).
  - **authority-backed** *(partially shipped)* - a certificate or an allow-list from a trusted issuer.
    For a **person** this is now real in [example 08](../08-sigstore-github/): **Sigstore** keyless (an
    OIDC/GitHub identity bound by a Fulcio certificate + the Rekor transparency log). Still pending:
    **SSH signatures** (a GitHub / `allowed_signers` principal) and a **model-CA** for a model. These
    schemes need network and OS tooling, so they live in the cockpit (`kton`), not the kernels.
- **Trust policy** - which authorities and identities you accept - is a consumer decision, never the
  kernel's.

> **Vocabulary (settled).** A key is named by its content-addressed IRI (`pk:<full hash>`, type
> `sec:Multikey`); the binding predicate is `sec:controller` from the W3C Security Vocabulary, with
> `actsAs` kept only as an alias for it; the principal is an IRI. This is deliberately the DID /
> Verifiable-Credential vocabulary, so the authority-backed tier (a Fulcio certificate in
> [example 08](../08-sigstore-github/) is exactly a `sec:controller` statement) needs no re-do.

## Run

```
bash run.sh
```

## See it

The viewer colours records by their signer. Crucially, a signer's **label is the principal from its
signed `sec:controller` claim where one exists** - so the opus key shows as `claude-opus-4-8` (what the
deployer *signed*), not a site-operator keyfile name. A key with no such binding falls back to its
keyfile label, which is a site label, not attested - the difference the whole example is about.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/07-identity/union.json&keys=data/07-identity/keys.json&names=data/07-identity/names.json)
