/**
 * The layer between "what was signed" and "what is drawn".
 *
 * The kernel builds the graph of what a corpus ATTESTS: a claim, its subject, its hash. It is
 * right to stop there - SPEC 7.1 makes meaning downstream on purpose. But a claim's object can be
 * a whole record, and a record's fields can name other records (`trainee`, `sopRef`, `areas`).
 * Those are relations that sit in the corpus and reach no graph, and no sketch can rescue them:
 * a sketch speaks about terms someone already wrote down, and the first time a corpus is opened
 * nobody has.
 *
 * So three steps, in order, each a different claim about the world:
 *
 *   surveyFields()     what the objects CONTAIN            - a measurement
 *   proposeRelations() what could be shown, and as what    - a reading, with its numbers attached
 *   deriveEdges()      the edges themselves                - marked `derived`, never mixed in
 *
 * All three run off ONE scan (`scanObjects`), so the survey cannot count what the derivation would
 * not draw. Two passes over the same data that disagree is how a report stops being evidence.
 *
 * The last step is why the file is careful. `G.edges` is what somebody signed. A derived edge is
 * what somebody READ. They must not end up in the same array, or an interpretation acquires the
 * authority of a signature - which in a provenance system is the one mistake that matters.
 */

const ID_LIKE = /^[A-Za-z][A-Za-z0-9_.+-]*:[^\s]+$/;
/** Graph node ids are the first 32 hex of a content hash - the kernel's own reference form. */
const hashId = (h) => String(h || "").replace(/^sha256:/, "").toLowerCase().slice(0, 32);
const localPart = (name) => { const i = Math.max(name.lastIndexOf(":"), name.lastIndexOf("/")); return i < 0 ? name : name.slice(i + 1); };
const short = (name) => (/^sha256:/.test(name) ? name.slice(0, 20) + "..." : name);

const valueKind = (x) => (typeof x === "number" ? "number"
    : typeof x === "boolean" ? "bool"
    : typeof x !== "string" ? "object"
    : /^\d{4}-\d{2}-\d{2}/.test(x) ? "date" : "text");

/**
 * One pass over every claim object, yielding one row per VALUE.
 *
 * Two reference forms, because two corpora write them differently and both are right:
 *   - a content hash (`{hash:"sha256:..."}`), which IS a node id - the kernel's form;
 *   - a name (`"qms:SOP-16"`), resolved against what the graph already knows by name.
 *
 * A value that is name-shaped and resolves to nothing is not noise, it is the edge of the corpus:
 * the reference that dangles in one source is the edge that appears when the next is added. It is
 * yielded with `outside: true` rather than dropped.
 */
function* scanObjects(G, terms) {
    // What a value could be naming. Entity nodes carry the ids the kernel already materialised, so
    // a name resolves against the GRAPH's own index of named things rather than against a guess.
    const byName = new Map();
    const learn = (name, id) => { if (typeof name === "string" && ID_LIKE.test(name) && !byName.has(name)) byName.set(name, id); };
    for (const n of G.nodes) { learn(n.uri, n.id); learn(n.role, n.id); learn(n.label, n.id); }

    for (const [claimId, t] of terms) {
        const body = t.body;
        if (!body) continue;
        const ctx = t.jsonld;
        // Where a derived edge should LEAVE from, in order:
        //   the record's own node - a relation between two records is not a relation between two
        //   assertions about them; then the claim itself, but only IF the kernel made it a node
        //   (in one fixture it did not, and the fallback pointed at an id that is in no graph);
        //   then what the claim is about. If none of the three exists there is nothing to hang an
        //   edge on, and the row says so rather than inventing an endpoint.
        const aboutTarget = ((G.out && G.out[claimId]) || []).find((e) => e.kind === "about");
        const subject = (typeof body.id === "string" && byName.get(body.id))
            || (G.byId.has(claimId) ? claimId : null)
            || (aboutTarget && aboutTarget.to)
            || null;
        // What this claim already reaches. A field the kernel drew is not news.
        const drawn = new Set(((G.out && G.out[claimId]) || []).filter((e) => e.kind !== "about").map((e) => e.to));

        for (const [field, value] of Object.entries(body)) {
            if (field === "@context") continue;
            const decl = ctx && ctx[field] && typeof ctx[field] === "object" ? ctx[field] : null;
            const shared = {
                claimId, subject, unanchored: !subject, field,
                term: (decl && decl["@id"]) || "",
                declared: !!(decl && decl["@type"] === "@id"),
                container: (decl && decl["@container"]) || "",
            };

            for (const x of (Array.isArray(value) ? value : [value])) {
                const hash = (x && typeof x === "object" && typeof x.hash === "string") ? x.hash
                           : (typeof x === "string" && /^sha256:/.test(x)) ? x : null;
                if (hash) {
                    const target = hashId(hash);
                    yield G.byId.has(target)
                        ? { ...shared, target, name: hash, projected: drawn.has(target) }
                        : { ...shared, outside: true, name: hash };
                    continue;
                }
                const name = (x && typeof x === "object" && typeof x.uri === "string") ? x.uri
                           : (typeof x === "string") ? x : null;
                if (name && byName.has(name)) {
                    const target = byName.get(name);
                    yield { ...shared, target, name, projected: drawn.has(target) };
                } else if (name && ID_LIKE.test(name)) {
                    yield { ...shared, outside: true, name };
                } else {
                    yield { ...shared, kind: valueKind(x) };
                }
            }
        }
    }
}

/**
 * What the claim OBJECTS hold, erhoben rather than declared.
 *
 * A sketch says what a corpus MEANS, and can only say it about terms someone already wrote down.
 * This says what a corpus CONTAINS, and needs nobody. It is a REPORT, like `survey().unknown`:
 * nothing here becomes an edge, and nothing here is signed.
 */
export function surveyFields(G, terms) {
    // Who counts as a person is not a vocabulary question: this corpus already names its
    // participants, and a target whose local part is one of them IS one. No `foaf:` list needed.
    const people = new Set((G.participants || []).filter(Boolean));

    const fields = new Map();
    const slot = (f) => {
        if (!fields.has(f)) fields.set(f, { field: f, n: 0, values: 0, id: false, term: "", container: "",
                                            resolves: 0, projected: 0, outside: 0, persons: 0,
                                            targets: new Map(), seen: new Map(), kinds: new Set(), sample: [] });
        return fields.get(f);
    };
    const remember = (f, v) => { if (f.sample.length < 2 && !f.sample.includes(v)) f.sample.push(v); };

    let last = null;
    for (const row of scanObjects(G, terms)) {
        const f = slot(row.field);
        // one object counts once for the field, however many values it put in it
        const here = row.claimId + " " + row.field;
        if (here !== last) { f.n++; last = here; }
        f.values++;
        if (row.declared) f.id = true;
        if (!f.term && row.term) f.term = row.term;
        if (!f.container && row.container) f.container = row.container;

        if (row.target) {
            f.resolves++;
            if (row.projected) f.projected++;
            const ty = (G.byId.get(row.target) || {}).type || "?";
            f.targets.set(ty, (f.targets.get(ty) || 0) + 1);
            f.seen.set(row.target, (f.seen.get(row.target) || 0) + 1);
            if (people.has(localPart(row.name))) f.persons++;
            remember(f, short(row.name));
        } else if (row.outside) {
            f.outside++;
            remember(f, short(row.name));
        } else {
            f.kinds.add(row.kind);
        }
    }

    const isRef = (f) => f.id || f.resolves > 0 || f.outside > 0;
    return [...fields.values()]
        .map((f) => ({
            field: f.field, n: f.n, values: f.values,
            ...(f.id ? { id: true } : {}),
            ...(f.term ? { term: f.term } : {}),
            ...(f.container ? { container: f.container } : {}),
            ...(isRef(f) ? { resolves: f.resolves, projected: f.projected, outside: f.outside } : {}),
            // how the references SPREAD: one thing to one thing, or hundreds onto two
            ...(f.seen.size ? { distinct: f.seen.size, top: Math.max(...f.seen.values()) } : {}),
            ...(f.persons ? { persons: f.persons } : {}),
            ...(f.targets.size ? { targets: Object.fromEntries([...f.targets].sort((a, b) => b[1] - a[1])) } : {}),
            ...(f.kinds.size ? { kind: [...f.kinds].sort().join("|") } : {}),
            ...(f.sample.length ? { sample: f.sample } : {}),
        }))
        // references first, and among them the ones that reach something. The head of the list is
        // what a first perspective would actually be made of.
        .sort((a, b) => (Number(!!b.resolves || !!b.id) - Number(!!a.resolves || !!a.id))
                     || ((b.resolves || 0) - (a.resolves || 0))
                     || (b.values - a.values));
}

/**
 * From what a corpus HOLDS to what could be SHOWN - and as what.
 *
 * Two things happen here that the survey deliberately does not do.
 *
 * First, MERGE BY TERM. The survey keys on the field name, because that is what the object wrote.
 * But two fields can carry the same `@id` term - `sopRef` and `governingSop` both say
 * `qmso:sopRef` - and offering them as two relations splits one thing in half. The term is the
 * identity, the field names are how it was spelled.
 *
 * Second, CLASSIFY. "Draw the references" is the wrong default: in one register 1033 references
 * resolve, and drawing them all is the bar-of-nodes again. How a reference should read is decided
 * by how it SPREADS, and that is measurable:
 *
 *   people          -> a facet. Who did it is a filter, not a picture: one field put 250 lines
 *                      onto two names, which is an attribute wearing a star costume.
 *   fan > 1.5       -> a region. A record that belongs to several things is membership, and
 *                      membership drawn as lines is the thing that made the picture unreadable.
 *   <3 per target   -> an edge. One thing to one thing is what a line is for.
 *   otherwise       -> a grouping. Many onto few, each onto one: a gathering point, not a stroke.
 *
 * The thresholds are a starting point, not a truth, so every proposal carries the numbers that
 * produced it. A reader who disagrees can see exactly what with.
 */
const FAN_IS_MEMBERSHIP = 1.5;
const PER_TARGET_IS_EDGE = 3;
/** A field by which an object names ITSELF is not a relation to something else. */
export const SELF_NAMING = new Set(["id", "@id", "name", "hash", "uri"]);

export function proposeRelations(fields) {
    const merged = new Map();
    for (const f of fields) {
        if (SELF_NAMING.has(f.field)) continue;
        if (!(f.resolves > 0) || f.projected !== 0) continue;   // nothing there, or already drawn
        const key = f.term || f.field;
        if (!merged.has(key)) merged.set(key, { relation: key, term: f.term || "", fields: [], declared: false,
                                                sources: 0, values: 0, edges: 0, outside: 0, distinct: 0,
                                                top: 0, persons: 0, targets: {} });
        const m = merged.get(key);
        m.fields.push(f.field);
        m.declared = m.declared || !!f.id;
        m.sources += f.n; m.values += f.values;
        m.edges += f.resolves; m.outside += f.outside || 0;
        m.distinct += f.distinct || 0; m.top = Math.max(m.top, f.top || 0);
        m.persons += f.persons || 0;
        for (const [t, n] of Object.entries(f.targets || {})) m.targets[t] = (m.targets[t] || 0) + n;
    }

    return [...merged.values()].map((m) => {
        const fan = m.sources ? m.values / m.sources : 0;
        const perTarget = m.distinct ? m.edges / m.distinct : 0;
        const as = m.persons * 2 > m.edges ? "facet"
                 : fan > FAN_IS_MEMBERSHIP ? "region"
                 : perTarget < PER_TARGET_IS_EDGE ? "edge"
                 : "group";
        return {
            relation: m.relation,
            ...(m.term ? { term: m.term } : {}),
            fields: m.fields,
            declared: m.declared,
            as,
            edges: m.edges, outside: m.outside,
            distinct: m.distinct, top: m.top,
            fan: Math.round(fan * 10) / 10,
            perTarget: Math.round(perTarget * 10) / 10,
            ...(m.persons ? { persons: m.persons } : {}),
            into: m.targets,
            why: as === "facet"  ? `${m.edges} Verweise auf ${m.distinct} Personen, haeufigste ${m.top}x - wer, nicht was`
               : as === "region" ? `${fan.toFixed(1)} Ziele je Record - Zugehoerigkeit, keine Verbindung`
               : as === "edge"   ? `${perTarget.toFixed(1)} Verweise je Ziel - eines auf eines`
               :                   `${m.edges} auf ${m.distinct} Ziele, je Record eines - ein Sammelpunkt`,
        };
    }).sort((a, b) => b.edges - a.edges);
}

/**
 * The edges themselves - and NOT in `G.edges`.
 *
 * Every one carries `derived: true` and the reading it came from, so a viewer can draw an edge, a
 * region, a facet or a gathering from the same row, and a reader can always ask which of the two
 * layers a line came from. Nothing here is filtered by `as`: choosing what to do with a relation
 * is the perspective's job, not the derivation's, and a derivation that quietly dropped the facets
 * would make the two layers disagree about how much is there.
 *
 * `from` is the record's own node where the kernel made one, and the claim only where it did not.
 * A relation between two records is not a relation between two assertions about them.
 */
export function deriveEdges(G, terms, relations) {
    const by = new Map();          // field -> the proposal that governs it
    for (const r of relations) for (const f of r.fields) by.set(f, r);

    // One edge per (from, to, relation) - but the claims that assert it are KEPT, not discarded.
    // A record attested twice says its relations twice; that is two people standing behind the same
    // reading, which is exactly the kind of thing this system exists to be able to answer. The
    // count also explains why there are fewer edges than references, instead of leaving a gap.
    const edges = new Map();
    let unanchored = 0;
    for (const row of scanObjects(G, terms)) {
        if (!row.target || row.projected) continue;
        // A reference the survey counted but that has no node to leave from. Counted there,
        // undrawable here: an edge with one end is not an edge.
        if (row.unanchored) { unanchored++; continue; }
        const r = by.get(row.field);
        if (!r) continue;          // self-naming, or a field nobody proposed
        const key = `${row.subject} ${row.target} ${r.relation}`;
        const hit = edges.get(key);
        if (hit) { if (!hit.claims.includes(row.claimId)) hit.claims.push(row.claimId); continue; }
        edges.set(key, { from: row.subject, to: row.target, kind: r.relation, as: r.as,
                         field: row.field, claims: [row.claimId], derived: true });
    }
    const out = [...edges.values()];
    out.unanchored = unanchored;   // reported, not hidden: the check adds it back for conservation
    return out;
}

/**
 * Hang a derived layer on a graph WITHOUT touching the attested one.
 *
 * Separate arrays and separate indexes, so every existing walk - `ask`, the compass directions,
 * every grouping - keeps seeing exactly what it saw before. Reading the second layer has to be
 * asked for, which is the point: it is a reading.
 */
export function withDerived(G, edges) {
    G.derived = edges;
    G.outDerived = {}; G.inDerived = {};
    for (const e of edges) { (G.outDerived[e.from] ??= []).push(e); (G.inDerived[e.to] ??= []).push(e); }
    return G;
}

/**
 * The drawable view: what a reader should see, from what the corpus attests.
 *
 * Three rules, all of them the same idea - a node earns its place by being a THING, not by being
 * the bookkeeping that connects things:
 *
 *   1. A claim with a subject AND an object is a RELATION. It becomes one named edge between them
 *      and stops being a box in the middle.
 *   2. A claim with only a subject is an ASSERTION ABOUT that node. It becomes a mark on it. It is
 *      not dropped - a mark carries its term, who said it and when, so the node can say what stands
 *      about it without spending a box on each.
 *   3. A file is only a node when it CONNECTS two kept nodes. A file that hangs off one step is
 *      that step's detail, and drawing it turns every step into a little star.
 *
 * Nothing here is a filter: no edge is lost. A contracted view has the same reachability as the
 * attested one - it just spends its boxes differently. `G.edges` is untouched, this returns a
 * separate view, and both travel so a reader can switch.
 */
export function contract(G, terms, opts = {}) {
    const isKept = (n) => (opts.keep || ["foton"]).includes(n.type);
    const out = (id) => (G.out && G.out[id]) || [];
    const kept = new Set(G.nodes.filter(isKept).map((n) => n.id));

    const edges = [];
    const marks = {};
    const addMark = (id, m) => { (marks[id] ??= []).push(m); };

    // rule 1 + 2: every claim is either a relation or a mark
    let asEdge = 0, asMark = 0, orphan = 0;
    for (const n of G.nodes) {
        if (n.type !== "claim") continue;
        const es = out(n.id);
        const subject = es.find((e) => e.kind === "about");
        const objects = es.filter((e) => e.kind !== "about" && kept.has(e.to));
        const t = terms.get(n.id) || {};
        const term = t.short || t.term || n.label || "";
        if (!subject || !kept.has(subject.to)) { orphan++; continue; }
        if (objects.length) {
            for (const o of objects) {
                edges.push({ from: subject.to, to: o.to, kind: term, claim: n.id,
                             by: t.by || n.participant || "", contracted: true });
                asEdge++;
            }
        } else {
            addMark(subject.to, { term, claim: n.id, by: t.by || n.participant || "",
                                  when: t.when || "", why: t.why || "",
                                  // what the claim SAID: a scalar value, or the record body for a
                                  // claim whose object is an object. A mark that carries only its
                                  // term says "something stands here" and not what.
                                  object: t.object, body: t.body });
            asMark++;
        }
    }

    // rule 3: a file survives only if it joins two kept nodes
    const bridges = new Set();
    for (const n of G.nodes) {
        if (isKept(n) || n.type === "claim") continue;
        const near = new Set();
        for (const e of out(n.id)) if (kept.has(e.to)) near.add(e.to);
        for (const e of ((G.in && G.in[n.id]) || [])) if (kept.has(e.from)) near.add(e.from);
        if (near.size > 1) bridges.add(n.id);
    }
    const visible = new Set([...kept, ...bridges]);

    // the attested edges that survive: both ends still on the canvas
    for (const e of G.edges) {
        if (visible.has(e.from) && visible.has(e.to)) edges.push({ ...e, contracted: false });
    }

    // What a node should be CALLED, and what stands out about it.
    //
    // A foton's label is its command, which is right for a machine and useless for a reader: four
    // refinements that all run model.R are four identical boxes. The claims know better - they name
    // their subject - and a claim that says `base` or `final` says which of them a reader should see
    // first. Both are already in the corpus; nothing here is invented.
    const names = {}, roles = {};
    for (const [, t] of terms) {
        for (const sub of (t.subject || [])) {
            if (!sub || !sub.name || !sub.hash) continue;
            const id = String(sub.hash).replace(/^sha256:/, "").toLowerCase().slice(0, 32);
            if (visible.has(id) && !names[id]) names[id] = sub.name;
        }
    }
    // From EVERY claim, not only the ones that stayed marks. A claim can be both a relation and an
    // assertion - `model-role` names a parent AND says `final` - and turning it into an edge must
    // not swallow what it said about its subject. Two of three roles went missing exactly that way.
    for (const n of G.nodes) {
        if (n.type !== "claim") continue;
        const subject = out(n.id).find((e) => e.kind === "about");
        if (!subject || !visible.has(subject.to)) continue;
        const t = terms.get(n.id) || {};
        const b = t.body || t.object;
        if (!b || typeof b !== "object") continue;
        const id = subject.to;
        if (b.role) roles[id] = b.role;
        if (b.key_step) roles[id] = roles[id] ? roles[id] + "+key" : "key";
    }

    return { nodes: [...visible], edges, marks, names, roles,
             stats: { kept: kept.size, bridges: bridges.size, asEdge, asMark, orphan,
                      named: Object.keys(names).length, roled: Object.keys(roles).length,
                      hidden: G.nodes.length - visible.size } };
}
