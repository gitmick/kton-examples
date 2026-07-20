# Static realization of the federation API — the mirror as files-by-hash

> Draft design note (kton-examples). Companion to **`plankton/docs/federation.md`**, which defines the
> concepts (resolve-by-hash, selective publication, the small federation API, append-only sync, mirroring).
> This note shows that API is realizable as **pure static files** — no server software — and works out what
> it costs to store, serve, and publish at world scale. Reference implementation: `viewer/build_mirror.py`,
> `docs/lens.js` (`data-mirror`), `docs/lens-multi.html`.

## The federation API is just files-by-hash

`federation.md` says a registry exposes a small API: `get-foton-by-output(hash)`, `uses(hash)`,
`attestations(subject)`, `sync(since)`. None of those needs a server — each is a path on a static host:

| federation API | static path | read |
|---|---|---|
| `get-foton-by-output(hash)` | `output/sha256/<ab>/<hash>/` | **list** → producer ids |
| `uses(hash)` | `input/sha256/<ab>/<hash>/` | list → consumer ids |
| `attestations(subject)` | `about/sha256/<ab>/<hash>/` | list → claim ids (the **nekton** endpoint) |
| fetch a record | `objects/sha256/<ab>/<hash>.json` | `GET` |
| `sync(since)` | copy the tree | append-only, so a plain `rsync`/`cp` |

Because the **filename is the content hash**, a lookup is O(1) and **scale-invariant**: resolving one hash is
the same operation whether the store holds five records or five billion. The reverse index
(`output/<outputHash>/ → [producers]`) is the "rainbow table of executions": given a file, who computed it.

```
objects/sha256/04/04134636…json           the record (immutable, self-verifying: it re-hashes to its own name)
output/sha256/73/73723a49…/04134636…       ← a producer of hash 73723a49 (one entry per foton that output it)
output/sha256/73/73723a49…/12eb670f…       ← another producer  → reproduction is just >1 entry here (↻N = the count)
input/sha256/a2/a212d6f9…/04134636…        ← a consumer
about/sha256/04/04134636…/6cadb8f3…        ← a claim about foton 04134636 (nekton)
keys.json  names.json                      for signature verify / labels
```

The 2-hex prefix (`…/73/73723a49…`) shards like git's `.git/objects/ab/…` so no directory holds millions of
files. On **object storage** keys are flat with no count limit, so sharding there is optional.

## Append-only index: markers or symlinks

An index entry's **name is the producer hash**, so listing the prefix yields the producers regardless of how
the entry is encoded. Two host-appropriate encodings, both **append-only — a new foton drops one file, nothing
is ever rewritten** (idempotent, order-independent → inherits plankton's drift):

- **symlink** (filesystem / nginx / IPFS): `output/…/<hash>/<pid>` → the single stored object. Zero bytes,
  deduplicated, and *list + follow* returns the record directly. On IPFS this is native — a directory node
  is a set of links to child CIDs.
- **marker** (object storage, which has no symlinks): a tiny `{"by": <keyid>}` named pointer; resolve the
  record via `objects/`. This is the portable form of a symlink — an entry whose identity is the target hash.

`build_mirror.py` emits markers by default and symlinks with `--symlink`; the lens reads either unchanged.

## No server software

The mirror is **dumb static files**. The host does exactly two things: return a file (`GET`) and list a prefix.
So it runs on the cheapest serving on the internet — nginx/apache/Caddy (autoindex on), static hosts
(GitHub/GitLab Pages, Netlify, Cloudflare Pages), object storage's native HTTP (S3/R2 + `LIST`), or IPFS
gateways. No database, no API server, no daemon. All the intelligence is client-side: hash the bytes, fetch by
name, **re-verify every object against its own hash**. Consequences: mirrors are `cp`/`rsync`-duplicable, and a
hostile host can only **withhold, never forge**. The one capability required is "**list a prefix**" (nginx
autoindex / S3 `LIST` / IPFS native).

## What it costs at world scale

Measured from the demos (~1.2 KB per signed record, ~⅓ index overhead) and extrapolated to **one billion fotons**:

| | |
|---|---|
| total static files | **≈ 1.6 TB** (1.2 TB records + 0.4 TB index) |
| **storage** | Backblaze B2 ~**$10/mo** · Cloudflare R2 ~**$24/mo** ($0 egress) · S3 ~$37/mo |
| **serve, per extra viewer** | **≈ $0** — immutable + content-addressed ⇒ cached at every CDN edge (origin serves each object ~once per edge, not per person); ingress/upload is free everywhere |
| **write / publish** | ~4 writes per foton (1 object + ~3 index entries), **append-only, one-time, never rewritten**. Request cost: **B2 $0** (uploads free) · R2 ~$18k · S3 ~$20k *one-time for a billion*. Marginal ≈ **$0.00002/foton** (S3), **$0** (B2) |

Two reasons it's cheaper than the table looks: the index is **linear** — each foton adds only its own
output/input edges and a reproduction adds exactly one entry, so "interconnections" never blow up
combinatorially; and because it **drifts**, you never publish a billion at once — each foton is published once
as it's made, amortized over years. Both writing and serving a global record of published computation is a
storage problem, and static storage of immutable, dedup'd, cacheable blobs is the cheapest thing there is.

## Plankton and nekton mirror the same way

The mechanics are identical for both layers — content-addressed objects + an append-only reverse index — and
even the **order** is content-addressed: a nekton chain is a linked list of claims whose `prev`/`subject` are
hashes, so you walk it by `GET`-ing hashes exactly like plankton lineage. Mirroring nekton is therefore just as
cheap and uses the same `about/` index.

The **one** thing a static mirror cannot provide — for either layer, but it bites nekton — is **currency and
completeness**: *"is this the latest head? have I seen every claim in this scope?"* A store can serve every
record but can withhold a newer one, so it can never *prove* you are current or complete. That is a **liveness**
property, not a storage one, and it is intentionally the *conversation* layer: you decide which aggregators you
consult and whether you believe they handed you the whole set (see `trust.md` and federation.md's *Selective
publication*). Integrity is cryptographic and free; completeness is a trust choice and deliberately yours.

## What to publish is the aggregator's decision

Content-addressing **enables** publication without **forcing** it. A foton is verifiable on a laptop or in a
public mirror; publishing is the deliberate act of dropping the finished object + its claims into a public
store, at a boundary the author and aggregator choose (federation.md, *Selective publication*: publish *starting
at* an aggregate; upstream hashes need never be mentioned; nothing leaks). So:

- **Closed working process** — the private substrate where work is *made* (in regulated contexts, the validated
  environment that binds the signature to a real person — the transactional last mile the protocol does not replace).
- **Publish** — a deliberate crossing at "finished," moving verifiable results + attestations into the open record.
- **Aggregator** — federates published work on dumb static hosting; its value is the *conversation* (curation,
  completeness for its scope, discovery), because the *facts* (storage/serving) are essentially free.

The public "rainbow table of all published computation" is thus the union of what aggregators chose to publish —
cheap to store, free to serve, incremental to write, and impossible to forge — while *what* to publish and *whom*
to believe about completeness stay with the people, not the protocol.

## Reference implementation

- `viewer/build_mirror.py` — union → mirror. `--add` (incremental append), `--symlink` (link index for FS/IPFS).
- `docs/lens.js` — `data-mirror`: resolves a figure's badge by hashing it and **listing one prefix**, verifying
  the producer objects; **never loads a whole union**. Reads marker or symlink mirrors identically.
- `docs/lens-multi.html` — a plot produced by 3 independent fotons (`↻3`), served lazily off the mirror, with
  the world-scale economics rendered on the page.
