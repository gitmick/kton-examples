# 18 with the cockpit

The same cycle as `run.sh`, with the cockpit's verbs instead of the kernel's. In the cockpit every
participant is a git checkout with its own identity (`cockpit keygen`), and every `publish`/`say` is
committed and shared to `origin`. The protocol underneath is the same: the records it writes are the
fotons and claims `run.sh` writes by hand.

Status, 17.11.2026, cockpit `(devel)` on kton v0.3.0: steps 1 and 2 **run as shown** (output below is
real). Steps 3 and 4 are **written, not yet run**: they need a `reviewed` template, a vocabulary
package that brings `four-eyes.rq`, and the SPARQL engine, which is in the cockpit's unreleased build.

## 1. The llm runs it and says what it is (tested)

The agent session's checkout. Its identity is its own key; through MCP it has exactly the three verbs.

```sh
cockpit init                      # cockpit.config.json, the default templates
cockpit keygen llm                # keys/llm.key (private), registry/keys/llm.pub (committed)
Rscript whales.R
cockpit publish --in whales.R --out whales.svg -- Rscript whales.R
#   out  whales.svg   sha256:6047f5cec2af7afc…   persisted and shared
cockpit say describes whales.svg value="Simulates 24 months of plankton density and whale sightings and draws both in one figure."
cockpit say rationale whales.svg value="To see whether whale sightings rise a month after the plankton does."
```

In a session the same three calls are `cockpit_publish`, `cockpit_say`, `cockpit_say` (`cockpit mcp`).

## 2. michael reruns it in his own checkout (tested)

```sh
git clone <the repo> && cd <it>
cockpit keygen michael            # this checkout now signs as michael
rm whales.svg && Rscript whales.R
cockpit publish --in whales.R --out whales.svg -- Rscript whales.R
cockpit ask reproductions whales.svg
#   ↻2 — 2 independent verified signer(s) produced these bytes
```

Same bytes, same foton: michael's signature lands on the llm's record.

## 3. The review, as its own scope (not yet run)

Who counts as a person is michael's policy, so it lives in his configuration as trust tiers, not in the
protocol:

```sh
cockpit trust add people <ana's checkout>   --yes
cockpit trust add people <ben's checkout>   --yes
cockpit trust add agents <llm's checkout>   --yes
```

The scopes, and the rule anchored before anyone reviews:

```sh
cockpit scope seed examples                              # then name it in claims.scopes
cockpit scope seed review-whales --parent examples       # likewise
cockpit install packages/review --allow                  # brings the 'reviewed' template and four-eyes.rq
cockpit say review-initialised review-whales rule=four-eyes.rq --scope review-whales
```

ana and ben, each in their own checkout, after `git pull`:

```sh
cockpit say reviewed whales.svg value=approve --scope review-whales --expect-head <head>
```

michael seals it into the parent:

```sh
cockpit sync
cockpit scope seal review-whales
```

## 4. Is the review valid? (not yet run)

```sh
cockpit config query.image oxigraph/oxigraph@sha256:10677fb6…
cockpit ask sparql --name four-eyes
```

`ask sparql` answers over the records a key in michael's trust tiers verifies, in a pinned Oxigraph.
To make the verdict a foton, as in `run.sh`, run it as a step:

```sh
cockpit run --dir check --in four-eyes.rq -- cockpit ask sparql four-eyes.rq --json
```

Open: whether the query can see the tier a key is in (`people` / `agents`), or whether the person /
agent statements have to be claims, as in `run.sh`.
