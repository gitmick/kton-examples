/**
 * The layer the protocol deliberately left empty.
 *
 * SPEC §7.1: a kernel "MUST treat [predicates] as opaque identifiers … MUST NOT require a known
 * vocabulary, validate term membership, or perform inference. **Meaning resolves downstream.**"
 * Downstream is here. A viewer that hard-codes relation names is not being pragmatic, it is doing
 * a job the kernel refused on purpose - and getting it wrong for every corpus but one.
 *
 * So grouping, filtering and perspectives arrive as CONFIGURATION. Three rules make it survive
 * contact with a corpus nobody has seen:
 *
 *   1. Key on the FULL term. The graph names a relation by its last segment, which is right for
 *      reading and wrong for identity - two different terms ending the same way merge silently.
 *   2. An unknown term is SHOWN, never dropped. §7.1 makes the set open by construction, so any
 *      allow-list is wrong in advance. Unknowns land in their own group, labelled with what the
 *      corpus called them, so opening a foreign corpus tells you what the config does not know yet.
 *   3. Structural edges are terms too. `builds-on` and `reproduces` come from the kernel, not from
 *      a claim; giving them `kton:edge/...` terms keeps ONE keyspace instead of two rules.
 */

import { shortTerm } from "./terms.js";

export const UNASSIGNED = "unassigned";
const STRUCTURAL = "kton:edge/";

/** Structural edges carry no claim; the kernel derived them. Give them a term anyway. */
export const structuralTerm = (kind) => STRUCTURAL + kind;

/**
 * The full term behind an edge.
 * A claim-derived edge always has its claim as `from` (measured across every fixture: about,
 * controller, reproducedBy, refines, L0, L1 - all of them). Anything else the kernel derived.
 */
export function edgeTerm(G, terms, edge) {
    const from = G.byId.get(edge.from);
    if (from && from.type === "claim") {
        const t = terms.get(edge.from);
        if (t) return { term: t.term, short: t.short, claim: from, structural: false };
    }
    return { term: structuralTerm(edge.kind), short: edge.kind, claim: null, structural: true };
}

export function makeConfig(spec) {
    const groups = new Map((spec.groups || []).map((g) => [g.id, g]));
    if (!groups.has(UNASSIGNED)) {
        groups.set(UNASSIGNED, { id: UNASSIGNED, label: spec.unassignedLabel || "nicht zugeordnet", axis: "c" });
    }
    const exact = new Map(Object.entries(spec.terms || {}));
    const rules = spec.match || [];

    /** term -> {group, label, axis, known}. Exact first, then rules, then honest ignorance. */
    function resolve(term) {
        const hit = exact.get(term);
        if (hit) return finish(term, hit, true);
        for (const r of rules) {
            if (r.term === term) return finish(term, r, true);
            if (r.prefix && term.startsWith(r.prefix)) return finish(term, r, true);
            if (r.suffix && shortTerm(term) === r.suffix) return finish(term, r, true);
        }
        return finish(term, { group: UNASSIGNED }, false);
    }
    function finish(term, hit, known) {
        const g = groups.get(hit.group) || groups.get(UNASSIGNED);
        return { term, group: g.id, groupLabel: g.label, axis: hit.axis || g.axis || "c",
                 label: hit.label || shortTerm(term), known };
    }

    const perspectives = spec.perspectives || { full: { label: "alles" } };

    return {
        spec,
        groups: () => [...groups.values()],
        group: (id) => groups.get(id),
        facets: () => spec.facets || ["participant", "context", "verified", "signer"],
        perspectives: () => Object.entries(perspectives).map(([id, p]) => ({ id, label: p.label || id, ...p })),
        perspective: (id) => perspectives[id] || perspectives.full || {},
        resolve,

        /** Resolve every edge once. Returns {byEdge, groupCounts, unknown} - unknown is a REPORT,
         *  not an error: it is what this config does not yet say about this corpus. */
        survey(G, terms) {
            const byEdge = new Map(), groupCounts = new Map(), unknown = new Map();
            for (const e of G.edges) {
                const { term, short, structural } = edgeTerm(G, terms, e);
                const r = resolve(term);
                byEdge.set(e, { ...r, short, structural });
                groupCounts.set(r.group, (groupCounts.get(r.group) || 0) + 1);
                if (!r.known) unknown.set(term, (unknown.get(term) || 0) + 1);
            }
            return { byEdge, groupCounts, unknown };
        },

        /** Does this perspective show that group? Vocabulary level - the mask. */
        showsGroup(perspectiveId, groupId) {
            const p = this.perspective(perspectiveId);
            if (p.only && p.only.length) return p.only.includes(groupId);
            if (p.hide && p.hide.length) return !p.hide.includes(groupId);
            return true;
        },
    };
}

export async function loadConfig(url) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`config: cannot fetch ${url} (HTTP ${r.status})`);
    return makeConfig(await r.json());
}
