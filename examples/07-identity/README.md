# 07 - identity

Every record so far was signed, and we kept saying "signed by a key" and "the keyid is what is real".
This example is about that: **a key is an identity**. It answers two different questions:

1. *Which model (or person) made this claim?* - trace it by keyid. Give a model its own key and every
   claim it makes is attributable to it.
2. *Who is that key, really?* - a separate, signed statement binds a key to a named principal. You
   believe it only if you trust whoever signed that binding.

Assumes `nekton` is on your PATH. (Claims are introduced in [example 04](../04-claim/).) **Parts 1 and
2 below run today**; tier 3 (Sigstore, GitHub SSH) in the concept section is described but **not yet
shipped**.

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
  "by":"claude-opus-4-8", "when":"2026-07-15T00:00:00Z" }
JSON
cat > sonnet.spec.json <<'JSON'
{ "subject":[{"uri":"urn:result:auc"}], "predicate":"nk:assessed",
  "object":{"value":"AUC looks plausible"},
  "by":"claude-sonnet-5", "when":"2026-07-15T00:00:00Z" }
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
`claude-opus-4-8`? An **authority** signs an identity claim ABOUT the key (we splice `$OPUS` into the
subject):

```
nekton keygen deployer
cat > identity.spec.json <<JSON
{ "subject":[{"uri":"urn:kton:key:$OPUS"}], "predicate":"nk:actsAs",
  "object":{"value":"model:anthropic/claude-opus-4-8"},
  "by":"CN=Deployment", "when":"2026-07-15T00:00:00Z" }
JSON
nekton claim identity.spec.json deployer.key --add
nekton about "urn:kton:key:$OPUS"
# sha256:...  predicate=nk:actsAs  by=CN=Deployment  keyid=<deployer keyid>
```

A consumer now resolves keyid -> model name via that claim - **and believes it only if they trust the
deployer's key**. It is just another single-signed claim; no new machinery.

## How identity works in kton

- **The kernel binds a record to a key, nothing more.** It knows keyids, never who a key belongs to.
  A pubkey is itself content-addressed (`keyid = fingerprint`), so it can be a subject of claims,
  pinned, and federated like anything else.
- **Identity is a separate, single-signed claim:** *key K acts as principal P, vouched by authority
  A.* One claim, one signer. Two parties vouching for the same key is just two matching claims, not a
  multi-signature, so nothing about the kernel changes.
- **Three assurance tiers**, weakest to strongest:
  - **self-asserted** - the `by` label (Part 1). Zero proof.
  - **attested** - a signed claim by someone you trust (Part 2).
  - **authority-backed** *(not yet shipped)* - a certificate or an allow-list from a trusted issuer:
    **Sigstore** (keyless: an OIDC identity via Fulcio + the Rekor transparency log) and **SSH
    signatures** (a GitHub / `allowed_signers` principal) for a person, a model-CA for a model. Those
    schemes need network and OS tooling, so they live in the cockpit (`kton`), not the kernels. Only
    `kton anchor` (anchor a record in Rekor) exists so far.
- **Trust policy** - which authorities and identities you accept - is a consumer decision, never the
  kernel's.

> The `urn:kton:key:` form used above is illustrative; the exact identity vocabulary (how a key is
> named as a claim subject, which ontology the binding predicate comes from) is still being settled.

## Run

```
bash run.sh
```

## See it

The viewer colours records by their signer, so each model's claims appear in its own colour, and the
deployer's identity claim is a distinct node.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/07-identity/union.json&keys=data/07-identity/keys.json&names=data/07-identity/names.json)
