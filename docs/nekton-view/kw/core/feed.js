/**
 * The workgroup feed: every lane's messages as one list, newest first.
 *
 * The feed does not read the registry itself. Trust is decided where the signatures are checked -
 * `cockpit ask` reads only what a trusted key signed - so the viewer takes the answers of the lanes
 * vocabulary's queries as SPARQL results (application/sparql-results+json) and only arranges them:
 *
 *   messages   feed-messages     every requests / announces / blocks, trusted only
 *   done       feed-done         every closing claim, trusted only
 *   routes     inbox-open-all    who an open message is for (by area -> the lane responsible)
 *   history    history-open      open messages moved from the markdown inboxes - UNSIGNED, kept apart
 *
 * Whoever runs the queries (tools/lanes-feed.sh, a host, an MCP tool) hands these four over; the
 * viewer never sees a key and never claims a message is trusted on its own account.
 */

export const KIND = { requests: "request", announces: "info", blocks: "blocked" };

/** SPARQL results JSON -> plain rows; a bare array of rows passes through. */
export function rows(results) {
    if (!results) return [];
    if (Array.isArray(results)) return results;
    return (results.results?.bindings || []).map((b) =>
        Object.fromEntries(Object.entries(b).map(([k, v]) => [k, v.value])));
}

/** `lane-kton-web-claims` -> `kton-web`: the signer label minus the key bookkeeping. */
export function who(label) {
    return (label || "?").replace(/^lane-/, "").replace(/-claims$/, "");
}

const tail = (iri) => (iri || "").split("/").pop();

/**
 * Join the four answers into one model.
 *   { entries: [{ id, ref, kind, area, title, text, why, fullText, from, when, scope, about,
 *                 to: [lane], closings: [{by, when, outcome, text}], open, signed: true }],
 *     history: [{ id, ref, kind, lane, title, text, from, when, open: true, signed: false }],
 *     lanes: [bare lane name], areas: [area] }
 */
export function buildFeed({ messages, done, routes, history } = {}) {
    const closed = new Map();
    for (const d of rows(done)) {
        for (const key of ["answers", "historical"]) {
            if (!d[key]) continue;
            if (!closed.has(d[key])) closed.set(d[key], []);
            closed.get(d[key]).push({ by: who(d.by), when: d.when, outcome: d.outcome || "", text: d.text || "" });
        }
    }
    const to = new Map();
    for (const r of rows(routes)) {
        if (!to.has(r.msg)) to.set(r.msg, new Set());
        to.get(r.msg).add(r.lane || "(nobody - unrouted)");
    }
    // a done names a claim by its IRI or by sha256:<id> - accept both, the queries are not ours
    const closingsOf = (msg) => [...(closed.get(msg) || []), ...(closed.get("sha256:" + tail(msg)) || [])];

    const entries = rows(messages).map((m) => {
        const closings = closingsOf(m.msg);
        return {
            id: m.msg, ref: "answers=sha256:" + tail(m.msg),
            kind: KIND[tail(m.kind)] || tail(m.kind) || "?",
            area: m.area || "", title: m.title || "", text: m.text || "",
            why: m.why || "", fullText: m.fullText || "",
            from: who(m.from), when: m.when || "", scope: m.scope || "", about: m.about || "",
            to: [...(to.get(m.msg) || [])].sort(),
            closings, open: closings.length === 0, signed: true,
        };
    }).sort((a, b) => (a.when < b.when ? 1 : a.when > b.when ? -1 : 0));

    const hist = rows(history).filter((h) => !closed.has(h.msg)).map((h) => ({
        id: h.msg, ref: "historical=" + h.msg,
        kind: KIND[tail(h.kind)] || tail(h.kind) || "?",
        lane: h.lane || "", title: h.title || "", text: h.text || "",
        from: h.from || "", when: h.when || "", open: true, signed: false,
    })).sort((a, b) => (a.lane + a.when < b.lane + b.when ? -1 : 1));

    // lanes by bare name: routes say `active/kton-web`, signers `kton-web` - one lane, one option
    const lanes = new Set(), areas = new Set(), bare = (l) => (l || "").split("/").pop();
    for (const e of entries) { e.to.forEach((l) => lanes.add(bare(l))); lanes.add(e.from); areas.add(e.area); }
    for (const h of hist) lanes.add(bare(h.lane));
    return { entries, history: hist, lanes: [...lanes].filter(Boolean).sort(), areas: [...areas].filter(Boolean).sort() };
}

/**
 * The reader's cut through the feed. A lane matches what it sent, what is routed to it, and - for
 * history - its own old inbox; `lane` given as `active/kton-web` or bare `kton-web` both work.
 */
export function filterFeed(feed, { lane = "", area = "", open = false, q = "" } = {}) {
    const bare = (l) => (l || "").split("/").pop();
    const L = bare(lane), needle = q.trim().toLowerCase();
    const hit = (s) => !needle || s.toLowerCase().includes(needle);
    const entries = feed.entries.filter((e) =>
        (!L || bare(e.from) === L || e.to.some((t) => bare(t) === L)) &&
        (!area || e.area === area) && (!open || e.open) &&
        hit([e.title, e.text, e.why, e.fullText, e.area, e.from].join(" ")));
    const history = area ? [] : feed.history.filter((h) =>
        (!L || bare(h.lane) === L) && hit([h.title, h.text, h.from].join(" ")));
    return { entries, history };
}

/** Group entries by local calendar day, keeping order. */
export function byDay(entries, day = (ts) => localStamp(ts).slice(0, 10)) {
    const out = [];
    for (const e of entries) {
        const d = day(e.when);
        if (!out.length || out[out.length - 1].day !== d) out.push({ day: d, entries: [] });
        out[out.length - 1].entries.push(e);
    }
    return out;
}

/** dct:created is UTC (...Z); the feed shows local time as YYYY-MM-DD HH:MM. */
export function localStamp(ts) {
    const d = new Date(ts);
    if (isNaN(d)) return (ts || "").slice(0, 16).replace("T", " ");
    const p = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
