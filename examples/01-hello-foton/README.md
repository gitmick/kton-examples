# 01 - hello foton

The smallest complete example: **record** one computation, then **use** the record. Six commands.

This assumes `plankton` and `nekton` are installed and on your PATH. One thing to hold onto from the
start: **plankton records; it never runs your command.** It stores that *these input hashes*, through
*this command*, produced *these output hashes*, and signs that statement. (Checking that a re-run
actually reproduces the output is a separate step, see example 03.)

## Walk through it, one command at a time

**1. Make an identity.**

```
plankton keygen me
```

Writes `me.key` (your private key, keep it) and `me.pub` (your public key, share it).

**2. Have some files.** A computation reads files and writes files. Here, by hand:

```
echo "3 7 2 8" > data.txt
echo "mean=5"  > result.txt
```

plankton stores none of these bytes, only their `sha256:` content hash.

**3. Record the computation as a foton.**

```
plankton author --cmd "mean data.txt result.txt" \
    --in data.txt --out result.txt --sign me.key -o mean.foton.json
```

A **foton** is one edge of a lineage graph: `inputs -> command -> outputs`, each file named by its
hash, signed by you. Again: plankton does not execute `mean`; it records the statement that this
command, with these input hashes, produced these output hashes.

**4. File it into the registry.**

```
plankton add mean.foton.json
# indexed foton sha256:3999af22...
```

The registry is just a directory (`PLANKTON_DIR`, default `./plankton-data`).

**5. Read it back.**

```
plankton show mean.foton.json
# foton:   sha256:3999af22...
# command: mean data.txt result.txt   (RECORDED, never run by plankton)
# inputs:  data.txt    sha256:76f7ad21...
# outputs: result.txt  sha256:69d22a6b...
```

**6. Verify the signature.**

```
plankton verify mean.foton.json me.pub
# signature: VALID - verified as keyid 94c121b1... (the authoritative signer)
```

`verify` checks the signature against the public key you give it.

**7. Ask the graph a question:** who produced `result.txt`?

```
plankton producer $(plankton hash result.txt)
# sha256:3999af22...  kind=script  in=1 out=1
```

`plankton hash <file>` prints the `sha256:<hex>` form the queries expect.

## Or just run the whole thing

```
bash run.sh
```

Same steps, in a throwaway directory, plus it builds the graph snapshot for the viewer.

## See it

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/01-hello-foton/union.json&keys=data/01-hello-foton/keys.json&names=data/01-hello-foton/names.json)

## Why this matters (footnote)

The envelope also carries a *declared* keyid, but that is only a hint until you `verify`: the
authoritative signer is whichever key actually validates the signature. Under the hood, signatures
are Ed25519 over a DSSE envelope. You need none of this for step one; it is simply why the steps
above can be trusted by someone who did not run them.
