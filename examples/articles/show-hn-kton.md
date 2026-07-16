# Show HN: kton – A Stateless, Non-Blockchain Protocol for Verifiable Data Pipelines and Human Attestations

## 1. Das Paradoxon: Die ungenutzten Millionen der Pharma-Industrie
Wenn wir Software entwickeln, tracken wir jede Änderung mit Git, versionieren Umgebungen mit Docker und automatisieren alles mit CI/CD. Doch sobald es um Datenwissenschaft, KI-Modellierung oder regulatorische Audits geht, bricht dieser Workflow zusammen.
* **In der akademischen Forschung** herrscht oft kreative Agilität, aber eine katastrophale Nachvollziehbarkeit (die Replikationskrise, Datenfriedhöfe in verstaubten PDFs) [1].
* **In der pharmazeutischen Entwicklung (GxP)** herrscht das Gegenteil: eine extrem strikte, millionenschwere Nachvollziehbarkeit [1, 1.2.2]. Doch sie hat ein massives Problem: **Ihr einziger Wert ist die behördliche Einreichung.** Sobald die Zulassung (z. B. durch die FDA) erteilt ist, wird dieser teure Nachweis-Pfad zu einem toten Dokumenten-Sarg [1, 1.2.2]. Er wird archiviert, nie wieder angefasst und hat keinerlei wissenschaftlichen Nutzen für die Zukunft.

Ich wollte ein System bauen, das diese Verschwendung beendet. Eine offene Infrastruktur, in der Nachvollziehbarkeit kein „totes Steuersiegel“ für Behörden ist, sondern ein **lebendiges, kollaboratives und wiederverwendbares Werkzeug** [1]. Ein System, bei dem der Herkunftspfad (die Provenienz) der Startpunkt für die nächste Generation von Wissenschaftlern ist, die darauf aufbauen, alternative Szenarien rechnen oder die Modelle verifizieren wollen [1].

---

## 2. Warum Blockchain die falsche Antwort ist (Die Entkoppelung von Plankton und Nekton)
Viele versuchen, dieses Problem mit einer Blockchain zu lösen, um ein „unveränderliches Logbuch“ zu schaffen. Das ist ein massives und teures Anti-Pattern:
* Wir haben kein Double-Spending-Problem. Berechnungen benötigen keinen *chronologischen* Konsens (Konsens über die Zeit), sondern eine *topologische* Konsistenz (Konsens über die Daten-Abhängigkeiten) [1].
* Um das ohne Blockchain-Overhead zu lösen, trennt `kton` das System in zwei streng entkoppelte Schichten [1]:

### Plankton (Die funktionale Realität)
`plankton` ist rein funktional, zustandslos und reihenfolge-unabhängig [1]. Jede Berechnung steht für sich allein. Sie wird nicht in eine künstliche, lineare Kette gezwungen [1]. Der einzig wahre Beweis für eine mathematische Berechnung ist ihre **lokale Reproduzierbarkeit** [1].

### Nekton (Das kausale Gespräch)
Menschliche Entscheidungen, Reviews oder Willenserklärungen (*„Ich habe dieses Modell geprüft und gebe es frei“*) sind das genaue Gegenteil [1]. Sie sind hochgradig kontextabhängig. Eine Aussage (ein Claim) ist nur so gültig wie das Gespräch, in dem sie entstand [1].
* Hier ist die Reihenfolge essenziell. Wenn ein Prüfer ein Modell ablehnt (*Reject*), darf dieser Schritt nicht heimlich unterschlagen werden [1].
* Daher nutzt `nekton` eine **kryptografische Hashchain** [1]. Jede Aussage referenziert den Hash der vorhergehenden Aussage [1]. Innerhalb einer *versiegelten Prüfkette* (eines *scope*) bricht die Kette ab, sobald ein Glied fehlt — ein unterschlagener Reject-Claim macht den veröffentlichten Kopf ungültig und die Manipulation sichtbar [1]. (Wichtig, und weiter unten aufgegriffen: das ist eine Eigenschaft der *geschlossenen* Prüfkette. Auf dem offenen Substrat ist eine unauflösbare Referenz nur *unvollständig*, nicht *ungültig* — sonst bräche Föderation.)

---

## 3. Die Poesie der Primitives: Foton, Plankton, Nekton
Die Namensgebung des Protokolls folgt einer klaren physikalischen und biologischen Analogie, die das System elegant beschreibt:

* **Foton** — *das Quant.* So wie ein Photon das unteilbare Quant des Lichts ist, ist ein **Foton** das unteilbare Quant einer Berechnung: ein signiertes Paket der Form *„diese Input-Dateien, durch dieses Kommando, ergaben diese Output-Dateien“*. Es ist masselos — es trägt nur die `sha256`-Hashes der Dateien, niemals die Bytes selbst. Der Record ist eine *Kante* in einem Herkunftsgraphen, nicht der Datenberg daran.
* **Plankton** — *das Umhergetriebene* (griech. *planktós*). Plankton driftet passiv mit der Strömung; jeder Organismus ist für sich lebensfähig und kennt keine Reihenfolge. Exakt so verhält sich die funktionale Schicht: Berechnungs-Records driften zwischen Umgebungen, jede Umgebung ist nur ein Verzeichnis, und zwei einander fremde Registries treffen sich von selbst am gleichen Inhalts-Hash — ohne Server, ohne Absprache. Föderation ist hier kein Protokoll, sondern eine Eigenschaft des Wassers.
* **Nekton** — *das Schwimmende* (griech. *nēktós*). Nekton schwimmt aktiv und gerichtet, oft gegen die Strömung. So verhält sich die Aussagen-Schicht: eine Attestierung hat eine Richtung, eine Kausalität, eine Reihenfolge — die Hashchain. Wo Plankton driftet, schwimmt Nekton mit Absicht.

In der Meeresbiologie sind *Plankton* und *Nekton* die zwei großen Abteilungen allen frei schwebenden Lebens — alles in der Wassersäule tut das eine oder das andere. Zusammen ergeben sie das ganze Ökosystem: **kton**. Und ein **Foton** ist das Lichtquant, das beide Schichten durchdringt — der Hash, an dem sich eine *Berechnung* (Plankton) und eine *Aussage darüber* (Nekton) am selben Knoten treffen.

---

## 4. Zeig es, erzähl es nicht: lauffähige Beispiele
Ein Protokoll ist nur so glaubwürdig wie das, was man selbst laufen lassen kann. `kton` kommt mit einer Reihe kleiner, in sich geschlossener Beispiele — vom `hello-foton` (eine Berechnung aufzeichnen, signieren, „wer hat diese Datei erzeugt?“ per Output-Hash fragen) bis zu einer vollständigen, regulierten Populations-PK-Einreichung, die eine Behörde mit *null Vertrauen* in den Einreicher nachprüfen kann.

Jedes Beispiel

* läuft mit einem einzigen `bash run.sh`,
* erzeugt echte Records **und** benutzt sie,
* und rendert den entstehenden Graphen in einem Viewer, sodass man genau sieht, was herauskam.

Die Kette baut aufeinander auf: ein Foton aufzeichnen → zwei fremde Registries per Inhalts-Hash zusammenführen (Multi-Source-Read, ganz ohne Kopie) → Reproduktion beweisen → eine signierte Aussage anhängen → eine versiegelte Review-Kette → Export nach RDF/PROV/Nanopublication → Identität → eine qualifizierte Umgebung → und als Finale die regulierte Einreichung, deren Freigabe-Entscheidung selbst ein reproduzierbarer Record ist.

**Live-Viewer:** https://gitmick.github.io/kton-examples/

---

## 5. Verifizieren statt vertrauen — und wo die Grenze ehrlich liegt
Der Anspruch *„prüf es selbst“* ist nur wahr, wenn man nicht gezwungen ist, **unseren** Verifizierer zu benutzen. Weil ein kton-Record kein Eigenformat ist, sondern ein **in-toto-Statement in einem DSSE-Envelope** (die Sprache von SLSA, Sigstore und in-toto), liest ihn jedes Standard-Werkzeug: ein zwanzigzeiliger Ed25519-Check mit einer gewöhnlichen Krypto-Bibliothek genügt — ganz ohne kton-Code.

Und — vielleicht das Wichtigste für ein reguliertes Publikum — das System behauptet nicht mehr, als es beweist:

* **„Verifizieren“ zerfällt in zwei Dinge.** Den *Record* prüfen (Signatur, Hash-Struktur, Form des Graphen) geht immer, überall, offline. Den *Inhalt* prüfen (die Bytes neu hashen, die Berechnung neu ausführen) braucht die Bytes — die reisen getrennt (git vs. git-annex). Mit null Bytes bleibt ein voll prüfbares Skelett aus Wer-behauptet-was; die Bytes legen die inhaltliche Wahrheit obendrauf.
* **Jedes *Urteil* über einen geschlossenen Kreis trägt seine eigene Welt mit sich.** „Das Review ist vollständig“, „das ist der aktuelle Stand“, „dieser Schlüssel ist Prof. A“ — ein solches Urteil committet *in seiner signierten Nutzlast* auf das, wogegen es geschlossen hat: die konsultierten **Quellen**, den aktuellsten **Kopf**, die vertraute **Autorität**. Andernfalls fährt man dasselbe Gate mit einer bequemeren Annahme neu und zeigt das Ergebnis vor.

Deshalb kein „die Kette macht Fälschung unmöglich“. Sondern das Ehrlichere und Stärkere: eine Fälschung ist genau so weit ausgeschlossen, wie die **Autorität reicht, der du selbst vertraust** — und genau diese Autorität reist im Urteil mit. Ein Schlüssel ist kein Mensch; erst eine von einer vertrauten Instanz signierte Bindung macht aus einem Signierschlüssel einen benannten Gutachter.

---

## 6. Status & Feedback
Die beiden Kerne — `plankton` und `nekton` — laufen und sind bewusst winzig und **ontologiefrei**: Der Kernel speichert signierte Subjekt-Prädikat-Objekt-Aussagen und interpretiert kein einziges Prädikat. Alles Domänenwissen — Vokabulare, Templates, Trust-Roots — ist föderierte Daten, kein Protokoll. Autoritätsgestützte Identität (Sigstore keyless, GitHub/SSH-Signaturen, eine Modell-CA) ist teils real, teils Roadmap, und als solche gekennzeichnet.

Ich freue mich über harte Fragen — besonders von Leuten aus Pharmakometrie, Reproduzierbarkeits-Forschung und verteilten Systemen. Was übersehe ich?

* **Beispiele & Viewer:** https://gitmick.github.io/kton-examples/
* **Code:** https://github.com/gitmick/kton-examples
