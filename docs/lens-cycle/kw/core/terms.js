/**
 * The full predicate terms, recovered from the union.
 *
 * The graph a viewer gets back names a claim's relation by its LAST SEGMENT: `lastSeg()` in the
 * kernel turns `http://www.w3.org/ns/dcat#downloadURL` into `downloadURL`. That is right for
 * display and right for merging the same term written two ways - `dcat:downloadURL` and its
 * expanded form are one relation and should read as one.
 *
 * It is not an identity, though. Two genuinely different terms that end in the same segment merge
 * into one relation and nothing says so. The kernel is foreign code and this is its display
 * choice, so the fix belongs here: key configuration on the FULL term, show the short one.
 *
 * The union is already in hand - every viewer fetches it to build the graph - so this costs one
 * more parse, not another request.
 */

/** Node ids in the graph are the first 32 hex of the content hash. */
const nodeId = (id) => String(id || "").replace(/^sha256:/, "").toLowerCase().slice(0, 32);

const termOf = (t) => (typeof t === "string" ? t : (t && (t.uri || t.hash)) || "");

/** Last path or fragment segment, mirroring the kernel's lastSeg so labels agree with the graph. */
export function shortTerm(term) {
    for (let i = term.length - 1; i >= 0; i--) if (term[i] === "/" || term[i] === "#") return term.slice(i + 1);
    const c = term.lastIndexOf(":");
    return c >= 0 ? term.slice(c + 1) : term;
}

/**
 * Read a union and return what each claim really said.
 * Map: node id -> {term, short, context, by, when, why, object, datatype}
 */
export function termsFromUnion(unionText) {
    const out = new Map();
    let recs;
    try { recs = JSON.parse(unionText); } catch { return out; }
    if (!Array.isArray(recs)) return out;

    for (const r of recs) {
        if (!r || !r.claimId || !r.envelope || !r.envelope.payload) continue;
        let st;
        try { st = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(r.envelope.payload), (c) => c.charCodeAt(0)))); } catch { continue; }   // UTF-8, not Latin-1
        const body = st.predicate || {};

        // Scope statements are not claims and carry no predicate term: SPEC §7.4 is the ONE
        // structural grammar the kernel mandates - identity, order, boundary, nesting - and it says
        // nothing about meaning. The kernel renders them as claim nodes with an empty role, which
        // makes the only mandated grammar the one thing a viewer cannot see. Give them terms.
        if (st.predicateType === "https://kton.dev/scope/v0") {
            out.set(nodeId(r.claimId), {
                term: body.genesis ? "https://kton.dev/scope/v0#seed" : "https://kton.dev/scope/v0",
                short: body.genesis ? "seed" : "scope",
                context: "", by: body.by || "", when: body.when || "", why: "",
                scope: body.scope || "", parent: body.parent || null,
            });
            continue;
        }

        const term = termOf(body.predicate);
        if (!term) continue;
        const obj = body.object;
        out.set(nodeId(r.claimId), {
            term,
            short: shortTerm(term),
            context: termOf(body.context) || "",
            by: body.by || "",
            when: body.when || "",
            why: body.why || "",
            object: (obj && typeof obj === "object" && !(obj.hash || obj.uri)) ? obj.value : undefined,
            datatype: (obj && typeof obj === "object" && obj.datatype) ? termOf(obj.datatype) : "",
            // The object's own BODY, kept rather than dropped.
            //
            // In one corpus an object is a scalar - `{value, datatype}` - and `object` above is the
            // whole of it. In another it is the record itself, with fields that name other records
            // (`trainee`, `sopRef`, `areas`). Those are relations that sit in the corpus and reach
            // no graph, because the kernel projects `predicate` to an edge kind and the object to
            // its hash. Dropping the body here is what made them invisible.
            //
            // This costs no request and no second parse - the payload is already decoded - so the
            // survey downstream can report what a corpus holds instead of only what a sketch knows.
            body: (obj && typeof obj === "object" && obj.value === undefined && !obj.uri) ? obj : undefined,
            // WHAT the claim is about, as the claim itself named it. The graph resolves a subject to
            // a node by hash and keeps the hash; the NAME the claimant used is dropped, and that is
            // the only human name many nodes have - a foton is labelled by its command, so four
            // steps that run the same script are four identical labels.
            subject: Array.isArray(st.subject) ? st.subject.map((x) => ({
                name: x && x.name, hash: (x && x.digest && x.digest.sha256) || undefined })) : undefined,
            // A JSON-LD object says WHICH of its own fields are references (`@type: "@id"`). That is
            // the corpus declaring its edges, so a foreign one needs no sketch to be read - only to
            // be named.
            jsonld: (obj && obj["@context"] && typeof obj["@context"] === "object") ? obj["@context"] : undefined,
        });
    }
    return out;
}

/** Node.js has no atob in older versions and the browser has no Buffer; cover both. */
function atob(b64) {
    if (typeof globalThis.atob === "function") return globalThis.atob(b64);
    return globalThis.Buffer.from(b64, "base64").toString("binary");
}
