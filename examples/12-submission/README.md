# 12 - capstone: a regulated popPK submission, verified by the agency with zero trust

Three organizations, three registries, no shared server - yet the regulator ends up holding **one
verifiable graph** that proves how a population-PK model was made, that it reproduces, in what qualified
environment, who reviewed it, and who submitted it. Every earlier example shows up here as a real
obligation in a regulated submission, and at the end a single **SPARQL query decides whether the
submission may be released**.

Everything really executes: the `pmxtools` tests and the fit run in **real R**, the banner-normalizer is
a real, env-pinned, separately-qualified tool the regulator **re-runs itself**, reproduction and
spectrum-fulfilment are real `plankton` queries, and the release gate is real
SPARQL over the exported RDF. Only **NONMEM** (proprietary) and **cosign keyless** (interactive - the
real flow is [example 08](../08-sigstore-github/)) are honest stand-ins, and even those run real
commands that produce the bytes we hash.

## Cast

| identity | org | role |
|---|---|---|
| `analyst`, `qc` | CRO | builds the model / independent quality control |
| `lead`, `submitter` | sponsor | modeling lead (owns the review scope) / regulatory affairs |
| `reviewer` | agency | the regulator - **re-verifies everything, vouches for nothing of the sponsor's; signs only its own verdict** |

Each org vouches for its own staff with a `sec:controller` Verifiable Credential
([example 07](../07-identity/)): `<key> sec:controller did:web:<org>.example/people/<name>`.

## The eight acts (each maps to an example)

1. **Qualify the toolchain + environment** (09/10). The `pmxtools` test suite runs in real R, one test
   per foton; two reproduce byte-identical (L0), the covariate test carries a volatile banner so it only
   matches after the normalizer (L1). The suite becomes a **spectrum**; the pinned OCI image is checked
   `3/3` and bound to it with a signed `qualifies-as`; a `gxp:validation-performed=pass` claim carries
   the SOP + protocol PDF as hashed evidence.
2. **Run the analysis under the qualified environment** (01/09). `raw.csv -> analysis.csv -> FIT ->
   diagnostics`, where the fit is authored `--environment <ENV>` so "produced under a qualified
   environment" is **COVERED** - baked into the foton's identity.
3. **The model tree** (pmx). `pmx:model-role` tags each model file `base -> covariate -> final` with a
   parent ref, so the graph shows *why* run12 is the final model - a signed tree, not a filename.
4. **Independent reproduction** (03). QC **re-authors the fit as its own foton** (same inputs + protocol
   as the analyst's, so the same action key, but an independent signer and its own output) - so the
   re-run is a visible *parallel branch* from `analysis.csv`, not a dangling file. Raw outputs differ
   (the banner), so `plankton reproduces --via <normalizer>` returns **L1**; QC signs an `nk:reproduces`
   claim that **links the two runs** (the analyst's output, `reproducedBy` QC's re-run foton), so the
   reproduction is a visible edge between the two fotons - not two unlinked runs. A tampered `.ext`
   would return none - the check is pure hashing. The **normalizer is itself a pinned, qualified tool**:
   a free-text `--cmd "sh strip-banner.sh"` pins nothing (a substituted script that collapses a
   genuinely-different run to a matching form carries the same string), so every normalize foton is
   authored `--environment <normalizer-spectrum> --env-ref <image>`, and that spectrum is qualified by
   its own reference corpus (banner-laden -> canonical pairs it must reproduce). The `--via <normalizer>`
   potential now commits to *which* qualified normalizer ran, not just a command string.
5. **The review scope** (04/05/11). `nekton seed` opens a scope; two independent reviewers each sign a
   `gxp:reviewed=pass` (with report PDF evidence), chained `prev -> prev` and sealed by one **head**.
   Editing any earlier claim breaks the chain. A general approval reuses schema.org
   (`schema:AcceptAction`). Residual risk is accepted explicitly with `gxp:risk-accepted`.
6. **The submission signature** (08). Regulatory affairs signs the scope head with the org's GitHub/OIDC
   identity via Sigstore keyless (here a stand-in `nk:submitted` claim; the real Fulcio+Rekor flow is
   example 08). The agency trusts Fulcio + Rekor + GitHub, not the sponsor.
7. **Federate across the three orgs** (02). No server: `plankton mirror` / `nekton mirror` move records
   by hash, cro -> sponsor -> agency. The agency's registry now holds one lineage spanning all three
   parties - the FIT is a *shared node*, not a copy.
8. **The regulator verifies, then runs the release gate** (06). Every check the regulator runs is
   mechanical over content-addressed records - re-reproduce, re-check the spectrum, re-verify
   signatures, re-walk the head. It even **re-runs the banner-normalizer itself** in the pinned
   environment: first proving that normalizer is the qualified tool (its re-run reproduces the
   normalizer-spectrum's reference corpus), then re-normalizing the two fit outputs with it and
   demanding byte-equality - so the L1 match never rests on the sponsor's recorded normalize fotons. A
   substituted normalizer is caught twice (it fails to qualify, and the fake collapse never happens under
   the real one). Then it exports the RDF and runs the gate.

## The release gate

`plankton export --rdf` (the PROV lineage) plus every attestation as a **nanopublication**
(`nekton export --nanopub`) merge at shared hash IRIs into one graph. The shipped query
[`release.rq`](release.rq) returns one row per satisfied release condition; the submission is
releasable only if **all** appear.

Crucially the gate is **bound to this submission**: the query takes `?fit` (the estimation activity),
`?env` (the environment the fit *declares* - derived from the fit's own descriptor, not the sponsor's
word), and `?head` (the signed submission head), so every condition must be *about* this submission. An
unrelated pass/qualify/review elsewhere in the graph cannot satisfy it - a real risk, since a
federated store holds many submissions' records at once.

```
release checklist (SPARQL bound to this submission):
  [x] toolchain validated (gxp:validation-performed = pass)
  [x] the fit's environment is qualified (qualifies-as citing a check foton that FULLY passed, N==M)
  [x] the fit ran the designated final model (pmx:model-role = final)
  [x] the fit's output reproduces (nk:reproduces at L0/L1)
  [x] two distinct PRINCIPALS passed (each vouched by a trusted authority), no fail (gxp:reviewed)
  [x] residual risk explicitly accepted (gxp:risk-accepted)
  [x] the submission head is signed by a verifiable identity (nk:submitted)
RELEASE: COMPLETE - the submission may be accepted
  (same gate bound to an unrelated hash: 0/7 conditions -> BLOCKED)
```

The regulator does not read a checklist - it **runs the gate**, bound to the submission it was handed.
Remove any one attestation and the box clears and release blocks; point it at a different hash and every
box clears. That is the whole thesis of the stack made executable. (The gate needs `rdflib`: `pip
install rdflib`.)

And the decision is not a free-floating query - the agency records it as a **foton**: its inputs are the
exact corpus it consumed (`submission.ttl` + `attestations.trig`, by hash) and the gate logic
(`release.rq`); its output is the verdict; it is signed by the agency. So the decision is
content-addressed and **reproducible** - re-run the gate over the same inputs and you get the same
verdict (L0) - and it **names its own evidence set** (its input list). A regulator does not trust the
sponsor's verdict; it re-derives its *own* verdict-foton over the sources it chose. (A verdict without
its corpus would be a configuration, not a statement.)

The corpus it names here is a *pre-exported* RDF snapshot (`submission.ttl` + `attestations.trig`). The
stronger form takes the **nekton records directly** (by hash) and runs the RDF export **inside** the gate
foton, so its input is the signed evidence itself rather than a derivation of it - one fewer out-of-band
step to trust, and the verdict's input edges then point straight at the attestations it counted.

## What the gate proves, and what it assumes

The gate is deliberately honest about its boundaries (this is the substrate's whole stance; see the
protocol's [Trust chapter](https://github.com/gitmick/plankton/blob/main/docs/trust.md)). It proves the
seven conditions hold **over the corpus it was handed** - no more:

- **"two reviewers" means two distinct PRINCIPALS, each vouched by a trusted authority - not two
  distinct keys.** This is the one that has to be a *join*, not a count, or the "zero-trust" gate is a
  forgery machine: one actor generates three keys, self-issues (or ring-signs: K1 vouches K2, K2 vouches
  K3, K3 vouches K1 - no self-loop) three `sec:controller` bindings, and each key genuinely approves.
  A key-count gate reads 3/3; the viewer would render three named reviewers. So the gate does **not**
  count keys. It requires each approving key to chain, through a `sec:controller` binding **signed by an
  authority the verifier itself names** (the `#TRUSTED#` root - here the two org authorities), to a
  distinct principal. A binding the trusted authorities did not sign never counts. *Executed:* a naive
  key-count reads the ring as 3/3; this gate rejects it (0 authority-vouched), and the viewer marks the
  self/ring-signed bindings unattested. It passes only if the *verifier* trusts those keys - which is a
  different trust root, hence (see below) a different verdict.
  - **Boundary (not closed): two DIDs, one human.** The gate proves two *distinct authority-vouched
    principals*; it cannot prove they are two distinct *people*. If a trusted authority vouches two DIDs
    that are in fact the same human (e.g. an org issues its own analyst a second reviewer identity), the
    gate reads two independent reviews. That is a property of the **authority's** honesty in issuing
    principals, not something the substrate can decide from signatures. For real independence, require the
    reviewers' vouching **authority to differ from the author's** (cross-org review) - a trust-root policy
    the verifier sets, not a bug the gate can close. The `?p1 != ?p2` join is necessary but not sufficient
    for "two humans."
- **"no reject" is corpus-relative.** The one non-monotone condition (`FILTER NOT EXISTS` a fail review)
  means "no fail *in the corpus loaded*". A withheld failing review makes the gate pass. The gate names
  its corpus (its inputs) but cannot itself establish that the corpus is complete - that is the
  **completeness** boundary, and it is a property of the source list, not of the hash. *This one is
  irreducible*: you cannot prove a negative over a partial union. It is labeled, not closed.
- **the environment is bound to the fit before it is read.** The gate reads the env from the fit
  envelope's own descriptor; Act 7 first **hard-gates** that this envelope's foton id equals the bound
  `fit_hash` (it re-derives the id with the kernel and aborts on mismatch), so the env is read from the
  *attested* fit, not an unchecked file. The check runs; it is not a promise.
- **"used the spectrum" is not "passed the spectrum".** The `qualifies-as` claim cites a **spectrum-check
  foton** (its inputs are the spectrum plus the checked results), the gate requires that foton to have
  `prov:used` the env-spectrum the fit declares, **and** it requires the carried tally to be a *full*
  pass - `membersFulfilled == membersTotal`. A `2/3` environment carries `membersFulfilled=2` and fails
  the branch (verified: tamper the tally to 2/3 and `env-qualified` goes dark). A *forged* `3/3` is
  caught by the regulator in Act 8a two ways. The kernel `spectrum check` recomputes the tally itself and
  aborts on a partial pass (exit 0 only on `N==M`), so a forged count over honest results fails. But for
  a **via-normalizer (L1) member** that check *follows the sponsor's recorded normalize fotons* - so a
  genuinely-unqualified environment (a covariate result of `6.66` where the reference is `6.00`, honestly
  hashed) plus **one lying normalize foton** claiming it converges to the reference form would score
  "fulfilled" (**spectrum-launder**). The close: for the L1 member the regulator **re-executes the
  qualified normalizer itself** on both the reference and the candidate and demands byte-equality
  (mirrors the reproduction re-run in step 1b) - an unqualified candidate does not normalize to the
  reference form under the real tool. Strip the fulfilment entirely and the branch also fails. (A
  kernel-emitted, signature-bound outcome triple so the SPARQL alone rejects a forged tally without any
  re-run remains a plankton roadmap item; today the regulator's re-execution is the zero-trust half.)

### Carry your closure - the one principle behind three of these

A closed-world judgment must commit, **inside its own signed payload, to every parameter that defines
its closure** - or it is re-runnable with a friendlier parameter for a friendlier answer:

- **corpus** - else run over a subset that omits the reject;
- **latest anchored head** (freshness) - else present an older, cleaner prefix;
- **trust root** (identity) - else run with an authority who vouches for the clique.

The verdict-foton already carries its corpus. The identity fix is the *same* move on the trust root:
`trust-root.txt` is a **COVERED input** of the verdict-foton, so a run with a different set of trusted
authorities is a different foton id and cannot be passed off as this one. Not three patches - one
principle, three instances. (The anchored-head/freshness instance is the roadmap item; see the Trust
chapter.)

None of the residual limits are hidden: the verdict carries its corpus *and its trust root*, so a
smaller-corpus or friendlier-authority rerun is a *different*, comparable verdict. The only irreducible
caveat is corpus-relative "no reject"; the freshness/anchor instance is the remaining roadmap item.

> **Why qualification is safe under federation (and the gate is not a "third closed world").** Reading
> more sources can only *complete* a qualification, never revoke one: the spectrum's member set is
> pinned by its hash (a defined set that travels, not one discovered per source), and each member check
> is a *positive* existence ("a fulfilling foton exists"). So qualification is **monotone** - unlike the
> release gate's one non-monotone condition ("no reject *exists*", a negative existential). The only way
> to read qualification as closed-world is to treat "not yet 3/3" as *failed* rather than *not yet
> established*; kton takes the latter, open-world reading. That is why the substrate keeps exactly two
> deliberate closed worlds (the sealed review scope and the gate/verdict), and qualification is not a
> third.

## Fetchable evidence (the bytes, not just the hashes)

Every sign-off carries its document by **hash** (`nk:evidence`), and every such file also gets a signed
`dcat:downloadURL` **located-at** claim, so the regulator can actually *fetch* the file it holds a hash
for and verify `sha256 == hash` on arrival. Location is a signed, plural, post-hoc claim - the kernels
never dereference it; resolving it is kton's job. In the viewer these fold into the per-file locators
rather than cluttering the graph.

To make that concrete and not just gestured at, the analysis code (`tools/fit.R`) is recorded as a
foton input and located at a **real, commit-pinned raw URL** - fetch it, re-hash it, and it matches the
recorded `sha256` forever. (The runtime PDFs keep illustrative `.example` URLs: they are generated in
gitignored `.work/`, so there is nothing committed to pin them to.)

## Best practices this example follows

- **No absolute paths in the record.** Author with paths relative to the example dir, so a foton's
  recorded input/output *names* never bake in a machine path (`/home`, `/mnt`, ...) that would then
  live forever in the committed, public snapshot.
- **Code is provenance.** Each analysis script is a recorded foton input, so the trail names exactly
  which code produced each result - not just the data.
- **Real, pinned locations for committed bytes; fictional identities stay fictional.** Evidence
  locations point at commit-pinned raw URLs that actually resolve and re-hash; the *organizations* stay
  `did:web:*.example` (RFC 2606 reserves `.example` so fictional entities never point at a real domain).

## Complete trails: nothing changed outside kton

The point of the substrate is a **complete** trail: every file in the graph is either a hand-authored
root (raw data, a model file, a reviewer's PDF) or the recorded output of a foton. There is a subtle way
to break that - run a real command that transforms data (a QC re-run, a candidate test run) and only
**hash** its output to feed a `reproduces` / `spectrum check`, without authoring the computation. The
output then dangles as a rootless node: data was changed *outside* the trail. This example is careful to
author *every* such computation - QC's re-run and the candidate test run are fotons, not just hashes -
so open the graph and the only rootless nodes are genuine inputs. Reproduction and qualification are
visible as parallel branches, not asserted in prose.

## What is real today

Everything in Acts 1-8 uses shipped machinery, with two honest exceptions: NONMEM (proprietary, so the
estimation is a real-R stand-in) and the human submission signature (Act 6), whose real Sigstore keyless
flow ships in [example 08](../08-sigstore-github/) but runs interactively. The org-vouches-for-staff
bindings use the attested tier (real today); a full model-CA / SSH `allowed_signers` authority path is
still roadmap (plankton issues #20, #21).

## Run it yourself

```
bash run.sh
```

Open the graph to see the whole thing in one frame: the lineage, the model tree, every signed
attestation, and every signer - the five people plus the two org authorities - across three
organizations that never shared a server.
