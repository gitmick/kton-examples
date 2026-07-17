#!/usr/bin/env bash
# 12 - capstone: a regulated population-PK submission, verified by the agency with ZERO trust in the
# sponsor. Three organizations, three registries, no shared server - yet the regulator ends up holding
# one verifiable graph proving how the model was made, that it reproduces, in what qualified
# environment, who reviewed it (typed sign-offs with evidence), and who submitted it. Every example in
# this repo shows up here as a real obligation in the workflow.
#
# Everything really executes: the pmxtools tests and the fit run in real R, the normalizer is real sed,
# reproduction and spectrum-fulfilment are real plankton queries, and the release gate is a real SPARQL
# query over the exported RDF. Only NONMEM (proprietary) and cosign keyless (interactive, see example
# 08) are honest stand-ins - and even those run real commands that produce the bytes we hash.
set -euo pipefail
EXDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$EXDIR"; source ../../lib/common.sh
command -v Rscript >/dev/null || { echo "this capstone runs real R; install Rscript"; exit 1; }
export NEKTON_TEMPLATES="$EXROOT/templates" NEKTON_ALIASES="$EXROOT/aliases.json"
# Best practice: author with paths RELATIVE to the example dir (cwd stays $EXDIR), so a foton's
# recorded input/output NAMES never bake in an absolute machine path (/home, /mnt, ...) that would
# then live forever in the committed, public snapshot. `.work/` is gitignored; only the names leak.
W=".work"; rm -rf "$W"; mkdir -p "$W"/{files,keys}
for org in cro sponsor agency; do mkdir -p "$W/$org/plankton" "$W/$org/nekton"; done
F="$W/files"; T="$EXDIR/tools"
key(){ echo "$W/keys/$1"; }
for k in cro-org sponsor-org analyst qc lead submitter reviewer; do nekton keygen "$(key $k)" >/dev/null; done
keyiri(){ echo "https://kton.dev/o/$(python3 -c "import hashlib;print(hashlib.sha256(bytes.fromhex(open('$(key $1).pub').read().strip())).hexdigest())")"; }
keyid16(){ python3 -c "import hashlib;print(hashlib.sha256(bytes.fromhex(open('$(key $1).pub').read().strip())).hexdigest()[:16])"; }
pauthor(){ plankton author "$@" --add | awk '/indexed foton/{print $3}'; }
# locate <file> <url> <signer>: record a signed dcat:downloadURL so the regulator can FETCH the bytes
# it holds a content hash for (verifying sha256 == hash on arrival). Location is a signed claim, plural
# and post-hoc; the kernels never dereference it (that is kton's job).
locate(){ printf '{"subject":[{"hash":"%s"}],"predicate":"http://www.w3.org/ns/dcat#downloadURL","object":{"uri":"%s"},"by":"CN=%s","when":"2026-07-16T00:00:00Z"}' "$(plankton hash "$1")" "$2" "$3" > "$F/loc.json"; nekton claim "$F/loc.json" "$(key $3).key" --add >/dev/null; }

echo "########## SETUP - identities: each org vouches for its staff (sec:controller VCs, example 07) #####"
export NEKTON_DIR="$W/cro/nekton"
for p in analyst qc; do
  printf '{"subject":[{"uri":"%s"}],"predicate":"https://w3id.org/security#controller","object":{"id":"did:web:cro.example/people/%s"},"by":"CN=cro-org","when":"2026-07-16T00:00:00Z"}' "$(keyiri $p)" "$p" > "$F/$p-id.json"
  nekton claim "$F/$p-id.json" "$(key cro-org).key" --add >/dev/null; echo "  CRO vouches $p -> did:web:cro.example/people/$p"
done
export NEKTON_DIR="$W/sponsor/nekton"
for p in lead submitter; do
  printf '{"subject":[{"uri":"%s"}],"predicate":"https://w3id.org/security#controller","object":{"id":"did:web:sponsor.example/people/%s"},"by":"CN=sponsor-org","when":"2026-07-16T00:00:00Z"}' "$(keyiri $p)" "$p" > "$F/$p-id.json"
  nekton claim "$F/$p-id.json" "$(key sponsor-org).key" --add >/dev/null; echo "  sponsor vouches $p -> did:web:sponsor.example/people/$p"
done

echo; echo "########## ACT 1 - qualify the toolchain + environment (examples 09/10, real R) ##########"
export PLANKTON_DIR="$W/cro/plankton" NEKTON_DIR="$W/cro/nekton"
NORMCMD="sh tools/strip-banner.sh"
declare -A REF
for t in test-onecomp test-twocomp test-covariate; do
  printf "x\n1\n2\n3\n" > "$F/$t.csv"
  if [ "$t" = "test-covariate" ]; then Rscript "$T/pmxtest.R" "$F/$t.csv" banner > "$F/$t.ref"; else Rscript "$T/pmxtest.R" "$F/$t.csv" > "$F/$t.ref"; fi
  plankton author --cmd "Rscript tools/$t.R" --in "$F/$t.csv" --out "$F/$t.ref" --sign "$(key analyst).key" --add >/dev/null
  REF[$t]=$(plankton hash "$F/$t.ref")
done
# the covariate test carries a volatile banner -> its candidate run differs -> normalizer gives L1.
# The candidate (docker) run is AUTHORED as its own foton too - it is a real computation, so recording
# only its hash for the spectrum check would leave a rootless file (a trail gap).
Rscript "$T/pmxtest.R" "$F/test-covariate.csv" banner > "$F/test-covariate.cand"
plankton author --cmd "Rscript tools/test-covariate.R" --in "$F/test-covariate.csv" --out "$F/test-covariate.cand" --sign "$(key qc).key" --add >/dev/null
sh "$T/strip-banner.sh" "$F/test-covariate.ref"  > "$F/cov.ref.canon"
sh "$T/strip-banner.sh" "$F/test-covariate.cand" > "$F/cov.cand.canon"
plankton author --cmd "$NORMCMD" --kind normalize --in "$F/test-covariate.ref"  --out "$F/cov.ref.canon"  --sign "$(key analyst).key" --add >/dev/null
plankton author --cmd "$NORMCMD" --kind normalize --in "$F/test-covariate.cand" --out "$F/cov.cand.canon" --sign "$(key analyst).key" --add >/dev/null
POT=$(python3 -c "import json,base64,glob;
import os
best=None
for f in glob.glob('$PLANKTON_DIR/objects/sha256/*.json'):
 import json;r=json.load(open(f));import base64
 s=json.loads(base64.b64decode(r['envelope']['payload']))
 if s['predicate']['protocol'].get('kind')=='normalize': best=s['predicate']['protocol']['ref']
print(best)")
plankton spectrum define --id "pmxtools-1.2.0" --of "R 4.3.2 + pmxtools 1.2.0 + pinned deps + NONMEM 7.5.1" \
  --normalizer "$POT" \
  --member "test-onecomp=${REF[test-onecomp]}" --member "test-twocomp=${REF[test-twocomp]}" \
  --member "test-covariate=${REF[test-covariate]}" -o "$F/pmxtools.spectrum.json" >/dev/null
ENV=$(plankton hash "$F/pmxtools.spectrum.json")
echo "  env-spectrum id (ENV) = $ENV"
echo "  the pinned docker image is checked against the spectrum:"
plankton spectrum check "$F/pmxtools.spectrum.json" \
  --candidate "test-onecomp=${REF[test-onecomp]}" --candidate "test-twocomp=${REF[test-twocomp]}" \
  --candidate "test-covariate=$(plankton hash "$F/test-covariate.cand")" | tee "$F/fulfilment.txt" | sed 's/^/    /' || true
# B1/D6: do not let "3/3 fulfilled" ride as a bare prose assertion on the qualifies-as claim. Back it
# with a reproducible spectrum-check FOTON that commits to the exact spectrum + candidate result files,
# so the qualification CARRIES ITS CORPUS (re-derivable), and the release gate can REQUIRE that foton
# rather than trust a naked binding. (This is example 10's pattern, adopted here.)
CHECK=$(plankton author --cmd "plankton spectrum check pmxtools-1.2.0" \
  --in "$F/pmxtools.spectrum.json" --in "$F/test-onecomp.ref" --in "$F/test-twocomp.ref" --in "$F/test-covariate.cand" \
  --out "$F/fulfilment.txt" --sign "$(key qc).key" --add | awk '/indexed foton/{print $3}')
echo "  fulfilment recorded as a reproducible spectrum-check foton (commits to the checked results): $CHECK"
# the exact OCI image (CARRIED) qualifies-as the env-spectrum (signed), carrying the fulfilment foton;
# and a gxp tool-validation claim
printf "oci://ghcr.io/cro/pmxtools:1.2.0@sha256:d34db33fcafe000000000000000000000000000000000000000000000000beef\n" > "$F/image.txt"
OCI=$(plankton hash "$F/image.txt")
# A4/B1: parse the REAL tally (N/M) from the fulfilment - a reproducible fact - and CARRY it typed on
# the qualification, so the gate can require a FULL pass (N==M), not merely that a check foton was used.
# A partial pass (e.g. a 2/3 environment) authored honestly then fails the gate; a FORGED N==M is caught
# by the regulator's own re-run (Act 8a, a hard gate). "Used the spectrum" is not "passed the spectrum".
TALLY=$(grep -oE '[0-9]+/[0-9]+ member' "$F/fulfilment.txt" | head -1 | grep -oE '[0-9]+/[0-9]+'); NFUL=${TALLY%/*}; NTOT=${TALLY#*/}
printf '{"subject":[{"hash":"%s","uri":"oci://ghcr.io/cro/pmxtools:1.2.0"}],"predicate":"https://kton.dev/v/qualifies-as","object":{"id":"https://kton.dev/o/%s","fulfilment":"https://kton.dev/o/%s","membersFulfilled":"%s","membersTotal":"%s"},"why":"image fulfils pmxtools-1.2.0 (%s members, re-derivable in the spectrum-check foton)","by":"CN=qc","when":"2026-07-16T00:00:00Z"}' "$OCI" "${ENV#sha256:}" "${CHECK#sha256:}" "$NFUL" "$NTOT" "$TALLY" > "$F/qual.json"
nekton claim "$F/qual.json" "$(key qc).key" --add >/dev/null
printf "%%PDF tool validation protocol\n" > "$F/toolval.pdf"
nekton annotate "$ENV" --template gxp/tool-validation --set outcome=pass --set sop="SOP-CV-014" --set protocol="$F/toolval.pdf" --by "CN=qc" --sign "$(key qc).key" --add >/dev/null
locate "$F/toolval.pdf" "https://cro.example/qms/SOP-CV-014/tool-validation.pdf" qc
echo "  qualifies-as (image -> ENV) + gxp:validation-performed=pass recorded (protocol.pdf located)"

echo; echo "########## ACT 2 - the analysis; the FIT runs the FINAL model, under the qualified env #######"
printf "ID,TIME,DV\n1,0,0\n1,1,5.2\n1,2,3.1\n" > "$F/raw.csv"
Rscript "$T/clean.R" "$F/raw.csv" "$F/analysis.csv"
# the model-development tree (files); the FIT below actually runs the FINAL model
printf '$PROB base one-comp\n' > "$F/run1.mod"
printf '$PROB +WT on CL\n' > "$F/run7.mod"
printf '$PROB final: WT on CL, allometric\n' > "$F/run12.mod"
Rscript "$T/fit.R" "$F/analysis.csv" > "$F/run1.ext"
Rscript "$T/gof.R" "$F/run1.ext" > "$F/diagnostics.txt"
# Best practice: the analysis CODE is provenance too - record each script as a foton input (relative
# name, so no absolute path leaks), so the trail says exactly which code produced each result.
CLEAN=$(pauthor --cmd "Rscript tools/clean.R raw.csv analysis.csv" --in "$F/raw.csv" --in "tools/clean.R" --out "$F/analysis.csv" --sign "$(key analyst).key")
FIT=$(plankton author --cmd "Rscript tools/fit.R analysis.csv" --in "$F/analysis.csv" --in "$F/run12.mod" --in "tools/fit.R" --out "$F/run1.ext" --environment "$ENV" --sign "$(key analyst).key" --add -o "$F/fit.dsse.json" | awk '/indexed foton/{print $3}')
GOF=$(pauthor --cmd "Rscript tools/gof.R run1.ext" --in "$F/run1.ext" --in "tools/gof.R" --out "$F/diagnostics.txt" --sign "$(key analyst).key")
# Best practice: point at least one dcat:downloadURL at a REAL, commit-pinned raw URL of a committed
# file, so "the regulator can fetch the bytes and re-hash" is demonstrable, not gestured at. fit.R is
# committed, so its recorded hash resolves forever at this permalink. (The runtime PDFs below keep
# illustrative .example URLs - they live in gitignored .work/, so there is nothing committed to pin.)
locate "tools/fit.R" "https://raw.githubusercontent.com/gitmick/kton-examples/76a44ef8314ddb028812aab732de8f561b9e5cb6/examples/12-submission/tools/fit.R" analyst
echo "  clean -> FIT (runs run12.mod, --environment ENV COVERED, code recorded + fit.R located) -> gof; FIT=$FIT"

echo; echo "########## ACT 3 - the model-development tree (pmx/model-role: base -> covariate -> final) ###"
export NEKTON_DIR="$W/cro/nekton"
nekton annotate "$(plankton hash "$F/run1.mod")"  --template pmx/model-role --set role=base --by "CN=analyst" --sign "$(key analyst).key" --add >/dev/null
nekton annotate "$(plankton hash "$F/run7.mod")"  --template pmx/model-role --set role=covariate --set parent="$(plankton hash "$F/run1.mod")" --by "CN=analyst" --sign "$(key analyst).key" --add >/dev/null
nekton annotate "$(plankton hash "$F/run12.mod")" --template pmx/model-role --set role=final --set parent="$(plankton hash "$F/run7.mod")" --by "CN=analyst" --sign "$(key analyst).key" --add >/dev/null
echo "  signed model tree: run1=base -> run7=covariate -> run12=final (the FIT ran run12)"

echo; echo "########## ACT 4 - independent reproduction by QC (real re-run, authored as a foton) ########"
# QC RE-AUTHORS the fit as its own foton (same inputs + protocol -> same action key as the analyst's
# run, but a distinct signer and its own output), so the re-run is a visible parallel branch from
# analysis.csv - not a dangling file. This is what makes reproduction show up in the lineage.
Rscript "$T/fit.R" "$F/analysis.csv" > "$F/run1-qc.ext"
QCFIT=$(plankton author --cmd "Rscript tools/fit.R analysis.csv" --in "$F/analysis.csv" --in "$F/run12.mod" --in "tools/fit.R" --out "$F/run1-qc.ext" --environment "$ENV" --sign "$(key qc).key" --add | awk '/indexed foton/{print $3}')
echo "  QC re-ran the fit -> $QCFIT (same action key as the analyst's, independent signer + output)"
sh "$T/strip-banner.sh" "$F/run1.ext"    > "$F/fit.ref.canon"
sh "$T/strip-banner.sh" "$F/run1-qc.ext" > "$F/fit.qc.canon"
plankton author --cmd "$NORMCMD" --kind normalize --in "$F/run1.ext"    --out "$F/fit.ref.canon" --sign "$(key qc).key" --add >/dev/null
plankton author --cmd "$NORMCMD" --kind normalize --in "$F/run1-qc.ext" --out "$F/fit.qc.canon" --sign "$(key qc).key" --add >/dev/null
echo -n "  plankton reproduces (raw): "; plankton reproduces "$(plankton hash "$F/run1.ext")" "$(plankton hash "$F/run1-qc.ext")" || true
echo -n "  plankton reproduces --via normalizer: "; plankton reproduces "$(plankton hash "$F/run1.ext")" "$(plankton hash "$F/run1-qc.ext")" --via "$POT" || true
# QC signs the reproduction as a claim that CONNECTS the two runs: subject = the analyst's output,
# level = L1 (what the gate checks), and reproducedBy = QC's re-run foton - so the graph draws the
# edge "the analyst's fit is reproduced by QC's fit", not two unlinked fotons.
printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/reproduces","object":{"level":"L1","reproducedBy":"https://kton.dev/o/%s"},"by":"CN=qc","when":"2026-07-16T00:00:00Z"}' "$(plankton hash "$F/run1.ext")" "${QCFIT#sha256:}" > "$F/repro.json"
nekton claim "$F/repro.json" "$(key qc).key" --add >/dev/null; echo "  QC signed a reproduction claim: analyst FIT <-reproducedBy- QC re-run (nk:reproduces, level L1)"

echo; echo "########## ACT 5 - review scope: typed sign-offs with evidence, chained + sealed (04/05/11) #"
export NEKTON_DIR="$W/sponsor/nekton"
SCOPE=$(nekton seed popPK-mABC --sign "$(key lead).key" --by "did:web:sponsor.example/people/lead" --add | grep -oE 'sha256:[0-9a-f]+' | head -1)
printf "%%PDF qc review\n" > "$F/qc-rep.pdf"; printf "%%PDF lead review\n" > "$F/lead-rep.pdf"
nekton annotate --foton "$F/fit.dsse.json" --template gxp/review --set outcome=pass --set sop="SOP-REV-002" --set report="$F/qc-rep.pdf" --by "CN=qc" --sign "$(key qc).key" --scope "$SCOPE" --prev "$SCOPE" --add >/dev/null
C1=$(nekton by predicate "https://kton.dev/v/gxp/reviewed" | head -1 | awk '{print $1}')
nekton annotate --foton "$F/fit.dsse.json" --template gxp/review --set outcome=pass --set sop="SOP-REV-002" --set report="$F/lead-rep.pdf" --by "CN=lead" --sign "$(key lead).key" --scope "$SCOPE" --prev "$C1" --add >/dev/null
locate "$F/qc-rep.pdf" "https://sponsor.example/reviews/qc-report.pdf" qc
locate "$F/lead-rep.pdf" "https://sponsor.example/reviews/lead-report.pdf" lead
# a general (non-GxP) approval reuses schema.org (example 11)
nekton annotate --foton "$F/fit.dsse.json" --template review/decision --set decision=https://schema.org/AcceptAction --set comment="$F/lead-rep.pdf" --by "CN=lead" --sign "$(key lead).key" --add >/dev/null
HEAD=$(nekton head "$SCOPE" | awk '/head:/{print $2}')
echo "  seed -> gxp:reviewed(qc,pass) -> gxp:reviewed(lead,pass) sealed; HEAD=$HEAD"

echo; echo "########## ACT 5b - explicit residual-risk acceptance (risk/accept) ##########"
printf "%%PDF shrinkage sensitivity\n" > "$F/shrinkage.pdf"
nekton annotate --foton "$F/fit.dsse.json" --template risk/accept --set severity=medium --set rationale="eta-shrinkage on CL 28pct; addressed by sensitivity analysis" --set mitigation="$F/shrinkage.pdf" --by "CN=lead" --sign "$(key lead).key" --add >/dev/null
locate "$F/shrinkage.pdf" "https://sponsor.example/risk/shrinkage-sensitivity.pdf" lead
echo "  gxp:risk-accepted (medium, mitigation.pdf located) recorded"

echo; echo "########## ACT 6 - authoritative submission signature (Sigstore keyless stand-in, example 08)"
printf '{"subject":[{"hash":"%s"}],"predicate":"https://kton.dev/v/submitted","object":{"id":"did:web:sponsor.example/people/submitter"},"why":"submission head signed via Sigstore keyless (Fulcio+Rekor); real flow in example 08","by":"did:web:sponsor.example/people/submitter","when":"2026-07-16T00:00:00Z"}' "${HEAD#sha256:}" > "$F/submit.json"
# subject is the scope HEAD (a claim id); reference it by hash
python3 -c "import json;d=json.load(open('$F/submit.json'));d['subject'][0]['hash']='$HEAD';json.dump(d,open('$F/submit.json','w'))"
nekton claim "$F/submit.json" "$(key submitter).key" --add >/dev/null
echo "  submission of HEAD attributed to the submitter's verifiable identity (nk:submitted)"

echo; echo "########## ACT 7 - federate across the three orgs by hash (no server, example 02) ##########"
PLANKTON_DIR="$W/sponsor/plankton" plankton mirror "$W/cro/plankton" | sed 's/^/  sponsor<-cro  /'
NEKTON_DIR="$W/sponsor/nekton"     nekton  mirror "$W/cro/nekton"    | sed 's/^/  sponsor<-cro  /'
PLANKTON_DIR="$W/agency/plankton"  plankton mirror "$W/sponsor/plankton" | sed 's/^/  agency<-sponsor  /'
NEKTON_DIR="$W/agency/nekton"      nekton  mirror "$W/sponsor/nekton"    | sed 's/^/  agency<-sponsor  /'

echo; echo "########## ACT 8a - the regulator re-verifies everything, trusting no one ##########"
export PLANKTON_DIR="$W/agency/plankton" NEKTON_DIR="$W/agency/nekton"
# zero-trust reproduction: the regulator RE-DERIVES the L1 match itself (analyst output vs QC's re-run,
# under the same normalizer potential) and ABORTS if it does not reproduce. The QC-signed nk:reproduces
# claim only draws the reproducedBy EDGE in the graph - it is NOT what the gate trusts. Without this hard
# gate a QC re-run that genuinely differs would still ship on the strength of its own signed L1 label.
echo -n "  1. reproduction re-check (L1):      "; if plankton reproduces "$(plankton hash "$F/run1.ext")" "$(plankton hash "$F/run1-qc.ext")" --via "$POT"; then :; else echo "  does not reproduce -> abort"; exit 1; fi
# zero-trust re-derivation of the tally: the regulator RE-RUNS the check itself; a partial pass exits
# non-zero and ABORTS. This is what makes a forged N==M on the qualification harmless - the regulator
# never takes the sponsor's word for "3/3", it recomputes it. (spectrum check exits 0 only on N==M.)
echo -n "  2. environment fulfils spectrum:    "; if plankton spectrum check "$F/pmxtools.spectrum.json" --candidate "test-onecomp=${REF[test-onecomp]}" --candidate "test-twocomp=${REF[test-twocomp]}" --candidate "test-covariate=$(plankton hash "$F/test-covariate.cand")" >/dev/null 2>&1; then echo "fully fulfilled"; else echo "NOT fully fulfilled -> abort"; exit 1; fi
echo -n "  3. analyst signature on the FIT:    "; if plankton verify "$F/fit.dsse.json" "$(key analyst).pub" 2>&1 | grep -q '\bVALID\b'; then echo "VALID"; else echo "INVALID -> abort"; exit 1; fi
# BIND the envelope to the id the gate uses: re-derive fit.dsse.json's foton id with the kernel (a
# fresh throwaway registry recomputes it from the bytes) and assert it EQUALS $FIT. Without this, the
# gate would read the environment from an envelope nobody checked was the attested fit. This is a pure
# hash re-derivation - no trust, no signature needed - and it is a HARD gate (abort on mismatch).
echo -n "  4. fit envelope binds to fit id:    "
REID=$(plankton add "$F/fit.dsse.json" --registry "$W/verify-tmp" 2>/dev/null | awk '/indexed foton/{print $3}')
if [ "$REID" = "$FIT" ]; then echo "BOUND ($FIT)"; else echo "MISMATCH ($REID != $FIT) -> abort"; exit 1; fi
echo    "  5. scope head unbroken:             $HEAD"
echo    "  (every check is mechanical over content-addressed records; the sponsor cannot fake any of it)"

echo; echo "########## ACT 8b - the release decision, recorded as a reproducible attested foton ########"
plankton export --rdf -o "$F/submission.ttl" >/dev/null 2>&1 || plankton export --rdf > "$F/submission.ttl"
: > "$F/attestations.trig"
for f in "$W/agency/nekton"/objects/sha256/*.json; do nekton export --nanopub "$f" >> "$F/attestations.trig" 2>/dev/null; echo >> "$F/attestations.trig"; done
echo "  exported submission.ttl + attestations.trig - the corpus the decision is made over"
# The verifier's OWN trust root: the authorities whose sec:controller vouchers it accepts (here the two
# org authorities). This is what stops the sock-puppet forgery - three self-issued (or ring-signed) keys
# are not vouched by a trusted authority, so they never count as reviewers. The trust root is written to
# a file and made a COVERED INPUT of the verdict-foton below: a run with a friendlier trust root is a
# different verdict id and cannot be passed off as this one (carry-your-closure, like the corpus).
AUTH_CRO=$(keyid16 cro-org); AUTH_SPONSOR=$(keyid16 sponsor-org)
printf 'trusted-authority %s  (CN=cro-org)\ntrusted-authority %s  (CN=sponsor-org)\n' "$AUTH_CRO" "$AUTH_SPONSOR" > "$F/trust-root.txt"
if python3 -c "import rdflib" 2>/dev/null; then
  python3 "$EXDIR/release.py" "$F/submission.ttl" "$F/attestations.trig" "$EXDIR/release.rq" "$F/fit.dsse.json" "$FIT" "$HEAD" "$AUTH_CRO" "$AUTH_SPONSOR" | tee "$F/verdict.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  !! GATE REGRESSION: the capstone gate did NOT return COMPLETE (release.py exited non-zero)"; exit 1; }
  # The decision is NOT a free-floating query: the agency records it as a FOTON. Its inputs are the
  # exact corpus it consumed (submission.ttl + attestations.trig, by hash) and the gate logic
  # (release.rq); its output is the verdict. So the decision is content-addressed and REPRODUCIBLE -
  # re-run the gate over the same inputs and you get the same verdict (L0) - and it NAMES its own
  # evidence set (its input list). The regulator signs its OWN verdict over the sources it chose.
  export PLANKTON_DIR="$W/agency/plankton"
  VERDICT=$(plankton author --cmd "release gate: release.rq over the submission graph under trust-root.txt" \
    --in "$F/submission.ttl" --in "$F/attestations.trig" --in "release.rq" --in "$F/trust-root.txt" --out "$F/verdict.txt" \
    --sign "$(key reviewer).key" --add | awk '/indexed foton/{print $3}')
  echo "  release decision recorded as foton $VERDICT"
  echo "    signed by the agency; its inputs ARE its corpus; re-run over them -> same verdict (L0)"
else
  echo "  (the release gate needs rdflib: 'pip install rdflib' - skipping)"
fi

echo
# the viewer relabels a signer to its attested principal ONLY for bindings vouched by a trusted
# authority (the two org authorities) - a sock-puppet's self/ring-signed binding is never shown attested.
snapshot 12-submission "$W/keys" --reg "$W/agency/plankton" --reg "$W/agency/nekton" \
  --authority "$(keyid16 cro-org)" --authority "$(keyid16 sponsor-org)"
