import { edgeTerm } from '../../core/config.js';

/**
 * The kton binding — every protocol word the compass would otherwise have to learn.
 *
 * The compass reads the graph that plktBuildGraph returns, directly. That was a deliberate call:
 * the graph already carries BOTH axes (builds-on next to about/reproduces), so reading it is not
 * the old viewer's mistake of hard-wiring lineage. What it does risk is vocabulary - an element
 * that knows the word "foton" is an element that a second domain cannot reuse.
 *
 * So the words live here, in data. Swap this file and the same compass walks a different graph.
 * That is the surviving half of the second-sketch test: the element stays ignorant, the binding
 * carries the domain.
 */

/**
 * Direction = which edge kinds count, and which END of them I am standing on.
 *
 * The claim axis is a DENY-list on purpose. The first version listed the three claim kinds it had
 * seen in two small fixtures - and against the full set that silently swallowed 200 `refines`
 * edges, plus `hash`, `controller`, `parent`, `qualifies-as`, `L0`, `L1`, `used`, `type`, `from`,
 * `submitted`. Fifteen kinds where the allow-list knew four.
 *
 * So the rule is the model's own two axes rather than a vocabulary census: derivation is
 * `builds-on`; everything that is NOT derivation is something being asserted about something, and
 * belongs on the claim axis. A kind nobody has seen yet shows up there tomorrow instead of
 * vanishing. An edge the compass cannot name is still an edge the reader must be able to walk.
 */
export const DIRECTIONS = [
    // lineage: "X builds-on Y" means Y went INTO X. Standing on X (from), Y is where it came from.
    { key: 'origin', axis: 'l', edges: ['builds-on'], me: 'from' },
    { key: 'effect', axis: 'l', edges: ['builds-on'], me: 'to' },
    // claim: everything else, read from both ends.
    { key: 'about', axis: 'c', except: ['builds-on'], me: 'to' },
    { key: 'mentions', axis: 'c', except: ['builds-on'], me: 'from' },
];

/** Node type -> the chip class compass.css already styles. Keeps the stylesheet untouched. */
const CHIP = { foton: 'cp-step', claim: 'cp-statement', source: 'cp-file',
               entity: 'cp-entity', ref: 'cp-entity', '': 'cp-file' };

export const binding = {
    directions: DIRECTIONS,

    /**
     * Hand the binding a sketch and the recovered terms, and relations stop being raw edge kinds.
     * Without this the compass still works and groups by kind - which is what a corpus with no
     * sketch deserves: its own vocabulary, unlabelled, rather than someone else's names.
     */
    configure({ config, terms, graph } = {}) {
        this._cfg = config || null; this._terms = terms || new Map(); this._graph = graph || null;
        return this;
    },

    /**
     * What to call this step's relation. Falls back to the raw kind, never to nothing: an edge the
     * sketch has no word for is still an edge the reader has to be able to see and follow.
     */
    rel(G, edge) {
        if (!this._cfg) return { id: edge.kind, label: edge.kind, known: false };
        const { term, short } = edgeTerm(G, this._terms, edge);
        const r = this._cfg.resolve(term);
        return { id: r.group, label: r.groupLabel, term, termLabel: r.label, short, known: r.known };
    },

    /** The graph hands back an ARRAY; the compass needs to look a node up by address. */
    index(graph) {
        const byId = new Map();
        for (const n of graph.nodes || []) byId.set(n.id, n);
        return byId;
    },

    /** What to call a thing. A source node carries its filename in `role`, not in `label`. */
    label: (n) => n.label || n.role || (n.id ? n.id.slice(0, 12) + '…' : '?'),

    /** What KIND of thing, in the reader's words - never the raw protocol noun if better exists. */
    typeName: (n) => ({ foton: 'Lauf', claim: 'Aussage', entity: 'Referent', ref: 'Verweis',
                        source: n.kind === 'code' ? 'Code' : 'Datei' }[n.type] || n.type || '?'),

    chip: (n) => CHIP[n.type] || 'cp-file',

    /**
     * What stands FIRM about this thing, as name/value pairs. These are attributes, not edges:
     * they do not resolve to something with its own structure, so they are not journeys.
     * `verified` is here on purpose - a reader standing on a record should see whether its
     * signature was re-checked, and see it as a fact about the record, not as decoration.
     */
    attrs(n) {
        const out = [];
        // the FULL term, not the last segment the graph shows: two different terms can end the
        // same way, and on a claim the exact term is the thing being asserted
        const t = this._terms && this._terms.get(n.id);
        if (t) { out.push({ n: 'term', v: t.term }); if (t.context) out.push({ n: 'kontext', v: t.context });
                 if (t.scope) out.push({ n: 'geltungsbereich', v: t.scope }); if (t.why) out.push({ n: 'begründung', v: t.why }); }
        const add = (name, value, by) => { if (value !== undefined && value !== null && value !== '') out.push({ n: name, v: String(value), b: by }); };
        add('art', n.type);
        add('signatur', n.type === 'source' ? '' : (n.verified ? 'nachgeprüft' : 'nicht nachgeprüft'));
        add('signierer', n.signer);
        add('beteiligter', n.participant);
        add('von', n.by);
        add('rolle', n.role);
        add('aussage', n.headline || n.text);
        if (n.repro > 1) add('reproduziert', `${n.repro} unabhängige Läufe`);
        if (n.kind) add('kind', n.kind);
        return out;
    },

    /** Every relation this graph actually contains - so a perspective naming others can be told. */
    classes(graph) {
        if (!this._cfg) return [...new Set((graph.edges || []).map((e) => e.kind))];
        return [...new Set(this._cfg.groups().map((g) => g.id))];
    },
};

export default binding;
