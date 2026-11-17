/**
 * Steering a viewer from outside it.
 *
 * A viewer is rarely the whole application. It sits in a verticle, an editor, a review tool - and
 * that host knows things the viewer cannot: which file is open, who is logged in, what the reader
 * was doing a moment ago. So the host must be able to say "show this node, under this perspective,
 * with these filters", and the viewer must be able to say back "the reader asked to open this
 * file" - which only the host can actually do.
 *
 * Two rules keep this from becoming a mess.
 *
 * ONE STATE. The URL already carries focus, perspective, facets and source (core/viewstate.js).
 * A message does not introduce a second model: it hands over the same state object, the viewer
 * applies it, and the URL follows. So a host-driven view can still be copied out of the address
 * bar and pasted into a ticket, and a reload lands where the host put it.
 *
 * THE VIEWER PERFORMS NOTHING. It reports that the reader asked for something and names it. What
 * "open in the editor" means is the host's business - the same line the compass element already
 * holds against its page, held once more against the embedding application. A viewer that reached
 * for an editor would be guessing about a world it cannot see.
 *
 *   host -> viewer   kton:set      {state}          apply this view
 *                    kton:ask      {want}           'state' | 'capabilities'
 *   viewer -> host   kton:ready    {capabilities, state}
 *                    kton:state    {state}          the reader moved, or the host's set landed
 *                    kton:intent   {intent}         navigate | act | reveal | mask
 *                    kton:refused  {what, why}      asked for something this viewer cannot do
 *
 * `kton:refused` matters more than it looks. A host that sets a facet the sketch does not declare,
 * or a node the corpus does not hold, must be told - otherwise it believes it steered and the
 * reader sees something else, and nobody finds out which of the two was wrong.
 */

const NS = "kton:";

/** Origins to trust. Defaults to the embedder; a page may widen it deliberately via ?host=origin. */
function allowedOrigins(explicit) {
    const out = new Set();
    for (const o of explicit || []) out.add(o);
    if (typeof location !== "undefined") {
        out.add(location.origin);
        const p = new URLSearchParams(location.search).get("host");
        if (p) for (const o of p.split(",").map((s) => s.trim()).filter(Boolean)) out.add(o);
    }
    return out;
}

/**
 * The viewer side. Give it what it can do and how to apply a state; it wires up the rest.
 *
 *   const host = hostBridge({
 *     capabilities: { facets: [...], perspectives: [...], sketch: 'default' },
 *     apply: (state) => { ... return {applied, refused} },
 *     current: () => readState(),
 *   });
 *   host.intent({type:'act', action:'open', node});   // bubbles out; also fine if nobody listens
 */
export function hostBridge({ capabilities = {}, apply, current, origins } = {}) {
    const embedded = typeof window !== "undefined" && window.parent && window.parent !== window;
    const allow = allowedOrigins(origins);
    const post = (type, body) => {
        if (!embedded) return;
        // '*' would broadcast a corpus view to any page that happens to hold the frame; name the
        // origins instead, even though it means one message per trusted origin
        for (const o of allow) { try { window.parent.postMessage({ type: NS + type, ...body }, o); } catch { /* not that one */ } }
    };

    const api = {
        embedded,
        state: (state) => post("state", { state }),
        intent: (intent) => post("intent", { intent }),
        refused: (what, why) => post("refused", { what, why }),
        ready: () => post("ready", { capabilities, state: current ? current() : null }),
    };

    if (typeof window !== "undefined") window.addEventListener("message", (ev) => {
        if (!ev.data || typeof ev.data.type !== "string" || !ev.data.type.startsWith(NS)) return;
        if (!allow.has(ev.origin)) { return; }              // silence is the right answer to a stranger
        const kind = ev.data.type.slice(NS.length);
        if (kind === "set" && apply) {
            const r = apply(ev.data.state || {}) || {};
            if (r.refused && r.refused.length) api.refused(r.refused, r.why || "not available in this view");
            api.state(current ? current() : null);
        }
        if (kind === "ask") {
            if (ev.data.want === "capabilities") api.ready();
            else api.state(current ? current() : null);
        }
    });

    return api;
}

/**
 * The host side. Wraps an iframe so a verticle does not have to know the wire format.
 *
 *   const v = embedKton(iframeEl, { onIntent, onState });
 *   v.set({ focus: nodeId, p: 'auditor', facets: { participant: ['qc'] } });
 */
export function embedKton(frame, { onIntent, onState, onReady, onRefused } = {}) {
    const target = () => new URL(frame.src, location.href).origin;
    const send = (type, body) => frame.contentWindow &&
        frame.contentWindow.postMessage({ type: NS + type, ...body }, target());

    window.addEventListener("message", (ev) => {
        if (ev.source !== frame.contentWindow) return;      // another frame's traffic is not ours
        if (!ev.data || typeof ev.data.type !== "string" || !ev.data.type.startsWith(NS)) return;
        const kind = ev.data.type.slice(NS.length);
        if (kind === "ready" && onReady) onReady(ev.data.capabilities, ev.data.state);
        if (kind === "state" && onState) onState(ev.data.state);
        if (kind === "intent" && onIntent) onIntent(ev.data.intent);
        if (kind === "refused" && onRefused) onRefused(ev.data.what, ev.data.why);
    });

    return {
        set: (state) => send("set", { state }),
        ask: (want = "state") => send("ask", { want }),
        frame,
    };
}
