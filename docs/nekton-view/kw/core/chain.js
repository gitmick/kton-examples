/**
 * Reading a subnekton as the unit it is.
 *
 * The two substrates are stored differently because they are shareable differently. A foton is
 * valid on its own - content-addressed, self-contained, signed - so plankton keeps one object per
 * file and handing over a subset is a real, meaningful partial share. A subnekton is not like
 * that: its seed gives it identity and its chain gives it order and integrity, so it is only valid
 * WITH ITS WHOLE CONTEXT. Hence one file. The unit of the file is the unit of validity.
 *
 * SPEC §7.4 puts the consequence precisely: the closed-world guarantee - that the chain reaches
 * scope_id without a gap - is a SEAL-VERIFICATION judgment, made over the resolved union when the
 * seal is relied upon, and NOT an ingest-time rejection. Ingest is monotone: a well-formed signed
 * statement is accepted even if its `prev` is not yet resolvable, because it may live in another
 * source. So the check belongs downstream, which is to say here.
 *
 * What this can and cannot see, stated plainly:
 *   - a GAP (a `prev` nothing in the file answers)     -> visible
 *   - a FORK (two statements claiming the same `prev`) -> visible
 *   - LINES REORDERED                                  -> nothing to see, and rightly so
 *   - a truncated TAIL                                 -> NOT visible from the chain alone
 *
 * The third is not a blind spot. The file is a BAG, not a sequence: order lives in `prev` and
 * nowhere else, so the file never becomes a second, unsigned representation of order that could
 * drift from the signed one. Shuffling the lines therefore changes nothing, and a checker that
 * complained would be asserting an order the protocol deliberately does not store.
 *
 * The fourth IS a limit, and not one to work around: a chain proves what it contains, and only a
 * seal states where it ends.
 *
 * Sealing lives OUTSIDE the registry. `nekton head <scope-id>` gives a scope's tip, and that id is
 * published or anchored somewhere a later reader can reach; everything up to it is then immutable,
 * because any edit to a prior claim changes the tip. Before that point a holder of the keys could
 * still drop a statement and re-sign the rest - the chain cannot see it, and guaranteeing it did
 * not happen is a transactional audit-trail's job, not a graph's.
 *
 * So this computes the tip and says which tier it is standing on, never more:
 *
 *   HEAD          the tip these statements reach
 *   provisional   a gap means the real head may be unreachable - the kernel's own warning is
 *                 "never present a truncated chain as sealed in silence"
 *   sealed        only when a published head was handed in AND it matches
 *
 * `sealed` is therefore never true on the strength of the file alone, and cannot become true by
 * looking harder at it.
 */

const SCOPE_V0 = "https://kton.dev/scope/v0";
const bare = (h) => String(h || "").replace(/^sha256:/, "").toLowerCase();

function decode(rec) {
    try {
        const b64 = rec.envelope.payload;
        const json = typeof globalThis.atob === "function"
            ? globalThis.atob(b64) : globalThis.Buffer.from(b64, "base64").toString("binary");
        return JSON.parse(json);
    } catch { return null; }
}

/**
 * Walk one subnekton's records.
 * Returns {scope, scopeId, seed, length, tail, gaps, forks, orphans, intact, sealed}.
 */
export function readSubnekton(records) {
    const byId = new Map(), stmts = [];
    for (const r of records) {
        const st = decode(r);
        if (!st) continue;
        const id = bare(r.claimId);
        const body = st.predicate || {};
        const s = { id, seed: st.predicateType === SCOPE_V0 && !!body.genesis,
                    scope: bare(body.scope), prev: bare(body.prev && (body.prev.digest?.sha256 || body.prev)) };
        byId.set(id, s); stmts.push(s);
    }

    const seeds = stmts.filter((s) => s.seed);
    const seed = seeds[0] || null;
    const scopeId = seed ? seed.id : "";

    // a `prev` that nothing here answers: either a genuine gap, or a statement whose predecessor
    // legitimately lives in another source - monotone ingest means we cannot tell them apart alone
    const gaps = stmts.filter((s) => !s.seed && s.prev && !byId.has(s.prev)).map((s) => s.id);
    const orphans = stmts.filter((s) => !s.seed && !s.prev).map((s) => s.id);

    const byPrev = new Map();
    for (const s of stmts) if (!s.seed && s.prev) byPrev.set(s.prev, (byPrev.get(s.prev) || 0) + 1);
    const forks = [...byPrev].filter(([, n]) => n > 1).map(([p]) => p);

    // statements nothing points at. A linear chain has exactly one; several mean claims share a
    // prev, and each of those would have to be sealed separately (or the chain re-linked).
    const pointedAt = new Set(stmts.map((s) => s.prev).filter(Boolean));
    const heads = stmts.filter((s) => !pointedAt.has(s.id)).map((s) => s.id);

    // follow the links from the seed; whatever it reaches is the chain this file actually proves
    let reached = 0, tail = scopeId;
    if (seed) {
        const next = new Map();
        for (const s of stmts) if (!s.seed && s.prev) next.set(s.prev, s.id);
        const seen = new Set([scopeId]);
        let at = scopeId;
        while (next.has(at)) { const n = next.get(at); if (seen.has(n)) break; seen.add(n); at = n; reached++; }
        tail = at;
    }

    return {
        scope: seed ? (decodeScopeName(records, scopeId) || "") : "",
        scopeId, seed: !!seed, seeds: seeds.length,
        length: stmts.length, reached, tail,
        gaps, forks, orphans, heads,
        head: heads.length === 1 ? heads[0] : "",
        // a withheld middle leaves the successors - maybe the real head - unreachable, so the tip
        // above is only the tip of what we HAVE
        provisional: gaps.length > 0 || heads.length !== 1,
        intact: !!seed && seeds.length === 1 && !gaps.length && !forks.length && !orphans.length
                && reached === stmts.length - 1,
        sealed: false,   // nothing was handed in to compare against - see sealState()
    };
}

function decodeScopeName(records, scopeId) {
    for (const r of records) {
        if (bare(r.claimId) !== scopeId) continue;
        const st = decode(r);
        return st && st.predicate && st.predicate.scope;
    }
    return "";
}

/**
 * Hold a subnekton against a published head.
 *
 * `published` maps scope id -> the head id someone anchored. Where a scope has no entry, the answer
 * is "unsealed", which is a real state and not a failure: unsealed is public and still open, and
 * saying so is more useful than a badge that means nothing.
 */
export function sealState(sub, published = {}) {
    const want = bare(published[sub.scopeId] || published[`sha256:${sub.scopeId}`] || "");
    if (!want) return { tier: "unsealed", sealed: false,
        says: "offen: bis zum Siegeln kann ein Schlüsselinhaber noch Einträge entfernen und den Rest neu signieren" };
    if (sub.provisional) return { tier: "provisional", sealed: false,
        says: "ein Siegel liegt vor, aber diese Kette hat eine Lücke - der erreichte Kopf ist nicht bewiesen der letzte" };
    if (want === sub.head) return { tier: "sealed", sealed: true,
        says: "der veröffentlichte Kopf stimmt: alles davor ist unveränderlich" };
    return { tier: "mismatch", sealed: false,
        says: `der veröffentlichte Kopf ist ${want.slice(0, 12)}…, erreicht wird ${sub.head.slice(0, 12)}… - diese Kopie ist nicht die versiegelte` };
}
