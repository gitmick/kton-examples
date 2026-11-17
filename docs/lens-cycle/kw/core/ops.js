/**
 * The op surface: everything a viewer can do, as data.
 *
 * improve's verticle host takes a tenant's contribution as `{handlers, catalog}`, where a catalog
 * entry is `{op, description, inputSchema}` - which is a tool definition. MCP is then a projection
 * of that catalogue, reached over the same broker under the same audit. So the useful thing to
 * build is not a server: it is the surface. It plugs in unchanged whether it arrives through
 * `registerOpSurface`, through an mcp-tool verticle once that binder is finished, or through a
 * standalone server for a corpus on disk.
 *
 * Nothing here imports VS Code, a browser, or a transport. It is the same modules the viewers use,
 * described. That is the point: an agent asking "what can I do here" and a reader clicking a button
 * must get the same answer, or the two will drift and only one of them will be right.
 *
 * The surface is deliberately small and READ-ONLY. Writing means signing, and signing means saying
 * a PERSON attested something - which belongs to the host's `nekton:claim` under `profile.signers`,
 * readable in a descriptor before anything is mounted, and never to a viewer that decided on its own.
 */

import { indexGraph } from "./nav.js";
import { termsFromUnion } from "./terms.js";
import { makeConfig, edgeTerm } from "./config.js";
import { surveyFields, proposeRelations, deriveEdges, withDerived } from "./projection.js";
import { catalogue as questionCatalogue, ask } from "./questions.js";
import { catalogue as groupingCatalogue, makeKey, groupList, pathOf as groupingPath } from "./grouping.js";
import { catalogue as layoutCatalogue } from "./layout.js";
import { run as runQuery } from "./query.js";

/**
 * Build the surface over one corpus.
 *
 * `load` is `() => Promise<{union, keys, names, sketch}>` - a function, not data, because where the
 * union comes from is the host's business: a file on disk, `resource:read` inside improve, a fetch.
 * The surface does not learn which.
 */
/**
 * The algebra's vocabularies, in one place.
 *
 * `describe` publishes these and `ask` refuses against them, so the words an agent is offered and
 * the words it is judged by cannot drift apart. Before this they lived only as a comment in
 * core/query.js: composing a query meant reading the source, and getting it wrong meant a TypeError
 * from three frames down. A surface that invites composition owes the caller both halves.
 */
const ALGEBRA = {
    from: ["node", "fotons", "claims", "nodes"],
    dir: ["up", "down"],
    as: ["cone", "list", "count", "card"],
    where: ["{has:{pred,value?}}", "{lacks:{pred,value?}}", "{attr:{name,in:[...]}}"],
};

/**
 * Check a caller-composed query against the algebra. Returns a refusal, or null to proceed.
 * Named questions come from a sketch and are not run through this - a sketch is the surface's own.
 */
function checkQuery(q) {
    const refuse = (error, expected) => (expected ? { error, expected } : { error });
    if (typeof q !== "object" || q === null || Array.isArray(q)) {
        return refuse("`query` must be an object with the clauses from/walk/where/as", ALGEBRA);
    }
    if (q.from != null && !ALGEBRA.from.includes(q.from)) {
        return refuse(`unknown \`from\`: ${JSON.stringify(q.from)} - it names a starting SET, not a node (put the node in the \`node\` argument)`, ALGEBRA.from);
    }
    if (q.walk != null) {
        if (typeof q.walk !== "object" || Array.isArray(q.walk)) return refuse("`walk` must be {dir, edges?, depth?}");
        if (!ALGEBRA.dir.includes(q.walk.dir)) {
            return refuse(`unknown walk \`dir\`: ${JSON.stringify(q.walk.dir)} - the algebra walks the graph, it does not name a compass direction`, ALGEBRA.dir);
        }
        if (q.walk.edges != null && !Array.isArray(q.walk.edges)) return refuse("`walk.edges` must be an array of edge kinds (see describe.algebra.walk.edges)");
    }
    if (q.where != null && !Array.isArray(q.where)) return refuse("`where` must be an array of clauses", ALGEBRA.where);
    if (q.as != null && !ALGEBRA.as.includes(q.as)) return refuse(`unknown \`as\`: ${JSON.stringify(q.as)}`, ALGEBRA.as);
    return null;
}

export function ktonOps({ load, openCorpus, buildGraph, openVerticle, store, prefix = "kton" }) {
    // A mcp-tool verticle gets no launch context, so it cannot be told at mount time which corpus to
    // read - the corpus is an ARGUMENT. `openCorpus(ref)` resolves one; ref null means the default.
    // `load` stays for the single-corpus callers (the viewers, a standalone server) as a shorthand
    // for an openCorpus that ignores its ref. Each resolved corpus is cached under its ref, because
    // building a 5k-node graph on every call would make the surface unusable over a network.
    const open = openCorpus || (load ? (async () => load()) : null);
    if (!open) throw new Error("ktonOps: give `openCorpus` or `load`");

    const cache = new Map(); // ref -> Promise<state>
    function ready(ref = null) {
        const key = ref || "";
        if (!cache.has(key)) cache.set(key, (async () => {
            const src = await open(ref);
            const graph = buildGraph(src.union, src.keys || "{}", src.names || "{}");
            const G = indexGraph(graph);
            const terms = termsFromUnion(src.union);
            // The second layer, built once with the graph. It hangs BESIDE `G.edges` (withDerived
            // puts it on its own arrays and indexes), so every existing walk sees exactly what it
            // saw before and reading it has to be asked for.
            const objectFields = surveyFields(G, terms);
            const relations = proposeRelations(objectFields);
            withDerived(G, deriveEdges(G, terms, relations));
            return { G, terms, config: makeConfig(src.sketch || {}), graph, objectFields, relations };
        })());
        return cache.get(key);
    }

    const label = (n) => n.label || n.role || (n.id || "").slice(0, 12);
    const nodeBrief = (n) => ({
        id: n.id, type: n.type, label: label(n),
        participant: n.participant || undefined, verified: !!n.verified,
    });

    const handlers = {
        /**
         * The whole built graph, for a client that DRAWS rather than asks - the UI verticle. Its
         * webview cannot run the wasm (CSP forbids it) and cannot fetch (connect-src none), so the
         * host builds the graph once and hands it over as data; compass.js then runs unchanged over
         * it. Terms travel as an array because a Map does not survive postMessage.
         */
        [`${prefix}:graph`]: async (args = {}) => {
            const { graph, terms, config, G, relations } = await ready(args && args.union);
            // The derived layer travels SEPARATELY, next to the graph rather than inside it. A
            // client that ignores the key draws exactly what it drew before; one that reads it can
            // tell, per edge, that it is a reading and which claims stand behind it.
            return { graph, terms: [...terms.entries()], sketch: config.spec,
                     derived: { note: "erhoben, nicht bezeugt - siehe describe.derived", relations, edges: G.derived || [] } };
        },

        /**
         * What this corpus is, and what can be asked of it.
         *
         * A caller that has to guess the vocabulary will guess wrong, so this answers first: which
         * relations exist and how they group, what can be filtered, how rows can be grouped, which
         * named questions are on offer, and what the sketch does NOT know about this corpus.
         */
        [`${prefix}:describe`]: async (args = {}) => {
            const { G, terms, config, objectFields, relations: derived } = await ready(args && args.union);
            const survey = config.survey(G, terms);
            const types = {};
            for (const n of G.nodes) types[n.type] = (types[n.type] || 0) + 1;
            return {
                size: { nodes: G.nodes.length, edges: G.edges.length, types },
                relations: config.groups().map((g) => ({
                    id: g.id, label: g.label, axis: g.axis, note: g.note,
                    edges: survey.groupCounts.get(g.id) || 0,
                })),
                facets: config.facets(),
                // How the picture is ARRANGED is a declared choice like any other. Naming a layout
                // is not cosmetic here: the ancestry of one report puts 97 nodes in a single layer,
                // which as one column is a bar rather than a picture, and which layout answers that
                // is the reader's call - or the agent's, through kton:show.
                layouts: layoutCatalogue(config.spec).map((l) => ({
                    id: l.id, label: l.label, by: l.by,
                    ...(l.wrap ? { wrap: l.wrap } : {}), ...(l.orient ? { orient: l.orient } : {}),
                    ...(l.note ? { note: l.note } : {}),
                })),
                groupings: groupingCatalogue(config.spec).map((g) => {
                    const p = groupingPath(g);
                    return { id: g.id, label: g.label, by: g.by, ...(p ? { path: p } : {}), ...(g.note ? { note: g.note } : {}) };
                }),
                questions: questionCatalogue(config.spec).map((q) => ({
                    id: q.id, label: q.label, gloss: q.gloss, at: q.at, as: q.as,
                })),
                perspectives: config.perspectives().map((p) => ({ id: p.id, label: p.label })),
                // the four clauses a caller can compose with `ask.query`, with THIS corpus's edge
                // kinds - a vocabulary that is only true of some other corpus is not a vocabulary
                // How to READ the `path` on a root grouping above. Said once, next to the thing it
                // describes: it is not a clause of the ask algebra and does not belong in it.
                paths: {
                    note: "a root grouping's `path` says HOW it reaches its root; closures are budgeted, and a climb that runs out yields no group rather than the furthest node it happened to reach",
                    syntax: ["a", "^a", "a/b", "a|b", "a*", "a+", "a?", "( )"],
                    of: "a strict subset of SPARQL 1.1 property paths",
                },
                algebra: {
                    note: "compose with kton:ask `query` when no named question covers it",
                    from: ALGEBRA.from,
                    walk: { dir: ALGEBRA.dir, edges: [...new Set(G.edges.map((e) => e.kind))].sort(), depth: "number; omit to walk all the way" },
                    where: ALGEBRA.where,
                    as: ALGEBRA.as,
                },
                // said out loud rather than swallowed: SPEC 7.1 makes the term set open, so a sketch
                // is always somewhat behind a corpus, and a caller should know by how much
                unknownTerms: [...survey.unknown].map(([term, n]) => ({ term, edges: n })),
                // What the claim OBJECTS hold. `unknownTerms` says "I do not know these predicates";
                // this says "and here are the relations that sit in the corpus and reach no graph".
                // `projected` is the honest half: a field the kernel already drew is not news.
                ...(objectFields.length ? { objectFields } : {}),
                // Erhoben, not declared and not signed. A first view of a foreign corpus has to be
                // MADE, because a sketch can only speak about terms someone already wrote down - and
                // nobody has, the first time. Naming one of these is a separate act, signing it a
                // further one; until then this is a reading offered, not a fact asserted.
                ...(derived.length ? { derived: {
                    note: "erhoben, weder benannt noch unterschrieben - Beziehungen, die im Korpus stehen und keine Kante sind",
                    reading: "`as` ist ein Vorschlag aus der Streuung, kein Befund - die Zahlen daneben sind, womit er gemacht wurde",
                    // what the reading actually produced, and how much stands behind it: fewer edges
                    // than references means the same relation was attested more than once, not that
                    // something was dropped.
                    edges: (G.derived || []).length,
                    asserted: (G.derived || []).reduce((a, e) => a + e.claims.length, 0),
                    relations: derived,
                } } : {}),
            };
        },

        /**
         * Run a query in the algebra (core/query.js). The same four clauses the sketches write, so
         * an agent can compose what a named question does not cover - and gets refused the same way.
         */
        [`${prefix}:ask`]: async (args = {}) => {
            const { G, config } = await ready(args && args.union);
            const named = args.question
                ? questionCatalogue(config.spec).find((q) => q.id === args.question)
                : null;
            if (args.question && !named) {
                return { error: `unknown question: ${args.question}`,
                         available: questionCatalogue(config.spec).map((q) => q.id) };
            }
            const q = named || args.query;
            if (!q) return { error: "give either `question` (a named one) or `query` (from/walk/where/as)", algebra: ALGEBRA };
            if (!named) {
                const bad = checkQuery(args.query);
                if (bad) return bad;
            }
            const r = ask(G, q, { node: args.node || null, depth: args.depth ?? Infinity, budget: args.budget ?? 200 });
            if (r.kind === "list") return { kind: "list", n: r.list.length, of: r.total, items: r.list.slice(0, args.limit ?? 50).map(nodeBrief) };
            if (r.kind === "cone") return { kind: "cone", rows: r.rows.length, distinct: r.distinct, truncated: r.truncated,
                items: r.rows.slice(0, args.limit ?? 100).map((x) => ({ depth: x.depth, kind: x.kind, repeat: x.repeat, ...nodeBrief(G.byId.get(x.id) || { id: x.id }) })) };
            return r;
        },

        /**
         * Where you are standing: what is firm about this node, and every way out with counts.
         *
         * The directions come from the same four the compass draws, resolved through the sketch, so
         * "what can I do from here" reads the same to an agent and to a person.
         */
        [`${prefix}:node`]: async (args = {}) => {
            const { G, terms, config } = await ready(args && args.union);
            const n = G.byId.get(String(args.node || ""));
            if (!n) return { error: `no such node: ${args.node}` };
            const term = terms.get(n.id);
            const dirs = [
                { key: "origin", side: "out", lineage: true }, { key: "effect", side: "in", lineage: true },
                { key: "about", side: "in", lineage: false }, { key: "mentions", side: "out", lineage: false },
            ].map((d) => {
                const es = (d.side === "out" ? G.out[n.id] : G.in[n.id]) || [];
                const take = es.filter((e) => (e.kind === "builds-on") === d.lineage && e.from !== e.to);
                const byRel = new Map();
                for (const e of take) {
                    const r = config.resolve(edgeTerm(G, terms, e).term);
                    byRel.set(r.group, (byRel.get(r.group) || 0) + 1);
                }
                return { direction: d.key, n: take.length,
                         relations: [...byRel].map(([id, count]) => ({ id, count })) };
            });
            return {
                node: nodeBrief(n),
                term: term ? { term: term.term, short: term.short, context: term.context || undefined,
                               by: term.by || undefined, when: term.when || undefined, why: term.why || undefined } : undefined,
                inputs: n.inputs, outputs: n.outputs,
                directions: dirs,
            };
        },

        /** Find a node. Walking cannot reach every component - several fixtures fall into pieces - so
         *  search is not a convenience here, it is the only way into another piece. */
        [`${prefix}:search`]: async (args = {}) => {
            const { G } = await ready(args && args.union);
            const s = String(args.text || "").toLowerCase();
            if (!s) return { error: "give `text`" };
            const hits = G.nodes.filter((n) =>
                `${n.id} ${label(n)} ${n.role || ""} ${n.text || ""} ${n.participant || ""} ${n.by || ""}`
                    .toLowerCase().includes(s));
            return { n: hits.length, items: hits.slice(0, args.limit ?? 30).map(nodeBrief) };
        },

        /** Group a set of nodes the way a viewer would, so an agent can say "21 groups, largest 59"
         *  instead of listing 257 rows nobody will read. */
        [`${prefix}:group`]: async (args = {}) => {
            const { G, terms, config } = await ready(args && args.union);
            const spec = groupingCatalogue(config.spec).find((g) => g.id === args.grouping);
            if (!spec) return { error: `unknown grouping: ${args.grouping}`,
                                available: groupingCatalogue(config.spec).map((g) => g.id) };
            let nodes = G.nodes;
            if (args.query) nodes = (runQuery(G, args.query, { node: args.node || null }).list) || [];
            const groups = groupList(nodes, makeKey(spec, { G, terms }));
            return { grouping: spec.id, groups: groups.length,
                     items: groups.slice(0, args.limit ?? 40).map((g) => ({ id: g.id, label: g.label, n: g.items.length })) };
        },
    };

    const catalog = [
        { op: `${prefix}:graph`, description:
            "The whole built graph as data - nodes, edges, recovered terms, sketch - for a client that draws it rather than querying. Built host-side because a webview can neither run the wasm nor fetch.",
          inputSchema: { type: "object", properties: {} } },
        { op: `${prefix}:describe`, description:
            "What this corpus holds and what can be asked of it: relations and how they group, facets, groupings, named questions, perspectives, and the terms the sketch does not yet know. Call this first.",
          inputSchema: { type: "object", properties: {} } },
        { op: `${prefix}:ask`, description:
            "Ask a named question, or compose one in the query algebra (from / walk / where / as). Returns a list, a cone, or a tally.",
          inputSchema: { type: "object", properties: {
              question: { type: "string", description: "id of a named question from describe" },
              query: { type: "object", description: "from | walk {dir,edges,depth} | where [{has|lacks|attr}] | as" },
              node: { type: "string", description: "where to stand, for a question that needs it" },
              depth: { type: "number", description: "how far to follow a walk; omit for all the way" },
              limit: { type: "number" } } } },
        { op: `${prefix}:node`, description:
            "What stands at a node and every way out of it, with counts per relation. The same four directions a compass draws.",
          inputSchema: { type: "object", properties: { node: { type: "string" } }, required: ["node"] } },
        { op: `${prefix}:search`, description:
            "Find nodes by text over id, label, role, participant and claim text. A graph can fall into several pieces, so this is how you reach one that walking cannot.",
          inputSchema: { type: "object", properties: { text: { type: "string" }, limit: { type: "number" } }, required: ["text"] } },
        { op: `${prefix}:group`, description:
            "Group nodes, or a query's result, by a declared grouping. Returns group labels with counts, not the rows.",
          inputSchema: { type: "object", properties: {
              grouping: { type: "string" }, query: { type: "object" }, node: { type: "string" }, limit: { type: "number" } },
              required: ["grouping"] } },
    ];

    // every op may name a corpus; the default is what the surface was opened on. Added once here
    // so a new op cannot forget it and quietly serve only the default.
    for (const e of catalog) {
        e.inputSchema.properties.union = { type: "string",
            description: "repository path of the union to read; omit for the default corpus" };
    }

    // Steering, gated on a host that can open a verticle. This is the op the whole surface exists
    // for: not another read, but making the viewer the person is watching MOVE. Because the host
    // hands a fresh context to an ALREADY-OPEN panel (HostMount re-sends it, the viewer's onLaunch
    // applies it), one call re-aims focus, perspective, grouping and filters live - which is exactly
    // "steer the filtering over MCP". The read ops answer where to point it; this points it.
    if (openVerticle) {
        handlers[`${prefix}:show`] = async (args = {}) => {
            const toGraph = args.viewer === "graph";
            const viewer = toGraph ? "kton-graph" : "kton-compass";
            // Tailor the context to what the TARGET declares in accepts: the graph takes focus/mode/
            // graph, the compass focus/p/g/f/sketch/graph. Sending a field the target does not accept
            // is refused by the host, which is the wall an agent hits with viewer:"graph" if we pass
            // the compass-only p/g/f. So each viewer gets only its own fields.
            // The graph takes facets too now. It always HAD a type filter; it just could not be
            // reached from here, so "drop the claims" was a thing a person could click and an agent
            // could not ask for - and in a corpus where two thirds of the drawing is claims, that is
            // the difference between a picture and a texture.
            const fields = toGraph ? ["focus", "mode", "graph", "layout", "f"]
                                   : ["focus", "p", "g", "f", "sketch", "graph"];
            const context = {};
            const f = args.facets ? (typeof args.facets === "string" ? args.facets
                : Object.entries(args.facets).map(([k, v]) => `${k}:${[].concat(v).join(",")}`).join(";")) : null;
            const src = { ...args, focus: args.node ?? args.focus, f: f ?? args.f };
            for (const k of fields) if (src[k] != null) context[k] = src[k];
            await openVerticle(viewer, context);
            return { shown: viewer, applied: context };
        };
        catalog.push({ op: `${prefix}:show`, description:
            "Open a viewer, or re-aim the one already open, LIVE: focus a node, set the perspective, the "
            + "grouping, and filters. This is how an agent steers what the person is looking at - the read "
            + "ops find the target, this points the view at it.",
          inputSchema: { type: "object", properties: {
              viewer: { type: "string", enum: ["compass", "graph"], description: "which viewer (default compass)" },
              layout: { type: "string", description: "layout id from describe (graph only): how the picture is arranged" },
              node: { type: "string", description: "node to focus (its id, e.g. from search/ask)" },
              p: { type: "string", description: "perspective id (from describe)" },
              g: { type: "string", description: "grouping id (from describe)" },
              facets: { type: "object", description: "facet -> [values], e.g. {participant:['anna'], verified:['true']}" },
              mode: { type: "string", description: "graph pedigree mode: anc | desc | both | lin | imp" },
              graph: { type: "string", description: "repository path of a pre-built graph.json; omit for the default corpus" } } } });
    }

    // Ingest, gated on a host that can write. A page can SEAL a record — plktSealClaim and
    // plktSealFoton do the whole of it, and the private key stays in WebCrypto — but it cannot
    // STORE one: a browser has no filesystem and no repository. That is the only half missing, and
    // it is missing by nature rather than by omission, so it lives here where the broker checks the
    // write against profile.paths and stamps it to the audit trail.
    //
    // WHERE a record goes is decided by WHAT it is, per core/registry.js: the unit of the file is
    // the unit of validity. A foton is valid alone, so it becomes its own file and adding one is a
    // pure create — two harvesters ingesting the same run write identical bytes to the same path.
    // A claim is only valid with its chain, so the nekton is ONE file and adding means appending a
    // line to it.
    //
    // That append is a read-modify-write and therefore racy: two agents ingesting at the same
    // moment can lose one line. It is not guarded here because the guard belongs to whatever owns
    // the store, and pretending otherwise would hide the race rather than fix it. Ingest one
    // harvest at a time until the store offers an append.
    if (store) {
        handlers[`${prefix}:add`] = async (args = {}) => {
            // plktSealClaim hands back {record: "<json>"}, plktSealFoton hands back the object.
            // Accept either rather than making the caller remember which.
            let rec = args.record;
            if (typeof rec === "string") rec = JSON.parse(rec);
            if (!rec || !rec.envelope) throw new Error("kton:add needs a sealed record with an envelope");
            const id = rec.fotonId || rec.claimId;
            if (!id) throw new Error("kton:add needs a record carrying a fotonId or a claimId");

            const root = (args.registry || "").replace(/\/+$/, "");
            if (!root) throw new Error("kton:add needs `registry`, the repository path of the store");

            if (rec.fotonId) {
                const path = `${root}/plankton/objects/sha256/${id.replace(/^sha256:/, "")}.json`;
                await store.writeText(path, JSON.stringify(rec, null, 2) + "\n");
                return { added: id, kind: "foton", path, shape: "object" };
            }
            const path = `${root}/nekton/objects/unscoped.nekton.jsonl`;
            const prior = await store.readText(path).catch(() => "");
            // Idempotent by id: re-ingesting a record already in the file is a no-op rather than a
            // duplicate line. A record IS its id, so a second copy states nothing new.
            const lines = String(prior).split("\n").filter((l) => l.trim());
            if (lines.some((l) => l.includes(id))) return { added: id, kind: "claim", path, already: true };
            await store.writeText(path, [...lines, JSON.stringify(rec)].join("\n") + "\n");
            return { added: id, kind: "claim", path, shape: "jsonl", lines: lines.length + 1 };
        };
        catalog.push({ op: `${prefix}:add`, description:
            "Store a sealed record — a foton or a claim — in a repository registry. The page seals it "
            + "(plktSealFoton / plktSealClaim, key never leaving WebCrypto); this is the half a browser "
            + "cannot do. A foton becomes its own file, a claim is appended to the nekton, because the "
            + "unit of the file is the unit of validity. Signatures are NOT verified here: the host holds "
            + "no key to check them against.",
          inputSchema: { type: "object", properties: {
              record: { description: "the sealed record {fotonId|claimId, envelope}, or the JSON string plktSealClaim returns" },
              registry: { type: "string", description: "repository path of the store, e.g. /demos/demo1-kton" } },
            required: ["record", "registry"] } });
    }

    return { handlers, catalog, reset: () => cache.clear() };
}
