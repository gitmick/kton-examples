# Briefing für den Examples-Workstream — 2026-09-01

Kommt aus der kton-Seite (Branch `dev`, gemerged auf `main` + PR #40 + #41). Alles hier ist gegen
den Code geprüft, nicht aus einem Report übernommen. Reihenfolge: **B1 zuerst**, der Rest hängt daran.

---

## B1 — Ein altes `nekton`-Binary liest den neuen Store als LEER, mit Exit 0

Das ist kein Beispiel-Bug, aber es trifft jedes Beispiel, und es ist die gefährlichste Sache in
diesem Briefing.

Seit #41 ist ein Subnekton eine Datei: `objects/scope/<scope_id>.nekton.jsonl` und
`objects/unscoped.nekton.jsonl`. Ein Binary von `v0.1.0` sucht `objects/**/*.json`, findet nichts,
und meldet:

```
$ NEKTON_DIR=<neuer store> nekton-v0.1.0 about sha256:1111
(none)
$ echo $?
0
```

Der Claim existiert, ist signiert und trägt zwei Signaturen. Das alte Binary sagt „nichts gesagt"
und beendet erfolgreich. Es gibt keinen Format-Marker im Store, an dem es das merken könnte.

**Für die Examples heißt das:** Solange die CI gegen ein anderes kton baut als das, mit dem der
Store erzeugt wurde, laufen Beispiele grün, die nichts geprüft haben. Kein Beispiel darf ein
vorgebautes oder installiertes `nekton` verwenden — immer das aus dem Checkout im selben Lauf.

---

## B2 — Die CI ist seit 2026-07-21 tot und meldet Erfolg

Der Workflow checkt das inzwischen archivierte, private `gitmick/plankton` aus. Seither werden alle
Schritte übersprungen, und der Lauf gilt als bestanden. Es hat also seit sechs Wochen niemand
gemerkt, dass nichts läuft.

Der Fix liegt hier unversioniert in `.github/workflows/ci.yml`:

- `repository: kton-protocol/kton` (kton ist umgezogen — **das Examples-Repo nicht**, das ist
  weiterhin `gitmick/kton-examples`, und das ist korrekt so)
- `path: _kton`, Build-Pfade `_kton/...`
- `PLANKTON_TOKEN` entfernt (das private Repo, für das er da war, gibt es nicht mehr)

Dazu: der Schritt darf nicht `continue-on-error` sein. Ein Checkout, der fehlschlägt, muss den
Lauf rot machen, nicht die Prüfung stillschweigend weglassen.

---

## B3 — Beispiele bestehen, obwohl ihre Prüfung nichts gesehen hat

Die unangenehmste Klasse, weil sie Verifikation *behauptet*. Drei belegte Fälle:

| Ort | Was passiert ist |
|---|---|
| `examples/05-review-scope/check.py` | fand null Claims, druckte BLOCKED — und das Beispiel bestand, weil `\|\| true` das Ergebnis verschluckte |
| `examples/11-review-template` | bestand mit einer 21 Byte großen `attestations.trig` (ein Helper-Bug schrieb die Temp-Datei ins falsche Argument) |
| `security/attacks/co-signer-drop.sh` (im kton-Repo) | globte `objects/sha256/*.json`, meldete nach #41 VULNERABLE, obwohl die Eigenschaft hält |

Der gemeinsame Nenner: **kein Beispiel prüft, dass es überhaupt etwas zu prüfen gab.** Jedes
`check`-Skript braucht vorne eine Zusicherung — „ich habe N Records gelesen, N > 0" — und darf
nicht hinter `|| true` stehen.

Der letzte Fall ist im kton-Repo schon behoben: `security/attacks/_records.sh` liest den Store
layout-unabhängig, und `security/check.sh` druckt jetzt seine eigene Abdeckung (10 von 28) statt
eine grüne Zeile, die mehr behauptet, als sie deckt. Dasselbe Muster gehört hierher.

---

## B4 — `findings.md`: F-016 und F-025 zurückziehen

Beide sind als **Blocker** eingetragen, mit „confirmed by reproducing F-016 live":

> `nekton claim review.spec.json reviewer.key review.dsse.json --add` sei ein Syntaxfehler.

Ist es nicht. `nekton/reference/cmd/nekton/main.go:214–229` parst `--add` und macht die
Ausgabedatei dabei sogar optional. Das gilt seit `d56827c` — v0.1.0, also seit dem ersten Tag, auf
`main` wie auf `dev`. Vermutlich lief die Reproduktion gegen ein altes oder falsches Binary — siehe
B1, genau dieser Fehlermodus.

Vier Beispiele (04, 06 und was daran hängt) stehen sonst zur „Reparatur" an, obwohl sie korrekt
sind.

---

## B5 — Das `reviewedBy`-Tripel in 04 und 06 ist verdreht

`examples/04-claim/run.sh:25` und `examples/04-claim/README.md:38-39`, kopiert nach
`examples/06-nanopub-rdf`:

```json
{"predicate":"pav:reviewedBy","object":{"value":"looks correct"},"by":"CN=Reviewer"}
```

`reviewedBy` ist passiv: „X wurde reviewt **von** Y". Der `object`-Slot gehört also der Identität
des Reviewers. Dort steht das Verdikt. Gelesen sagt das Tripel: *dieses Foton wurde von „looks
correct" reviewt* — und die Identität des Reviewers kommt in dem, was der Claim behauptet,
überhaupt nicht vor; sie steht nur in `by`, das den Claim signiert.

Das steht bereits als **F-017** in `findings.md`, aber die dortige Lösung („eine erklärende Zeile
ergänzen") dokumentiert den Fehler nur. Zwei tragfähige Fixes:

1. `"object": {"id": "CN=Reviewer"}` und das Verdikt nach `why` — bleibt bei PAV.
2. Ein aktives unäres Prädikat, z. B. `nekton/v/reviewed`, mit dem Verdikt als Literal.

Ich würde (2) nehmen: es ist das, was das Beispiel eigentlich zeigen will, und es umgeht die
Passiv-Falle ganz. Der Kernel fängt so etwas nie ab — er speichert Prädikate als opake IRIs und
interpretiert sie nicht. Das ist die richtige Designentscheidung und zugleich der Grund, warum
genau dieser Fehler durch alles durchgeht.

---

## B6 — Was sich durch #41 in den Beispielen ändert

Nichts am Protokoll, nur am Lesen des Stores. Auf `41-nekton-files` liegt bereits:

- `lib/records.sh` mit `records_of()` — liest `*.nekton.jsonl`-Zeilen **und** legacy `*.json`
- `viewer/build_union.py` und `examples/05-review-scope/check.py` mit demselben Reader inline
- `examples/11-review-template/run.sh`, `examples/12-submission/run.sh` auf einfache Schleifen
  umgestellt

**Ungeprüft und vor dem Merge zu prüfen:** ob diese Reader auch gegen den *alten* Kernel von
`origin/main` funktionieren — der Fall, den die CI heute tatsächlich hat. Sie lesen beide Formen,
es sollte also halten, bewiesen ist es nicht. Nach B2 ist das ein CI-Lauf, keine Handarbeit.

---

## Reihenfolge

1. **B2** — CI reparieren, sonst prüft niemand irgendetwas davon.
2. **B4** — die zwei falschen Blocker zurückziehen, bevor jemand korrekte Beispiele „repariert".
3. **B3** — jedes `check`-Skript bekommt eine „ich habe etwas gelesen"-Zusicherung, `|| true` raus.
4. **B5** — das Tripel in 04 und 06 geradeziehen.
5. **B6** — gegen `dev` verifizieren, sobald der Kernel dort gemerged ist.

**B1** ist keine Aufgabe für dieses Repo, aber die Release-Notes der nächsten kton-Version müssen
es aussprechen, und die Beispiele dürfen bis dahin kein Binary aus einer anderen Quelle als dem
Checkout benutzen.

---

## B7 — `.work/` ist getrackt, also verschmutzt jeder Beispiellauf den Index

Ein `bash examples/*/run.sh` über alle 14 Beispiele ändert **368 getrackte Dateien**. Zwei
getrennte Ursachen:

- `docs/data/**` — die Viewer-Snapshots. Der Diff ist **ausschließlich** ein neuer `keyid` und eine
  neue Signatur: jeder Lauf macht ein frisches Schlüsselpaar, der Payload ist byte-identisch. Diese
  Snapshots sind also durch Konstruktion nicht reproduzierbar und lassen sich nie sinnvoll
  diffen. Verwandt mit #42 (wall-clock `when` in `seed.go:64`), aber eine eigene Ursache.
- `examples/*/.work/**` — Arbeitsverzeichnisse mit Schlüsseln, Registries und Zwischenständen.

Beides gehört nicht in den Index. Solange es drin ist, ist jeder Beispiel-PR unlesbar, und ein
echter Unterschied — etwa dass 05 jetzt 13 Records sieht statt 0 — verschwindet zwischen 368
Zeilen Rauschen. Vorschlag: `.work/` ignorieren und aus dem Tracking nehmen; für `docs/data`
entweder deterministische Schlüssel (ein fester Seed pro Beispiel) oder ebenfalls nicht tracken
und im CI erzeugen.

## Verifiziert gegen kton 0.2

Alle 14 Beispiele laufen gegen die 0.2-Binaries durch (`fail=0`). Und, weil ein grünes PASS in
diesem Repo nachweislich nichts heißt (B3), stichprobenartig nachgeprüft, dass sie auch wirklich
etwas getan haben:

| Beispiel | vorher | jetzt |
|---|---|---|
| `05-review-scope` | 0 Claims gefunden, BLOCKED gedruckt, bestanden | 13 Records (1 Foton, 12 Claims), Szenarien 2+3 blocken korrekt |
| `11-review-template` | `reviews.trig` mit 21 Byte, bestanden | 9875 Byte, 3 Review-Claims, SPARQL `approvals=3/3, COMPLETE: True` |
| `12-submission` | 7 Bedingungen unerfüllt | `attestations.trig` mit 51631 Byte |

B6 ist damit erledigt: die neuen Reader funktionieren gegen den 0.2-Kernel. Gegen den *alten*
Kernel von `main` sind sie weiterhin ungeprüft — nach dem Merge von `dev` ist das gegenstandslos.
