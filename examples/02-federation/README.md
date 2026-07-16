# 02 - federation

Two people build on each other's work. The natural first thought is "put both of them on one shared
store", and that works. But often you *can't* share a store (different orgs, an air-gap, no server).
The real lesson: **two independent registries converge to the same lineage by content hash - with no
shared store and nothing copied** - because every record is named by its content. We build up to it in
three acts, each sharing *less* than the last.

Three things could be "shared" here; keep them apart:

1. **the registry** (the records) - shared in Act 1, separate from Act 2 on.
2. **the file bytes** - plankton stores none, only hashes; on one machine they just sit in the working
   folder. Whoever wants to re-hash a file obtains its bytes out-of-band (see the note in Act 3).
3. **the records, copied by `mirror`** - Act 3, and it is an *optimization*, not the mechanism.

The coupling drops act by act:

| act | what is shared | coupling |
|---|---|---|
| 1 | the registry | maximal - one store both write to |
| 2 | nothing - both registries read as sources | none - **this is the primitive** |
| 3 | records, copied by `mirror` | optional - a cache for offline / single-store reads |

Assumes `plankton` is on your PATH. (New to fotons? Do [example 01](../01-hello-foton/) first.)

You will see a registry named two ways below, they are interchangeable: the **`PLANKTON_DIR=<dir>`**
environment variable (prefix a single command), or the **`--registry <dir>`** flag (on the commands
that write to a store: `add`, and `author --add`). `--registry X` is simply `PLANKTON_DIR=X` for that
one command. The read commands take a third form, **`--source <dir>`** (Act 2), which names the stores
to read as a union.

## Setup

```
plankton keygen alice
plankton keygen bob
echo "raw,data"     > dataset.csv
echo "cleaned,data" > cleaned.csv
echo "model=fit"    > model.txt
MODEL=$(plankton hash model.txt)     # the file we will query the lineage of, in every act
```

## Act 1 - two people, one shared registry

**What is shared: the registry.** alice and bob both `plankton add` into the *same* `PLANKTON_DIR`,
like a shared database, or a git remote everyone pushes to.

```
mkdir shared
# alice cleans the dataset. --add files it into the shared store (--registry shared) in one step;
# -o keeps the envelope so the later acts can re-file the SAME record elsewhere.
plankton author --cmd "clean dataset.csv cleaned.csv" \
    --in dataset.csv --out cleaned.csv --sign alice.key --add --registry shared -o alice.foton.json
# bob fits a model on alice's output, into the same store:
plankton author --cmd "fit cleaned.csv model.txt" \
    --in cleaned.csv --out model.txt --sign bob.key --add --registry shared -o bob.foton.json
```

The closing query - the full lineage of `model.txt`:

```
PLANKTON_DIR=shared plankton lineage "$MODEL"
# sha256:...  kind=script   <- bob's fit
# sha256:...  kind=script   <- alice's clean
```

## Act 2 - two separate registries, read as one (the federation primitive)

Now each person keeps their **own** registry. Nothing is shared between them; bob's `reg-b` has never
heard of alice's `reg-a`. Neither store alone holds the whole story:

```
mkdir reg-a reg-b
plankton add alice.foton.json --registry reg-a    # alice's record -> registry A
plankton add bob.foton.json   --registry reg-b    # bob's record   -> registry B

# bob's store ALONE: the fit is there, but its input dangles - alice's clean is not in reg-b
PLANKTON_DIR=reg-b plankton lineage "$MODEL"
# sha256:...  kind=script   <- bob's fit        (alice's clean is missing here)
```

A record that references something you cannot yet see is still valid on its own hash and signature -
it is *incomplete*, not invalid. (That is the open substrate; contrast the deliberately sealed scope of
[example 05](../05-review-scope/), where a dangling link *is* rejected.) Naming a second source
completes the lineage, and **copies nothing**:

```
# read BOTH registries as sources - no mirror, no shared store, neither store is mutated
plankton lineage --source reg-a --source reg-b "$MODEL"
# sha256:...  kind=script   <- bob's fit
# sha256:...  kind=script   <- alice's clean   (joined from reg-a, by hash)
```

**That is federation.** The two records meet at the shared input hash (`cleaned.csv` - alice's output
is bob's input) the moment someone reads both stores; the convergence comes from the content address,
not from any copy or handshake. `--source` names the stores to union - it *replaces* `PLANKTON_DIR`
rather than adding to it, so the sources you read are exactly the ones you name. Adding a source can
only *complete* a lineage, never invalidate one already resolved: more sources, more resolvable, never
less true.

### A stranger reads them both

Nothing above required alice and bob to know each other - or to know the reader. A third person,
**carol**, who has never touched either registry, can name both as sources and get the identical merged
lineage:

```
# carol knows neither alice nor bob; she just points at both stores
plankton lineage --source reg-a --source reg-b "$MODEL"    # same complete lineage
```

That is the whole graph vision in one command: independent people and programs converge on one lineage
because they name the same content, not because anyone was introduced or told to.

## Act 3 - mirror: copying records, as an optimization

Reading many sources on every query is fine, but sometimes you want one store that answers *alone* -
offline, or a single cache. `mirror` copies **records (hashes)** from one registry into another. It
moves no file bytes:

```
PLANKTON_DIR=reg-b plankton mirror reg-a
# mirrored reg-a: 1 new; reg-b now holds 2 fotons
PLANKTON_DIR=reg-b plankton lineage "$MODEL"
# sha256:...  kind=script   <- bob's fit
# sha256:...  kind=script   <- alice's clean   (now resident in reg-b)
```

Same merged lineage as Act 2, now materialized in one store. **`mirror` is a convenience on top of the
read - not what makes federation work.** (On this machine `cleaned.csv` still just sits in the working
folder; in reality whoever re-hashes it obtained those bytes out-of-band. `mirror` did not carry them -
it moves records, never content.)

## Or just run the whole thing

```
bash run.sh
```

## See it

The viewer colours the two participants differently, so you see one federated graph from two
registries.

[Open the graph](https://gitmick.github.io/kton-examples/viewer.html?union=data/02-federation/union.json&keys=data/02-federation/keys.json&names=data/02-federation/names.json)
