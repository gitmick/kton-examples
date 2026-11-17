# Lens paper: *Pygoscelis*

`../lens-paper.html` is a fabricated field report over real, cited data. The
published finding is correct and independently reproduced, and still misleading,
because a decision — split by species — was never written down. Nobody cheats
here. What the marks on the figures show is the gap.

Four registries, four things a reader can be:

| | |
|---|---|
| Palmer Field Station | the report as published |
| `+ Ethics Committee` | it re-ran the anonymisation and got the released file back. The input is named by hash, with no address |
| `+ Reviewer 2` | the reproduction, and the analysis split by species that the report does not contain |
| `view as the Committee` | only now does `penguins-named.csv` carry an address, and the animals have names |

The last is a change of role, not another source. A reviewer cannot switch it on.

## Rebuilding

```
./build.sh                 # rebuild in place
./build.sh --serve 8413    # …and serve docs/ so you can look at it
```

Needs `Rscript`, and `plankton` and `nekton` on `PATH` (or `$PLANKTON` / `$NEKTON`).
Everything is reproducible: keys from fixed seeds, animal names from
`set.seed(1999)`, claim timestamps from `--when`, and R's `svg()` device writes
byte-identical output for the same input. Two runs give the same tree.

`src/` holds what is not generated: the CC0 source data and the R scripts.
`files/`, `figures/`, `ethics/`, `reviewer/` and `reg/` are all output.

## Publishing: two commits

A locator says where bytes live. For a permalink that address contains the commit
carrying them — which does not exist until they are committed. So:

```
./build.sh
git add docs/lens-paper.html docs/lens-paper/{build.sh,README.md,.gitignore,src,files,figures,ethics,reviewer}
git commit -m "lens paper: payload"
SHA_A=$(git rev-parse HEAD)

./build.sh --base https://raw.githubusercontent.com/gitmick/kton-examples/$SHA_A/docs/lens-paper
git add docs/lens-paper/reg
git commit -m "lens paper: records with permalinks"

python3 ../../bin/check-permalinks.py --against-ref $SHA_A
```

The second run leaves the payload untouched — locators are CARRIED, so they do
not change a foton id. Only the addresses and the signatures differ.

The last line is the one that matters: it resolves every address against the
repository and re-hashes the bytes. Add `--http` once it is pushed to also fetch
them over the network.

## A word about the names

In reality the committee would not publish `penguins-named.csv` at all. Here it is
reachable because the demo has to run in a browser. The animal names are invented;
the measurements are not. See `src/SOURCE.txt`.
