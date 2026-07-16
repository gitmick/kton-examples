# 12 - capstone: a regulated popPK submission, verified by the agency with zero trust

Three organizations, three registries, no shared server - yet the regulator ends up holding **one
verifiable graph** that proves how a population-PK model was made, that it reproduces, in what qualified
environment, who reviewed it, and who submitted it. Every earlier example shows up here as a real
obligation in a regulated submission, and at the end a single **SPARQL query decides whether the
submission may be released**.

Everything really executes: the `pmxtools` tests and the fit run in **real R**, the normalizer is real
`sed`, reproduction and spectrum-fulfilment are real `plankton` queries, and the release gate is real
SPARQL over the exported RDF. Only **NONMEM** (proprietary) and **cosign keyless** (interactive - the
real flow is [example 08](../08-sigstore-github/)) are honest stand-ins, and even those run real
commands that produce the bytes we hash.

## Cast

| identity | org | role |
|---|---|---|
| `analyst`, `qc` | CRO | builds the model / independent quality control |
| `lead`, `submitter` | sponsor | modeling lead (owns the review scope) / regulatory affairs |
| `reviewer` | agency | the regulator - **signs nothing, re-verifies everything** |

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
4. **Independent reproduction** (03). QC re-runs the fit in the qualified image; raw outputs differ (the
   banner), so `plankton reproduces --via <normalizer>` returns **L1**. QC signs an `nk:reproduces`
   claim. A tampered `.ext` would return none - the check is pure hashing.
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
   signatures, re-walk the head. Then it exports the RDF and runs the gate.

## The release gate

`plankton export --rdf` (the PROV lineage) plus every attestation as a **nanopublication**
(`nekton export --nanopub`) merge at shared hash IRIs into one graph. The shipped query
[`release.rq`](release.rq) returns one row per satisfied release condition; the submission is
releasable only if **all** appear:

```
release checklist (SPARQL over the merged graph):
  [x] toolchain validated (gxp:validation-performed = pass)
  [x] environment qualified (a signed qualifies-as binding)
  [x] a final model is designated (pmx:model-role = final)
  [x] the fit reproduces (nk:reproduces at L0/L1)
  [x] two independent reviewers passed, no fail (gxp:reviewed)
  [x] residual risk explicitly accepted (gxp:risk-accepted)
  [x] submission signed by a verifiable identity (nk:submitted)
RELEASE: COMPLETE - the submission may be accepted
```

The regulator does not read a checklist - it **runs the gate** over the merged graph. Remove any one
attestation and the corresponding box clears and release blocks. That is the whole thesis of the stack
made executable. (The gate needs `rdflib`: `pip install rdflib`.)

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
attestation, and the six participants - across three organizations that never shared a server.
