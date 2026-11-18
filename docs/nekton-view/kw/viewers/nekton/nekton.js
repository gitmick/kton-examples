/**
 * The nekton side, as a reader meets it: first every scope and how they hang together, then one
 * scope's chain, statement by statement.
 *
 *   ?src=<url>      a .nekton.jsonl (a subnekton, or the unscoped nekton) - repeat it, or a comma
 *                   list. Each file stays its own source: nothing is merged before it is read,
 *                   because a subnekton is only valid with its whole chain (core/chain.js).
 *                   A plankton object file may be named too; its fotons only give names to hashes.
 *   ?keys= ?names=  keys.json / names.json, as the lens and the graph take them
 *   ?file=<url>     a file whose hash a claim names (a rule, a script): hashed here, then named
 *   ?scope=<id>     open one scope (or "unscoped-<n>") instead of the overview; &hl=<claim id>
 *   ?graph= ?compass=  where the two other viewers live (default: next door in this kit)
 *
 * What counts as verified is the kernel's verdict over all the sources together (the wasm graph),
 * never the record's own say-so - the same rule the lens and the graph follow.
 */
import { loadKton } from "../../runtime/kton.js";
import { recordsFromText } from "../../core/registry.js";
import { readSubnekton } from "../../core/chain.js";

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const bare = (h) => String(h || "").replace(/^sha256:/, "").toLowerCase();
const short = (h) => bare(h).slice(0, 8) + "…";
const lastSeg = (u) => String(u || "").replace(/[/#]+$/, "").split(/[/#]/).pop();
const clip = (s, n) => { s = String(s || ""); return s.length > n ? s.slice(0, n - 1) + "…" : s; };

const qs = new URLSearchParams(location.search);
const list = (k) => qs.getAll(k).flatMap((s) => s.split(",")).map((s) => s.trim()).filter(Boolean);
const abs = (u) => new URL(u, location.href).href;
const SRC = list("src").map(abs), FILES = list("file").map(abs);
const KEYS_URL = qs.get("keys") ? abs(qs.get("keys")) : "", NAMES_URL = qs.get("names") ? abs(qs.get("names")) : "";
const GRAPH = abs(qs.get("graph") || "../graph/index.html"), COMPASS = abs(qs.get("compass") || "../compass/index.html");
const PAL = ["--a", "--b", "--c", "--d", "--e", "--f"];
const SCOPE_V0 = "https://kton.dev/scope/v0";

function decode(rec) {
    try { return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(rec.envelope.payload), (c) => c.charCodeAt(0)))); } catch { return null; }
}
async function text(u) { const r = await fetch(u); if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.text(); }
async function sha256(buf) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", buf))].map((b) => b.toString(16).padStart(2, "0")).join(""); }

/* ---------- reading ---------- */

const W = { scopes: [], groups: [], byId: new Map(), keys: {}, names: {}, nodes: new Map(), fileName: new Map(), fotons: new Map(), colour: {} };

async function read() {
    if (!SRC.length) throw new Error("no sources: name the scopes' .nekton.jsonl files with ?src=");
    [W.keys, W.names] = await Promise.all([KEYS_URL, NAMES_URL].map(async (u) => { try { return u ? JSON.parse(await text(u)) : {}; } catch { return {}; } }));
    const all = [], seen = new Set();
    for (const url of SRC) {
        let recs; try { recs = recordsFromText(await text(url)).records; } catch (e) { W.groups.push({ id: "missing-" + W.groups.length, kind: "missing", src: url, stmts: [], err: String(e.message || e) }); continue; }
        for (const r of recs) { const id = r.claimId || r.fotonId; if (id && !seen.has(id)) { seen.add(id); all.push(r); } }
        const stmts = recs.map((rec) => ({ rec, id: bare(rec.claimId || rec.fotonId), foton: !!rec.fotonId, st: decode(rec), src: url })).filter((s) => s.st);
        const seed = stmts.find((s) => s.st.predicateType === SCOPE_V0 && s.st.predicate && s.st.predicate.genesis);
        if (seed) W.scopes.push(scopeOf(seed, stmts, recs, url));
        else if (stmts.some((s) => !s.foton)) W.groups.push({ id: "unscoped-" + W.groups.filter((g) => g.kind === "unscoped").length, kind: "unscoped", name: "unscoped", src: url,
            stmts: stmts.filter((s) => !s.foton).sort((a, b) => String(a.st.predicate.when || "").localeCompare(String(b.st.predicate.when || ""))) });
        for (const s of stmts) {
            if (!W.byId.has(s.id)) W.byId.set(s.id, s);
            if (s.foton) W.fotons.set(s.id, s);
            for (const ref of [...(s.st.subject || []), ...((s.st.predicate && s.st.predicate.inputs) || [])])
                if (s.foton && ref.name && ref.digest && ref.digest.sha256) W.fileName.set(bare(ref.digest.sha256), ref.name);
        }
    }
    for (const s of W.scopes) for (const x of s.stmts) x.home = s;
    for (const g of W.groups) for (const x of g.stmts) x.home = g;
    for (const u of FILES) { try { W.fileName.set(await sha256(await (await fetch(u)).arrayBuffer()), decodeURIComponent(u.split("/").pop())); } catch { /* a file we cannot reach names nothing */ } }

    // the kernel's verdict over everything at once: a claim verifies or it does not
    const kton = await loadKton();
    const g = kton.buildGraph(JSON.stringify(all), W.keys, W.names);
    for (const n of g.nodes) W.nodes.set(n.id, n);
    // colours in the graph viewer's order: the published names sorted, then whoever else signed
    const named = [...new Set(Object.values(W.names))].sort();
    const signers = [...new Set([...W.byId.values()].map(signer))];
    [...named, ...signers.filter((p) => !named.includes(p))].forEach((p, i) => { W.colour[p] = `var(${PAL[i % PAL.length]})`; });
    relate();
}

function scopeOf(seed, stmts, recs, src) {
    const sub = readSubnekton(recs);
    // the chain in its signed order: seed, then whatever names the previous one as `prev`
    const next = new Map();
    for (const s of stmts) { const p = bare(s.st.predicate && s.st.predicate.prev); if (p && !next.has(p)) next.set(p, s); }
    const chain = [seed], on = new Set([seed.id]);
    for (let at = seed; next.has(at.id) && !on.has(next.get(at.id).id);) { at = next.get(at.id); chain.push(at); on.add(at.id); }
    const off = stmts.filter((s) => !on.has(s.id));
    return { id: seed.id, kind: "scope", name: seed.st.predicate.scope || short(seed.id), src, stmts, chain, off, sub,
             parent: bare(seed.st.predicate.parent && (seed.st.predicate.parent.hash || seed.st.predicate.parent)), kids: [], about: [] };
}

const node = (id) => W.nodes.get(bare(id).slice(0, 32));
const verified = (s) => !!(node(s.id) || {}).verified;
function signer(s) { const n = node(s.id); return (n && n.participant) || (s.st.predicate && s.st.predicate.by) || "?"; }
const pred = (s) => s.st.predicateType === SCOPE_V0 ? "seed" : lastSeg(s.st.predicate && s.st.predicate.predicate && s.st.predicate.predicate.uri) || "claim";
const subjects = (s) => (s.st.subject || []).map((x) => x.uri ? { uri: x.uri } : { hash: bare(x.digest && x.digest.sha256) });
const scopeById = (id) => W.scopes.find((s) => s.id === bare(id));

/** What a parent says about its children (anchors, seals), and which other sources a scope's claims are about. */
function relate() {
    for (const s of W.scopes) { const p = scopeById(s.parent); if (p) p.kids.push(s); }
    for (const home of [...W.scopes, ...W.groups]) for (const x of home.stmts) {
        const k = pred(x);
        for (const sj of subjects(x)) {
            const child = sj.hash && scopeById(sj.hash);
            if (child && child !== home && (k === "closed" || k === "review-initialised")) {
                (child.about).push({ kind: k, claim: x, in: home, names: bare(x.st.predicate.object && x.st.predicate.object.hash) });
            }
        }
    }
}

/** A seal is a `closed` claim in the parent naming the child's head. */
function sealOf(s) {
    const seals = s.about.filter((a) => a.kind === "closed");
    if (!seals.length) return { tier: "open", text: "open: no seal for it in the loaded scopes" };
    const a = seals[seals.length - 1], i = s.chain.findIndex((x) => x.id === a.names);
    if (!verified(a.claim)) return { tier: "bad", a, text: "a seal is there, but its signature does not verify" };
    if (a.names === s.sub.head && !s.sub.provisional) return { tier: "sealed", a, text: `sealed in «${a.in.name}»: the head it names is this chain's head` };
    if (i >= 0) return { tier: "partial", a, text: `sealed in «${a.in.name}» at #${i}; ${s.chain.length - 1 - i} statement(s) came after the seal` };
    return { tier: "bad", a, text: `the seal in «${a.in.name}» names ${short(a.names)}, which this copy of the chain does not reach` };
}

/* ---------- naming things ---------- */

const dot = (name) => `<span class="dot" style="background:${W.colour[name] || "var(--faint)"}" title="${esc(name)}"></span>`;
const AGENT = /kton\.dev\/agent\/([0-9a-f]+)/;

/** A subject or object, said as plainly as the sources allow. `link` makes in-page jumps. */
function say(ref, link = true) {
    if (!ref) return "";
    if (ref.value !== undefined) return `<span class="val">«${esc(clip(ref.value, 160))}»</span>`;
    if (ref.uri) {
        const m = String(ref.uri).match(AGENT);
        if (m) { const nm = W.names[m[1]] || ""; return `${nm ? dot(nm) : ""} <span class="ref mono" title="${esc(ref.uri)}">key ${esc(m[1].slice(0, 8))}</span>`; }
        return `<span class="ref" title="${esc(ref.uri)}">${esc(lastSeg(ref.uri))}</span>`;
    }
    const h = bare(ref.hash);
    const sc = scopeById(h);
    if (sc) return link ? `<a class="ref" data-go="${esc(sc.id)}">scope «${esc(sc.name)}»</a>` : `scope «${esc(sc.name)}»`;
    const x = W.byId.get(h);
    if (x && x.foton) return `<span class="ref" title="sha256:${h}">run ${esc(fotonLabel(x))}</span>`;
    if (x) {
        const v = x.st.predicate && x.st.predicate.object && x.st.predicate.object.value;
        const where = x.home ? (x.home.kind === "scope" ? `#${x.home.chain.indexOf(x)} in «${x.home.name}»` : "unscoped") : "";
        const head = W.scopes.find((s) => s.sub.head === h);
        const t = `${esc(pred(x))} ${dot(signer(x))}${v != null ? " " + `<span class="val">«${esc(clip(v, 70))}»</span>` : ""}`;
        return (link ? `<a class="ref" data-go="${esc(x.home ? x.home.id : "")}" data-hl="${h}">` : "<span>") + `claim ${t}` + (link ? "</a>" : "</span>") +
            ` <span class="meta">${esc(where)}${head ? ` · the head of «${esc(head.name)}»` : ""}</span>`;
    }
    const f = W.fileName.get(h);
    if (f) return `<span class="ref" title="sha256:${h}">file <b>${esc(f)}</b></span> <span class="meta mono">${short(h)}</span>`;
    return `<span class="ref mono" title="sha256:${h} - not in these sources">sha256:${short(h)}</span>`;
}
function fotonLabel(x) {
    const p = x.st.predicate || {}, cmd = p.protocol && p.protocol.descriptor && p.protocol.descriptor.cmd;
    const outs = (x.st.subject || []).map((o) => o.name).filter(Boolean);
    return [cmd ? `«${cmd}»` : short(x.id), outs.length ? "→ " + outs.join(", ") : ""].filter(Boolean).join(" ");
}

function viewerLink(base, focus, extra = {}) {
    const p = new URLSearchParams();
    p.set("union", SRC.join(","));
    if (KEYS_URL) p.set("keys", KEYS_URL);
    if (NAMES_URL) p.set("names", NAMES_URL);
    if (focus) p.set("focus", "sha256:" + bare(focus));
    for (const [k, v] of Object.entries(extra)) p.set(k, v);
    return base + "?" + p.toString();
}

/* ---------- the overview: every scope, its parent above it ---------- */

function overview() {
    const BW = 268, GX = 46, GY = 92, LH = 19;
    const items = [];
    const lines = (s) => {
        const L = [];
        if (s.kind === "scope") {
            L.push({ t: `${s.stmts.length} statements · head ${short(s.sub.head || s.sub.tail)}`, c: "dimt" });
            L.push(s.sub.intact ? { t: "chain intact, seed to head ✓", c: "okt" } : { t: `chain: ${s.sub.gaps.length} gap(s), ${s.sub.forks.length} fork(s)`, c: "badt" });
            if (s.parent) { const z = sealOf(s); L.push({ t: z.tier === "sealed" ? "sealed in the parent ✓" : z.tier === "open" ? "open (no seal yet)" : z.text, c: z.tier === "sealed" ? "okt" : z.tier === "open" ? "dimt" : "badt" }); }
            for (const k of s.kids) for (const a of k.about.filter((a) => a.in === s))
                L.push({ t: (a.kind === "closed" ? "■ seals «" : "⚑ anchors the rule of «") + k.name + "»" + (a.kind === "closed" && sealOf(k).tier === "sealed" ? " ✓" : ""), c: "" });
        } else if (s.kind === "unscoped") {
            L.push({ t: `${s.stmts.length} claims, each on its own (no chain)`, c: "dimt" });
        } else L.push({ t: "not loaded", c: "badt" });
        return L;
    };
    const signersOf = (s) => { const m = new Map(); for (const x of s.stmts) m.set(signer(x), (m.get(signer(x)) || 0) + 1); return m; };
    const height = (s) => 72 + lines(s).length * LH;

    // the tree: a scope sits under its parent; a parent that is named but not handed in is drawn as such
    const roots = [];
    const missing = new Map();
    for (const s of W.scopes) {
        if (!s.parent) roots.push(s);
        else if (!scopeById(s.parent)) {
            if (!missing.has(s.parent)) { const m = { id: s.parent, kind: "missing", name: "parent not loaded", stmts: [], kids: [] }; missing.set(s.parent, m); roots.push(m); }
            missing.get(s.parent).kids.push(s);
        }
    }
    let col = 0; const pos = new Map();
    const place = (s, depth) => {
        if (!s.kids.length) { pos.set(s, { col: col++, depth }); return; }
        s.kids.forEach((k) => place(k, depth + 1));
        const c = s.kids.map((k) => pos.get(k).col);
        pos.set(s, { col: (Math.min(...c) + Math.max(...c)) / 2, depth });
    };
    roots.forEach((r) => place(r, 0));
    for (const g of W.groups) pos.set(g, { col: col++, depth: 0 });          // unscoped: a group of its own, beside the tree
    const all = [...pos.keys()], maxDepth = Math.max(0, ...all.map((s) => pos.get(s).depth));
    const rowH = []; for (let d = 0; d <= maxDepth; d++) rowH[d] = Math.max(0, ...all.filter((s) => pos.get(s).depth === d).map(height));
    const rowY = []; let y = 20; for (let d = 0; d <= maxDepth; d++) { rowY[d] = y; y += rowH[d] + GY; }
    const width = Math.max(1, col) * (BW + GX) + GX, H = y - GY + 30;
    const at = (s) => { const p = pos.get(s); return { x: GX + p.col * (BW + GX), y: rowY[p.depth], h: height(s) }; };

    const edge = (a, b, label, cls, dashed) => {
        const A = at(a), B = at(b), x1 = A.x + BW / 2, y1 = A.y + A.h, x2 = B.x + BW / 2, y2 = B.y, my = (y1 + y2) / 2;
        const lx = (x1 + x2) / 2, ly = my;
        return `<path d="M${x1},${y1} C${x1},${my} ${x2},${my} ${x2},${y2}" fill="none" stroke="var(--${cls === "okt" ? "ok" : "line"})" stroke-width="2" ${dashed ? 'stroke-dasharray="5 5"' : ""} marker-end="url(#ah)"/>` +
            (label ? `<g><rect x="${lx - label.length * 3.6 - 8}" y="${ly - 11}" width="${label.length * 7.2 + 16}" height="22" rx="11" fill="var(--panel2)" stroke="var(--line)"/><text x="${lx}" y="${ly + 4}" text-anchor="middle" font-size="12" class="${cls || ""}">${esc(label)}</text></g>` : "");
    };
    for (const s of all) for (const k of (s.kids || [])) { const z = sealOf(k); items.push(edge(s, k, z.tier === "sealed" ? "sealed ✓" : z.tier === "open" ? "open" : "seal ⚠", z.tier === "sealed" ? "okt" : z.tier === "open" ? "dimt" : "badt")); }
    // a scope whose claims are about claims held elsewhere - a review of the llm's texts, by claim id
    for (const s of W.scopes) {
        const to = new Map();
        for (const x of s.stmts) for (const sj of subjects(x)) { const y = sj.hash && W.byId.get(sj.hash); if (y && y.home && y.home !== s && y.home.kind === "unscoped" && !y.foton) to.set(y.home, (to.get(y.home) || new Set()).add(y.id)); }
        for (const [g, ids] of to) {
            const A = at(s), B = at(g), x1 = A.x + BW, y1 = A.y + 30, x2 = B.x + BW / 2, y2 = B.y + B.h, k = pred(s.stmts.find((x) => subjects(x).some((sj) => ids.has(sj.hash)))), lbl = `${k === "reviewed" ? "reviews" : k} ${ids.size} of its claims`;
            items.push(`<path d="M${x1},${y1} C${x2},${y1} ${x2},${y1} ${x2},${y2}" fill="none" stroke="var(--accent)" stroke-width="1.6" stroke-dasharray="4 4" marker-end="url(#ah2)"/>` +
                `<text x="${x1 + 10}" y="${y1 - 8}" font-size="12.5" fill="var(--accent)">${esc(lbl)}</text>`);
        }
    }
    for (const s of all) {
        const A = at(s), L = lines(s), sg = signersOf(s);
        let dx = 0; const dots = [...sg].map(([n, c]) => { const t = `<circle cx="${A.x + 20 + dx}" cy="${A.y + 46}" r="6" fill="${W.colour[n] || "var(--faint)"}"><title>${esc(n)}</title></circle><text x="${A.x + 30 + dx}" y="${A.y + 50}" font-size="12" class="dimt">${c}</text>`; dx += 22 + String(c).length * 7; return t; }).join("");
        items.push(`<g class="node" data-go="${esc(s.kind === "missing" ? "" : s.id)}">` +
            `<rect class="box" x="${A.x}" y="${A.y}" width="${BW}" height="${A.h}" rx="10" fill="var(--panel)" stroke="var(--line)" stroke-width="1.5" ${s.kind !== "scope" ? 'stroke-dasharray="6 4"' : ""}/>` +
            `<text x="${A.x + 14}" y="${A.y + 25}" font-size="16" font-weight="650">${esc(s.kind === "unscoped" ? "unscoped" : s.name)}</text>` +
            `<text x="${A.x + BW - 12}" y="${A.y + 24}" font-size="11" text-anchor="end" class="dimt">${s.kind === "scope" ? (s.parent ? "scope" : "root scope") : s.kind === "unscoped" ? "nekton" : ""}</text>` +
            dots + L.map((l, i) => `<text x="${A.x + 14}" y="${A.y + 76 + i * LH}" font-size="12.5" class="${l.c}">${esc(clip(l.t, 40))}</text>`).join("") + `</g>`);
    }
    $("#ov").innerHTML = `<p class="lede">Every scope is a short chain of its own, opened by its seed and signed statement by statement. A child scope hangs under the parent its seed names; what the parent says about it (the rule it anchors, the head it seals) is listed in the parent. Click a scope to read its chain.</p>` +
        `<svg viewBox="0 0 ${width} ${H}" style="max-width:${Math.round(width * 1.3)}px" role="img" aria-label="the scopes and their hierarchy">` +
        `<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0L10,5L0,10z" fill="var(--faint)"/></marker>` +
        `<marker id="ah2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0L10,5L0,10z" fill="var(--accent)"/></marker></defs>` +
        items.join("") + `</svg>`;
}

/* ---------- one scope ---------- */

function oneScope(s, hl) {
    const isScope = s.kind === "scope";
    const rows = isScope ? [...s.chain, ...s.off] : s.stmts;
    const parent = isScope && scopeById(s.parent);
    const z = isScope && s.parent ? sealOf(s) : null;
    let html = `<div class="card"><h2>${esc(isScope ? s.name : "unscoped claims")}</h2>`;
    if (isScope) {
        html += `<div class="kv">scope <code title="sha256:${s.id}">sha256:${short(s.id)}</code>${s.parent ? ` · child of ${parent ? `<a class="ref" data-go="${parent.id}" style="color:var(--accent);cursor:pointer">«${esc(parent.name)}»</a>` : `<code>${short(s.parent)}</code> (not loaded)`}` : " · a root scope"}${s.kids.length ? ` · parent of ${s.kids.map((k) => `<a class="ref" data-go="${k.id}" style="color:var(--accent);cursor:pointer">«${esc(k.name)}»</a>`).join(", ")}` : ""}</div>`;
        html += `<div class="kv">chain: <b>${s.chain.length}</b> statements from the seed to the head <code>${short(s.sub.head || s.sub.tail)}</code> ${s.sub.intact ? '<span class="ok">✓ intact: no gap, no fork</span>' : `<span class="bad">${s.sub.gaps.length} gap(s), ${s.sub.forks.length} fork(s), ${s.off.length} off the chain</span>`}</div>`;
        if (z) html += `<div class="kv">${z.tier === "sealed" ? '<span class="ok">■ ' : z.tier === "open" ? "<span>" : '<span class="bad">'}${esc(z.text)}</span>${z.a ? ` (claim <a class="ref" data-go="${z.a.in.id}" data-hl="${z.a.claim.id}" style="color:var(--accent);cursor:pointer">${short(z.a.claim.id)}</a>, signed by ${dot(signer(z.a.claim))})` : ""}</div>`;
    } else html += `<div class="kv">${s.stmts.length} claims outside any scope: each stands on its own signature, with no chain and no seal.</div>`;
    html += `<div class="kv mono" style="color:var(--dim)">${esc(decodeURIComponent(s.src.split("/").slice(-3).join("/")))}</div>`;
    if (isScope) html += `<div class="acts"><a class="btn" href="${esc(viewerLink(GRAPH, s.id))}" target="_blank">open in the graph ↗</a><a class="btn" href="${esc(viewerLink(COMPASS, s.id))}" target="_blank">open in the compass ↗</a></div>`;
    html += `</div>`;
    if (isScope) html += review(s);

    html += `<div class="card"><h3>${isScope ? "The chain, seed first: each statement names the one before it" : "The claims, by time"}</h3><ol class="chain">`;
    rows.forEach((x, i) => {
        const p = x.st.predicate || {}, k = pred(x), who = signer(x), ok = verified(x);
        const off = isScope && i >= s.chain.length;
        let tri;
        if (k === "seed") tri = `<div class="tri"><span class="lbl">opens</span>scope «${esc(p.scope)}»${s.parent ? ` <span class="lbl">under</span>${say({ hash: s.parent })}` : ""}</div>`;
        else {
            const sj = subjects(x).map((r) => say(r)).join(", ");
            const ob = p.object ? (p.object.value !== undefined ? say({ value: p.object.value }) : p.object.hash ? say({ hash: p.object.hash }) : p.object.uri ? say({ uri: p.object.uri }) : esc(JSON.stringify(p.object))) : "";
            const ol = k === "closed" ? "head" : k === "review-initialised" ? (W.byId.has(bare(p.object && p.object.hash)) ? "its anchor" : "rule") : "is";
            tri = `<div class="tri"><span class="lbl">about</span>${sj || "-"}${ob ? ` <span class="lbl" style="margin-left:10px">${ol}</span>${ob}` : ""}</div>` +
                (p.foton ? `<div class="tri"><span class="lbl">under review</span>${say({ hash: p.foton })}</div>` : "");
        }
        html += `<li id="c-${x.id}" class="${x.id === hl ? "hl" : ""}"><span class="n" style="background:${W.colour[who] || "var(--faint)"}" title="${esc(who)}">${isScope ? (i === 0 ? "S" : off ? "?" : i) : i + 1}</span>` +
            `<div class="body"><span class="pred">${esc(k)}</span><span class="tick ${ok ? "ok" : "bad"}">${ok ? "✓ signature verifies" : "✗ does not verify"}</span>${off ? ' <span class="bad">· not on the chain</span>' : ""}${tri}` +
            `<div class="meta mono">claim ${short(x.id)}${p.when ? " · " + esc(p.when) : ""}</div></div>` +
            `<div class="side"><a href="${esc(viewerLink(GRAPH, x.id))}" target="_blank">graph ↗</a><a href="${esc(viewerLink(COMPASS, x.id))}" target="_blank">compass ↗</a></div></li>`;
    });
    html += `</ol></div>`;
    $("#one").innerHTML = html;
    if (hl) { const el = document.getElementById("c-" + hl); if (el) el.scrollIntoView({ block: "center" }); }
}

/** A review scope: the rule it anchored before anyone reviewed, and who delivered which approval. */
function review(s) {
    // only the anchor this scope holds about ITSELF: a parent also holds review-initialised claims, about its children
    const anchor = s.chain.find((x) => pred(x) === "review-initialised" && subjects(x).some((sj) => sj.hash === s.id));
    const reviews = s.chain.filter((x) => pred(x) === "reviewed");
    if (!anchor && !reviews.length) return "";
    let h = `<div class="card"><h3>The review</h3>`;
    if (anchor) {
        const ai = s.chain.indexOf(anchor), first = reviews.length ? s.chain.indexOf(reviews[0]) : -1;
        const up = s.about.find((a) => a.kind === "review-initialised");
        h += `<div class="kv">${dot(signer(anchor))} anchored the rule ${say({ hash: anchor.st.predicate.object && anchor.st.predicate.object.hash })} at #${ai}` +
            (first > ai ? ` <span class="ok">✓ before the first review (#${first})</span>` : first >= 0 ? ` <span class="bad">after a review was already given</span>` : "") + `</div>`;
        if (anchor.st.predicate.foton) h += `<div class="kv">under review: ${say({ hash: anchor.st.predicate.foton })}</div>`;
        h += `<div class="kv">${up ? (up.names === anchor.id ? `<span class="ok">✓</span> the parent «${esc(up.in.name)}» names this anchor (claim ${short(up.claim.id)})` : `<span class="bad">the parent «${esc(up.in.name)}» names another anchor (${short(up.names)})</span>`) : "the anchor is not named in a loaded parent"}</div>`;
    }
    if (reviews.length) {
        const items = [], who = [];
        for (const r of reviews) { for (const sj of subjects(r)) if (sj.hash && !items.includes(sj.hash)) items.push(sj.hash); const w = signer(r); if (!who.includes(w)) who.push(w); }
        const cell = (it, w) => { const r = reviews.filter((x) => signer(x) === w && subjects(x).some((sj) => sj.hash === it)); if (!r.length) return "<td class=\"c\" style=\"color:var(--faint)\">-</td>";
            const x = r[r.length - 1], v = x.st.predicate.object && x.st.predicate.object.value;
            return `<td class="c"><a class="ref" data-hl="${x.id}" data-go="${s.id}" style="cursor:pointer;color:${v === "approve" ? "var(--ok)" : "var(--bad)"}" title="claim ${short(x.id)}">${esc(v || "?")}${verified(x) ? " ✓" : " ✗"}</a></td>`; };
        h += `<div class="kv" style="margin-top:8px">The deliveries: what each reviewer signed, item by item. An item is named by its hash, so a text that changes later is a new claim that no approval covers.</div>`;
        h += `<table class="dl"><tr><th>item</th>${who.map((w) => `<th>${dot(w)}</th>`).join("")}</tr>` +
            items.map((it) => `<tr><td>${say({ hash: it })}</td>${who.map((w) => cell(it, w)).join("")}</tr>`).join("") + `</table>`;
    }
    return h + `</div>`;
}

/* ---------- routing ---------- */

function keyrow() {
    const present = [...new Set([...W.byId.values()].filter((x) => !x.foton).map(signer))];
    const order = Object.keys(W.colour).filter((p) => present.includes(p));
    $("#keyrow").innerHTML = `<span style="color:var(--dim)">signer:</span>` + order.map((p) => `<span>${dot(p)} ${esc(p)}</span>`).join("");
}
function show() {
    const q = new URLSearchParams(location.search), id = q.get("scope") || "", hl = q.get("hl") || "";
    const s = id && (W.scopes.find((x) => x.id === bare(id) || x.id.startsWith(bare(id))) || W.groups.find((g) => g.id === id));
    $("#ov").hidden = !!s; $("#one").hidden = !s;
    $("#crumbs").innerHTML = s ? `<a data-go="">all scopes</a> › ${s.kind === "scope" ? [...ancestry(s)].reverse().map((a) => a === s ? esc(a.name) : `<a data-go="${a.id}">${esc(a.name)}</a>`).join(" › ") : "unscoped"}` : "all scopes";
    if (s) oneScope(s, bare(hl)); else overview();
    window.scrollTo(0, 0);
    if (s && hl) { const el = document.getElementById("c-" + bare(hl)); if (el) el.scrollIntoView({ block: "center" }); }
}
function* ancestry(s) { for (let a = s, n = 0; a && n < 20; a = scopeById(a.parent), n++) yield a; }
function go(id, hl) {
    const u = new URL(location.href);
    if (id) u.searchParams.set("scope", id); else u.searchParams.delete("scope");
    if (hl) u.searchParams.set("hl", hl); else u.searchParams.delete("hl");
    history.pushState(null, "", u); show();
}
document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-go],[data-hl]"); if (!t) return;
    if (t.dataset.go === undefined) return;
    e.preventDefault(); go(t.dataset.go, t.dataset.hl || "");
});
addEventListener("popstate", show);

read().then(() => { $("#msg").hidden = true; keyrow(); show(); })
    .catch((e) => { $("#msg").innerHTML = `<span class="bad">${esc(e.message || e)}</span>`; });
