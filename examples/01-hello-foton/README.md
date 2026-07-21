# 01 - hello foton

New here? This page reads best right after the
[30-second intro](https://gitmick.github.io/kton-examples/), which defines the words used below. In
one line to get you going:

> A **foton** is a small signed record that says *"these input files, run through this command,
> produced these output files."* Making one, and reading it back, is all example 01 does.

**The thing that surprises everyone first: plankton does not run anything.** You run your analysis
however you like (a script, a notebook, a tool); plankton only *records* what went in, what came out,
and who says so. It never executes your command. So in this example we will **write the result by
hand** and then hand plankton the record. That is not cheating, it is the point: recording *that*
something was produced, and *reproducing* it to check, are two different jobs. (Reproduction is
example 03.)

Two words you will meet below:

- a **hash** (written `sha256:...`) is a fingerprint of a file's exact bytes: the same bytes give the
  same fingerprint, change one byte and it is completely different. plankton identifies every file by
  its hash, never by its name or location, and stores none of the bytes.
- a **registry** is the directory where plankton files its records (set by `PLANKTON_DIR`, default
  `./plankton-data`), a plain folder, a *store*. (Not an execution environment like a container or an
  OS, that is a separate thing.)

This assumes `plankton` is installed and on your PATH.

## Walk through it, one command at a time

**1. Make an identity.**

```
plankton keygen me
```

Writes `me.key` (your private key, keep it) and `me.pub` (your public key, share it).

**2. Stand in for the analysis.** Normally your script reads an input and writes an output; here we
just type both by hand (plankton will *record* that the command produced the output, not run it):

```
echo "3 7 2 8" > data.txt
echo "mean=5"  > result.txt
```

`3 7 2 8` really does have mean 5. plankton stores none of these bytes, only their hash.

**3. Record the computation as a foton, and file it into the registry.** `--cmd` records the command
string as metadata (a label — plankton never runs it); `--add` does both authoring and filing in one
step; `-o` also keeps the **envelope** — the signed foton as a DSSE-wrapped JSON file (here
`mean.foton.json`) — so we can show and verify it below.

```
plankton author --cmd "mean data.txt result.txt" \
    --in data.txt --out result.txt --sign me.key --add -o mean.foton.json
# authored foton ... -> mean.foton.json
# indexed foton sha256:...  (registry now holds 1 fotons)
```

A **foton** is one edge of a lineage graph: `inputs -> command -> outputs`, each file named by its
hash, signed by you. Again: plankton does not execute `mean`; it records the statement that this
command, with these input hashes, produced these output hashes. The registry it was filed into is
just a directory (`PLANKTON_DIR`, default `./plankton-data`; `--registry <dir>` picks another) —
created automatically on the first `--add`/`add`, so you never `mkdir` it.

> `--add` is the convenience for the everyday case. Authoring and filing are still separate
> underneath — the two-step form is:
> ```
> plankton author --cmd "mean data.txt result.txt" --in data.txt --out result.txt --sign me.key -o mean.foton.json
> plankton add mean.foton.json
> ```
> `plankton author` alone just writes the signed record (to hand off or publish); `plankton add` alone
> files a record — yours, or one you received from someone else. `--add` fuses the two into the single
> command above.

**4. Read it back.**

```
plankton show mean.foton.json
# foton:   sha256:...
# command: mean data.txt result.txt   (RECORDED, never run by plankton)
# inputs:  data.txt    sha256:...
# outputs: result.txt  sha256:...
# declared keyid: ... (unverified envelope field - run `plankton verify` with the signer's key)
```

That last line is a *declared* identity — a hint the record makes about who signed it, **not yet
checked**. Step 5 is what turns "declared" into "verified".

**5. Verify the signature.**

```
plankton verify mean.foton.json me.pub
# signature: VALID - verified as keyid ... (the authoritative signer)
```

`verify` checks the signature against the public key you give it.

**6. Ask the graph a question:** who produced `result.txt`?

```
plankton producer $(plankton hash result.txt)
# sha256:...  kind=script  in=1 out=1
```

`plankton hash <file>` prints the `sha256:<hex>` form the queries expect — the whole `$(plankton hash
result.txt)` above is substituted with that hash before `producer` runs (i.e. `plankton producer sha256:...`).

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
