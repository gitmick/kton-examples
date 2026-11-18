/**
 * The compass — four directions, at every node, whatever the node is.
 *
 * It takes a graph and a binding, draws where you are and every way out, and reports what the
 * reader wants. It performs nothing: no fetch, no protocol, no action. Which actions exist at a
 * node is the host's business, handed in as `actions(node)`.
 *
 * The reason for that line: the viewer this replaces had the lineage axis BUILT IN. It could do
 * origin and effect because that was the structure it was written against, and when the corpus
 * carried more assertions than transformations there was nothing to configure - only to replace.
 *
 * This one reads the protocol's own graph shape, but it never learns the protocol's words. Which
 * edge kinds make a direction, what a node is called, what counts as an attribute - all of that
 * arrives in `binding` (see binding-kton.js). Swap the binding, walk a different domain.
 *
 *   const compass = mountCompass(el, { graph, binding, onIntent, actions });
 *   compass.goTo(address);
 *
 * Intents: navigate · act · reveal · mask.
 */

const DEFAULT_LABELS = {
    origin: ['Herkunft', 'woraus es entstanden ist'],
    effect: ['Wirkung', 'was daraus entstanden ist'],
    about: ['Aussagen', 'was darüber gesagt wird'],
    mentions: ['Erwähnt', 'worauf es sich bezieht'],
    empty: 'Von hier führt in dieser Richtung nichts weg — unter dieser Perspektive.',
    scoped: 'ausserhalb des Geltungsbereichs',
    reveal: 'einblenden',
    restore: 'Geltungsbereich wieder anwenden',
    attrs: 'Was darüber feststeht',
    trail: 'Weg',
    onestep: 'ein Schritt',
    depth: 'Tiefe',
    depthHint: 'weiter verfolgen — aus einem Schritt wird ein Kegel',
    rows: 'Zeilen',
    distinct: 'verschieden',
    upto: 'bis Tiefe',
    again: 'schon gesehen',
    cycle: 'führt auf sich selbst zurück',
    capped: 'gekappt bei',
    of: 'von',
    andMore: 'und weitere',
    flattened: 'gruppiert - der Kegel ist dafür flachgelegt',
};

import { indexGraph, cone } from '../../core/nav.js';
import { groupList } from '../../core/grouping.js';

export function mountCompass(root, opts) {
    const { graph, binding, onIntent = () => {}, actions = () => [], labels = {} } = opts;
    const L = { ...DEFAULT_LABELS, ...labels };
    const DIRECTIONS = binding.directions;
    const perspectives = opts.perspectives || {};

    /* The SAME index the graph viewer walks (core/nav.js). The compass built its own adjacency,
       which was a second copy of a two-line thing - and worse, it kept it in Maps where the shared
       walks index plain objects, so a cone computed over there could not have run here at all.
       Self-loops are dropped at read time, not at index time: they are no journey, but the index is
       shared and must stay exactly what the graph viewer was proven against. */
    const G = indexGraph(graph);
    const byId = G.byId;
    const notSelf = (e) => e.from !== e.to;

    const state = { at: null, perspective: opts.perspective || 'full', trail: [], relFilter: {}, reveal: {},
                    facets: opts.facets || {}, depth: opts.depth || {},
                    // a FUNCTION, not a vocabulary: the element must not learn what "by participant"
                    // means any more than it learns what a foton is. The host builds the key from
                    // its sketch and hands it in.
                    groupKey: opts.groupKey || null, groupLabel: opts.groupLabel || '',
                    collapsed: {} };

    const node = (a) => byId.get(a) || { id: a, type: '', label: a };
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const persp = () => perspectives[state.perspective] || {};
    const other = (dir) => (dir.me === 'from' ? 'to' : 'from');
    const rel = (e) => (binding.rel ? binding.rel(G, e) : { id: e.kind, label: e.kind });
    /** A direction names either the kinds it takes or the ones it refuses; refusing is what keeps
     *  an unseen kind visible instead of silently dropped (see binding-kton.js). */
    const takesKind = (dir, k) => (dir.edges ? dir.edges.includes(k) : !(dir.except || []).includes(k));

    /** The mask: which KINDS of edge are in view. Vocabulary level. */
    function visible(rel) {
        const p = persp();
        const hit = (pat) => rel === pat || rel.startsWith(pat + ' ') || rel.split('.')[0] === pat;
        if (p.only && p.only.length) return p.only.some(hit);
        if (p.hide && p.hide.length) return !p.hide.some(hit);
        return true;
    }

    /**
     * The scope: which INSTANCES are in play. State level - a different thing from the mask,
     * deliberately.
     *
     * Two sources compose here and neither overrides the other: the perspective's declared scope,
     * and the facets chosen at runtime (by the reader, or by a host steering this view). They are
     * the same mechanism at different moments, so a facet is not a new concept to learn - it is a
     * scope someone picked later. Both must allow a node for it to be offered unasked.
     */
    function outOfScope(addr) {
        const sc = persp().scope;
        const fc = state.facets;
        const hasFacets = fc && Object.keys(fc).some((k) => fc[k] && fc[k].length);
        if (!sc && !hasFacets) return null;
        for (const a of binding.attrs(node(addr))) {
            const declared = sc && sc[a.n];
            if (declared && !declared.includes(a.v)) return `${a.n}=${a.v}`;
            const chosen = fc && fc[a.n];
            if (chosen && chosen.length && !chosen.includes(a.v)) return `${a.n}=${a.v}`;
        }
        return null;
    }

    /**
     * A scope orders what is OFFERED unasked and never blocks an explicit move: following an edge
     * means the reader asked for that thing. And nothing goes silently - what it removes is counted
     * and revealable, because "there is no predecessor" and "the predecessor is out of scope" are
     * opposite findings.
     */
    function stepsFor(dir) {
        const side = dir.me === 'from' ? G.out : G.in;
        // the mask reads the RELATION the sketch resolved, not the raw kind - that is what makes a
        // perspective say "Freigaben" instead of listing four spellings of reviewedBy
        const all = (side[state.at] || []).filter((e) => notSelf(e) && takesKind(dir, e.kind) && visible(rel(e).id));
        all.sort((x, y) => (rel(x).id === rel(y).id
            ? binding.label(node(x[other(dir)])).localeCompare(binding.label(node(y[other(dir)])))
            : rel(x).id.localeCompare(rel(y).id)));
        const shown = [], hidden = new Map();
        for (const e of all) {
            const why = state.reveal[dir.key] ? null : outOfScope(e[other(dir)]);
            if (why) hidden.set(why, (hidden.get(why) || 0) + 1);
            else shown.push(e);
        }
        return { steps: shown, hidden: [...hidden].map(([reason, count]) => ({ reason, count })) };
    }

    /** Classes a perspective names that this graph does not have. Said out loud, always. */
    function unknownClasses() {
        const p = persp();
        const have = new Set(binding.classes(graph));
        return [...(p.only || []), ...(p.hide || []), ...Object.keys(p.scope || {})].filter((n) => !have.has(n));
    }

    function render() {
        const n = node(state.at);
        const unknown = unknownClasses();
        const attrs = binding.attrs(n).filter((a) => visible(a.n));
        const acts = actions(state.at, n) || [];

        root.innerHTML = `
        ${unknown.length ? `<p class="cp-warn"><b>Achtung:</b> die Perspektive nennt Klassen, die dieser
            Graph nicht führt — ${esc(unknown.join(', '))}. Ein leeres Feld heißt hier falsches
            Vokabular, nicht „nichts gefunden".</p>` : ''}
        <section class="cp-station">
          <div class="cp-kindrow">
            <span class="cp-chip ${esc(binding.chip(n))}">${esc(binding.typeName(n))}</span>
            ${acts.map((a) => `<button class="cp-act" data-act="${esc(a.id)}"
                ${a.hint ? `title="${esc(a.hint)}"` : ''}>${esc(a.label)}</button>`).join('')}
          </div>
          <h1 class="cp-label">${esc(binding.label(n))}</h1>
          <div class="cp-addr">${esc(state.at)}</div>
          ${attrs.length ? `<div class="cp-attrs"><h2>${esc(L.attrs)}</h2><div class="cp-grid">
            ${attrs.map((a) => `<dl class="cp-attr"><dt>${esc(a.n)}</dt><dd>${esc(a.v)}
              ${a.b ? `<span class="cp-who"> · ${esc(a.b)}</span>` : ''}</dd></dl>`).join('')}</div></div>` : ''}
        </section>
        <section class="cp-compass">${DIRECTIONS.map((d) => renderDirection(d)).join('')}</section>
        <nav class="cp-trail"><span class="cp-lab">${esc(L.trail)}</span>${state.trail.map((a, i) =>
            `${i ? '<span class="cp-sep">›</span>' : ''}<button class="cp-step" data-jump="${i}"
              aria-current="${i === state.trail.length - 1}">${esc(binding.label(node(a)))}</button>`).join('')}</nav>`;
    }

    /**
     * The cone: the same direction, followed further.
     *
     * It is NOT a second traversal - core/nav.js does the walking, the compass only decides how to
     * show it. A provenance cone is a DAG, so a shared input reappears under every consumer: a
     * repeat is marked and not expanded again, and `distinct` says how many things are really
     * there. "37 Zeilen, 12 verschieden" is the honest sentence; 37 rows alone would read as 37
     * files.
     *
     * Scope behaves differently here than at one step, deliberately. At depth 1 an out-of-scope
     * node is withheld and counted, because withholding it costs the reader nothing. Inside a cone
     * it is marked instead: dropping a node in the middle would silently sever everything below it,
     * and a path that quietly loses its middle is worse than one that shows a greyed-out stone.
     */
    function coneFor(d) {
        const depth = state.depth[d.key] || 1;
        const navDir = d.me === 'from' ? 'up' : 'down';
        const c = cone(G, state.at, navDir, {
            kind: (e) => notSelf(e) && takesKind(d, e.kind) && visible(rel(e).id),
            depth, budget: 400,
        });
        const rows = c.rows.map((r) => ({ ...r, scoped: outOfScope(r.id) }));
        return { ...c, rows };
    }

    function renderCone(d) {
        const c = coneFor(d);
        // Grouping a TREE destroys the tree, so the honest move is to flatten it and say so rather
        // than to draw headers over an indentation that no longer means anything.
        if (state.groupKey) {
            const groups = groupList(c.rows.slice(0, 400), (r) => state.groupKey(node(r.id)));
            return `<div class="cp-conehead">${c.rows.length} ${esc(L.rows)} · <b>${c.distinct}</b> ${esc(L.distinct)}
                · ${esc(L.flattened)}</div>` +
              `<div class="cp-groups">${groups.map((g) => `<section class="cp-group">
                <button class="cp-ghead" data-collapse="${esc(d.key + '/c/' + g.id)}" aria-expanded="${!state.collapsed[d.key + '/c/' + g.id]}">
                  <span class="cp-gtick">${state.collapsed[d.key + '/c/' + g.id] ? '▸' : '▾'}</span>
                  <span class="cp-glabel">${esc(g.label || 'ohne')}</span><span class="cp-n">${g.items.length}</span></button>
                ${state.collapsed[d.key + '/c/' + g.id] ? '' : `<div class="cp-rows">${g.items.slice(0, 120).map((r) => {
                    const n = node(r.id);
                    return `<button class="cp-row" data-go="${esc(r.id)}"><span class="cp-rowlab">${esc(binding.label(n))}${r.repeat ? `<span class="cp-rep">${esc(L.again)}</span>` : ''}</span>
                      <span class="cp-meta">${esc(binding.typeName(n))}</span></button>`;
                  }).join('')}</div>`}</section>`).join('')}</div>`;
        }
        const [name, gloss] = L[d.key] || [d.key, ''];
        const depth = state.depth[d.key] || 1;
        if (!c.rows.length) return `<p class="cp-empty">${esc(L.empty)}</p>`;
        return `<div class="cp-conehead">${c.rows.length} ${esc(L.rows)} · <b>${c.distinct}</b> ${esc(L.distinct)}
            · ${esc(L.upto)} ${c.maxDepth}${c.cycle ? ` · <span class="cp-cyc">${esc(L.cycle)}</span>` : ''}</div>
          <div class="cp-rows">${c.rows.map((r) => {
              const n = node(r.id);
              return `<button class="cp-row cp-cone" data-go="${esc(r.id)}" style="padding-left:${10 + (r.depth - 1) * 17}px"
                        ${r.scoped ? `data-scoped="${esc(r.scoped)}"` : ''}>
                <span class="cp-rowlab">${r.depth > 1 ? '<span class="cp-tick">└</span>' : ''}${esc(binding.label(n))}${r.repeat ? `<span class="cp-rep">${esc(L.again)}</span>` : ''}</span>
                <span class="cp-meta">${esc(binding.typeName(n))}</span>
                <span class="cp-sub"><em>${esc(rel(r).termLabel || r.kind)}</em>${r.scoped ? `<span class="cp-off">${esc(r.scoped)}</span>` : ''}</span></button>`;
          }).join('')}</div>
          ${c.truncated ? `<p class="cp-empty">${esc(L.capped)} ${c.rows.length} ${esc(L.of)} ${c.total}.</p>` : ''}`;
    }

    /**
     * Rows under headers. The reader collapses a group they do not care about, which is the only
     * thing that makes a direction with two hundred and fifty steps readable - and the pmx corpus
     * has exactly that, because every model run in an analysis eats the same dataset.
     *
     * Counts sit in the header even when collapsed: a collapsed group must still say how much is
     * behind it, or collapsing becomes a way to lose track of what you were looking at.
     */
    function renderGroups(d, groups) {
        return `<div class="cp-groups">${groups.map((g) => {
            const ck = d.key + '/' + g.id;
            const shut = !!state.collapsed[ck];
            return `<section class="cp-group">
              <button class="cp-ghead" data-collapse="${esc(ck)}" aria-expanded="${!shut}"
                ${g.title ? `title="${esc(g.title)}"` : ''}>
                <span class="cp-gtick">${shut ? '▸' : '▾'}</span>
                <span class="cp-glabel">${esc(g.label || 'ohne')}</span>
                <span class="cp-n">${g.items.length}</span></button>
              ${shut ? '' : `<div class="cp-rows">${g.items.slice(0, 200).map((s) => {
                  const t = s[other(d)], tn = node(t);
                  return `<button class="cp-row" data-go="${esc(t)}">
                    <span class="cp-rowlab">${esc(binding.label(tn))}</span>
                    <span class="cp-meta">${esc(binding.typeName(tn))}</span>
                    <span class="cp-sub"><em>${esc(rel(s).termLabel || s.kind)}</em>${tn.participant ? `<span>${esc(tn.participant)}</span>` : ''}</span></button>`;
                }).join('')}${g.items.length > 200 ? `<p class="cp-empty">${esc(L.andMore)} ${g.items.length - 200}</p>` : ''}</div>`}
            </section>`;
        }).join('')}</div>`;
    }

    function renderDirection(d) {
        const { steps, hidden } = stepsFor(d);
        const [name, gloss] = L[d.key] || [d.key, ''];
        const rels = new Map();
        for (const s of steps) { const r = rel(s); const e = rels.get(r.id) || { label: r.label, n: 0, known: r.known }; e.n++; rels.set(r.id, e); }
        const active = state.relFilter[d.key];
        const shown = active ? steps.filter((s) => rel(s).id === active) : steps;
        const grouped = state.groupKey
            ? groupList(shown.slice(0, 400), (e) => state.groupKey(node(e[other(d)])))
            : null;
        const depth = state.depth[d.key] || 1;
        return `<section class="cp-dir cp-axis-${esc(d.axis)}">
          <header><div class="cp-dirtop"><span class="cp-dirname">${esc(name)}</span>
            <span class="cp-count">${steps.length}</span>
            <span class="cp-depth" title="${esc(L.depthHint)}">
              <button class="cp-dstep" data-depth="${esc(d.key)}" data-to="${Math.max(1, depth - 1)}" ${depth <= 1 ? 'disabled' : ''}>−</button>
              <span class="cp-dnum">${depth === 1 ? esc(L.onestep) : esc(L.depth) + ' ' + depth}</span>
              <button class="cp-dstep" data-depth="${esc(d.key)}" data-to="${depth + 1}">+</button>
            </span></div>
            <div class="cp-gloss">${esc(gloss)}</div></header>
          <div class="cp-rels">${[...rels].map(([id, r]) => `<button class="cp-rel" data-dir="${esc(d.key)}"
            data-rel="${esc(id)}" aria-pressed="${active === id}" ${r.known ? '' : 'title="der Sketch kennt diesen Term noch nicht"'}><b>${esc(r.label)}${r.known ? '' : ' ?'}</b>
            <span class="cp-n">${r.n}</span></button>`).join('')}</div>
          ${depth > 1 ? renderCone(d) : ''}
          ${depth === 1 && grouped ? renderGroups(d, grouped) : ''}
          <div class="cp-rows" ${depth > 1 || grouped ? 'hidden' : ''}>${shown.length ? shown.slice(0, 200).map((s) => {
              const t = s[other(d)], tn = node(t);
              return `<button class="cp-row" data-go="${esc(t)}">
                <span class="cp-rowlab">${esc(binding.label(tn))}</span>
                <span class="cp-meta">${esc(binding.typeName(tn))}</span>
                <span class="cp-sub"><em>${esc(rel(s).termLabel || s.kind)}</em>${tn.participant ? `<span>${esc(tn.participant)}</span>` : ''}
                  ${tn.headline ? `<span>${esc(tn.headline)}</span>` : ''}</span></button>`;
          }).join('') : `<p class="cp-empty">${esc(L.empty)}</p>`}</div>
          ${hidden.length ? `<button class="cp-scoped" data-reveal="${esc(d.key)}">${hidden.map((h) =>
              `${h.count} ${esc(L.scoped)} <b>(${esc(h.reason)})</b>`).join(' · ')} — ${esc(L.reveal)} ▸</button>`
            : state.reveal[d.key] ? `<button class="cp-scoped cp-on" data-reveal="${esc(d.key)}">${esc(L.restore)} ◂</button>` : ''}
        </section>`;
    }

    root.addEventListener('click', (ev) => {
        const go = ev.target.closest('[data-go]');
        if (go) return api.goTo(go.dataset.go);
        const jump = ev.target.closest('[data-jump]');
        if (jump) { const i = +jump.dataset.jump; state.trail = state.trail.slice(0, i + 1); return api.goTo(state.trail[i], false); }
        const rel = ev.target.closest('.cp-rel');
        if (rel) { const d = rel.dataset.dir; state.relFilter[d] = state.relFilter[d] === rel.dataset.rel ? null : rel.dataset.rel; return render(); }
        const cl = ev.target.closest('[data-collapse]');
        if (cl) { const k = cl.dataset.collapse; state.collapsed[k] = !state.collapsed[k]; return render(); }
        const dp = ev.target.closest('[data-depth]');
        if (dp) { state.depth[dp.dataset.depth] = Math.max(1, +dp.dataset.to); render();
                  return onIntent({ type: 'depth', direction: dp.dataset.depth, depth: state.depth[dp.dataset.depth], node: state.at }); }
        const rv = ev.target.closest('[data-reveal]');
        if (rv) { const d = rv.dataset.reveal; state.reveal[d] = !state.reveal[d]; onIntent({ type: 'reveal', direction: d, node: state.at }); return render(); }
        const act = ev.target.closest('[data-act]');
        // The element does not know what the action does, and must not: it reports that the reader
        // asked for it, and the host resolves that against whatever it can actually offer.
        if (act) return onIntent({ type: 'act', action: act.dataset.act, node: state.at });
    });

    const api = {
        goTo(addr, push = true) {
            if (!byId.has(addr)) return false;
            state.at = addr;
            state.relFilter = {};
            state.reveal = {};
            if (push) { state.trail.push(addr); if (state.trail.length > 14) state.trail = state.trail.slice(-14); }
            render();
            onIntent({ type: 'navigate', node: addr });
            return true;
        },
        setPerspective(name) {
            state.perspective = name;
            state.relFilter = {};
            state.reveal = {};
            render();
            onIntent({ type: 'mask', perspective: name, unknownClasses: unknownClasses() });
        },
        perspectives: () => Object.keys(perspectives),
        /** Narrow which instances are offered unasked, without touching the perspective. */
        setFacets(f) { state.facets = f || {}; state.reveal = {}; render(); onIntent({ type: 'mask', perspective: state.perspective, facets: state.facets, unknownClasses: unknownClasses() }); },
        facets: () => ({ ...state.facets }),
        /** How far each direction is followed. 1 is one step; above that the direction is a cone. */
        setDepth(d) { state.depth = { ...(d || {}) }; render(); },
        /** Group the rows of every direction. `key` is node -> {id,label}; null turns it off. */
        setGrouping(key, label) { state.groupKey = key || null; state.groupLabel = label || ''; state.collapsed = {}; render();
            onIntent({ type: 'group', grouping: label || '', node: state.at }); },
        grouping: () => state.groupLabel,
        depth: () => ({ ...state.depth }),
        /** The values a facet actually takes in this graph, with counts - a host cannot guess them. */
        facetValues(name) {
            const out = new Map();
            for (const n of byId.values()) for (const a of binding.attrs(n)) if (a.n === name) out.set(a.v, (out.get(a.v) || 0) + 1);
            return [...out].sort((x, y) => y[1] - x[1]).map(([value, count]) => ({ value, count }));
        },
        /** What the four directions currently offer, without going through the DOM. Exists so a
         *  check can WALK the compass instead of asserting that its files are present - the same
         *  distinction that made an earlier scenario checker report 8 of 10 where 6 were walkable. */
        directions: () => DIRECTIONS.map((d) => {
            const { steps, hidden } = stepsFor(d);
            const c = coneFor(d);
            return { key: d.key, axis: d.axis, hidden, to: steps.map((e) => e[other(d)]),
                     kinds: steps.map((e) => e.kind), rels: steps.map((e) => rel(e).id),
                     depth: state.depth[d.key] || 1,
                     cone: { rows: c.rows.length, distinct: c.distinct, maxDepth: c.maxDepth,
                             truncated: c.truncated, ids: c.rows.map((r) => r.id) } };
        }),
        at: () => state.at,
        nodes: () => [...byId.values()],
        refresh: render,
    };
    return api;
}
