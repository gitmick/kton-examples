# 08 - sign with your GitHub identity (Sigstore keyless)

Example 07 ended at a wall: tier 3, *authority-backed* identity, "not yet shipped". This example
crosses it for a **person**: sign a kton record with your **GitHub identity** via **Sigstore keyless**,
so anyone can verify *who* signed it, through a certificate authority and a public transparency log,
**with no long-lived key and no trust in you**.

Unlike examples 01-07, this one is **not headless**: keyless signing needs an interactive OIDC login,
so exactly one step is run by you. It needs [`cosign`](https://github.com/sigstore/cosign) **v2.x** on
your PATH (the `--new-bundle-format` and `--certificate-identity-regexp` flags below are 2.x), and it
has **no live graph snapshot** (the identity is yours and personal; run it yourself).

## Walk through it

**1. (automatic) Make a kton record to sign.** Any signed foton or claim envelope works:

```
plankton author --cmd "assess result.csv" --in result.csv --out assessment.txt \
    --sign author.key --add -o foton.dsse.json
```

That record is already signed once, on the **inside**, by the foton's own author (`author.key`). The
GitHub signature you add next is a second, **outer** attestation over the whole record's hash: a
different party vouching for the record, independent of whoever authored it. Inner signature = who made
the record; outer signature = who is willing to stand behind it under their real-world identity.

**2. (you run this) Sign it with your GitHub identity.** This opens an OIDC login, choose GitHub:

```
cosign sign-blob --yes --new-bundle-format --bundle sig.bundle foton.dsse.json
# Retrieving signed certificate...
# tlog entry created with index: <n>          <- your signature is now in the Rekor transparency log
# Wrote bundle to file sig.bundle
```

Keyless means: the login proves your GitHub identity to **Fulcio**, which issues a *short-lived
certificate* binding that identity to an *ephemeral* key; you sign with the ephemeral key; the
signature + certificate go into the public **Rekor** transparency log. Nothing long-lived to store or
leak.

**3. (automatic) Verify: valid signature, the right identity, logged in Rekor.**

```
# discover the identity that signed (accepts any, for inspection only):
cosign verify-blob --new-bundle-format --bundle sig.bundle \
    --certificate-identity-regexp '.+' --certificate-oidc-issuer-regexp '.+' foton.dsse.json
# Verified OK

# in production you PIN the exact identity and issuer, never accept '.+':
cosign verify-blob --new-bundle-format --bundle sig.bundle \
    --certificate-identity you@example.com \
    --certificate-oidc-issuer https://github.com/login/oauth  foton.dsse.json
```

The identity lives in the certificate's SAN (an `email:...`), and the OIDC issuer
`https://github.com/login/oauth` says GitHub vouched for it. A verifier trusts **Fulcio** (the CA) and
**Rekor** (the log), not you.

## How this fits kton

This is the **authority-backed tier** from [example 07](../07-identity/), made real for a person:

- **subject** = the kton record (by its content hash) - the thing signed.
- **principal** = your GitHub/OIDC identity - who signed it.
- **authority** = Fulcio (issues the identity certificate) + Rekor (timestamps and witnesses it in a
  public, append-only log).
- **no long-lived key** - the signing key is ephemeral and thrown away; the *certificate* is the
  durable proof, and it is only as trusted as Fulcio + your OIDC provider.

Compared to tier 2 (example 07's attested claim, "I trust the deployer's key that says this"), tier 3
removes the need to trust any single vouching key: the binding is backed by a CA and a transparency
log the whole ecosystem already audits.

> **Next:** record this binding back into kton as an identity claim, so the GitHub signer becomes a
> node in the graph (`sec:controller` of the record's key, the Verifiable-Credential form). That is
> part of the identity-vocabulary work; a Fulcio certificate *is* already exactly such a
> key-to-identity statement.

## Run it yourself

```
bash run.sh      # prints the sign command to run, then re-run it to verify
```

You will need `cosign` installed and a GitHub account. Your identity and signature become **public**
in the Rekor transparency log, that is how keyless Sigstore works.
