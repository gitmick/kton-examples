# 01 - hello foton

The smallest possible **create + use**: record one computation as a signed foton, then query it.

## What `run.sh` does

- **ANLEGEN (create):** make an identity (`keygen`), create an input and an output file, and record
  the computation as a foton with `plankton author` (`inputs -> protocol(cmd) -> outputs`), then
  `plankton add` it to the registry.
- **VERWENDEN (use):** `plankton show` the foton, `plankton verify` its signature, and `plankton
  producer <outputHash>` to ask "who produced this file?".

## Key idea

A **foton** is a content-addressed edge: it names its input and output files by their `sha256:` hash
and carries an opaque protocol descriptor. plankton stores none of the bytes. `verify` checks the
Ed25519 signature against a public key; the declared keyid in the envelope is only a hint until you
verify.

## Run

```
bash run.sh
```

## Expected output (abridged)

```
foton:   sha256:3999af22...
command: mean data.txt result.txt   (RECORDED, never run by plankton)
inputs:
  .work/data.txt      sha256:76f7ad21...
outputs:
  .work/result.txt    sha256:69d22a6b...
signature:       VALID - verified as keyid 94c121b1127cc9db (the authoritative signer)
```

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/01-hello-foton/union.json&keys=data/01-hello-foton/keys.json&names=data/01-hello-foton/names.json)
