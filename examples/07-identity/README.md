# 07 - identity

Every record so far was signed, and we kept saying "signed by a key" and "the keyid is what is real".
This example is about that: **a key is an identity**. It answers two different questions:

1. *Which model (or person) made this claim?* - trace it by keyid. Give a model its own key and every
   claim it makes is attributable to it.
2. *Who is that key, really?* - a separate, signed statement binds a key to a named principal. You
   believe it only if you trust whoever signed that binding.

Assumes `nekton` is on your PATH. (Claims are introduced in [example 04](../04-claim/).)

## Part 1 - a key is an identity (self-asserted)

Give two models their own signing keys. The **keyid** is the fingerprint of the public key: it *is*
the cryptographic identity. (The human `by` label is just text, anyone can type any name there.)

```
nekton keygen opus       # keypair opus    keyid=e9708de7...
nekton keygen sonnet     # keypair sonnet  keyid=25ed220f...
```

Hand each key to the corresponding model; each model signs the claims it makes:

```
# opus signs (subject urn:result:auc, by-label "claude-opus-4-8"):
nekton claim opus.spec.json   opus.key   --add
nekton claim sonnet.spec.json sonnet.key --add
```

Now trace which claims came from which model, by keyid:

```
nekton by signer <opus-keyid>
# sha256:...  predicate=nk:assessed  by=claude-opus-4-8  keyid=e9708de7...
nekton by signer <sonnet-keyid>
# sha256:...  predicate=nk:assessed  by=claude-sonnet-5  keyid=25ed220f...
```

That is the whole mechanism: **give a model a key, and every claim it makes is attributable to that
key.** `by=claude-opus-4-8` is a self-asserted *label*; the keyid is the cryptographic fact.

## Part 2 - binding a key to a named model (attested)

Part 1 shows *that* a key made a claim, not *who* the key is. Who says keyid `e9708de7...` really
belongs to `claude-opus-4-8`? An **authority** signs an identity claim ABOUT the key:

```
nekton keygen deployer
# subject urn:kton:key:<opus-keyid>, predicate nk:actsAs, object "model:anthropic/claude-opus-4-8"
nekton claim identity.spec.json deployer.key --add
nekton about "urn:kton:key:<opus-keyid>"
# sha256:...  predicate=nk:actsAs  by=CN=Deployment  keyid=ad9f01ed...
```

A consumer now resolves keyid -> model name via that claim - **and believes it only if they trust the
deployer's key**. This binding is just another single-signed claim; no new machinery.

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
  - **authority-backed** - a certificate or an allow-list from a trusted issuer. This is where
    **Sigstore** (keyless: an OIDC identity via Fulcio + Rekor transparency log) and **SSH signatures**
    (a GitHub/`allowed_signers` principal) come in, for a person, and a model-CA for a model. Those
    schemes need network and OS tooling, so they live in the cockpit (`kton`), not the kernels;
    they are in development. `kton anchor` (Rekor) is the first piece already present.
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
