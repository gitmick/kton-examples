/**
 * Where a corpus comes from - the one thing core/ops.js does not decide for itself.
 *
 * A source is just `() => Promise<{union, keys, names, sketch}>`. Three of them cover every place
 * this kit runs, and they share one shape so the ops surface never learns which is behind it:
 *
 *   brokerSource   inside a verticle: read through the host's resource:read, over the broker, under
 *                  the audit. The verticle never holds a token and never reaches the network itself.
 *   restSource     from Node (Claude Code, a standalone server): the same REST endpoints the shared
 *                  client uses, Basic auth. For a repo whose security is the network, not a secret.
 *   localSource    a corpus on disk: the fixtures, and anyone testing without an instance.
 *
 * The sketch is chosen per corpus, so it is passed in rather than fetched - a corpus does not know
 * which lens a reader brings, and a source that guessed would be guessing about meaning, which is
 * exactly the thing SPEC 7.1 keeps out of the substrate.
 */

/** Sibling files a union path implies - the same rule the viewers use. */
function siblings(unionPath) {
    const base = String(unionPath).replace(/[^/]*$/, "");
    return { union: unionPath, keys: base + "keys.json", names: base + "names.json" };
}

/**
 * Inside a verticle. `callOp` is `improveHost.callOp` (or the brokered `callOp(handle, op, args)`
 * bound to a session). A missing keys/names file is not an error - it means no verified ring and no
 * attested names, which is a real state, so it degrades to "{}" instead of failing the whole read.
 */
export function brokerSource({ callOp, unionPath, sketch }) {
    const path = siblings(unionPath);
    const read = async (p, fallback) => {
        try { const r = await callOp("resource:read", { path: p });
              return typeof r === "string" ? r : (r && r.content) || fallback; }
        catch { return fallback; }
    };
    return async () => ({
        union: await read(path.union, null).then((u) => { if (!u) throw new Error(`no content at ${path.union}`); return u; }),
        keys: await read(path.keys, "{}"),
        names: await read(path.names, "{}"),
        sketch,
    });
}

/**
 * From Node, straight at the REST API. `resource` may be a PATH ("/pmx/union.json") or the ids from
 * verticle/corpus.json; a path costs one lookup to resolve, an id is direct.
 */
export function restSource({ host, api = "/repository/api/v1", user = "admin", pass = "admin",
                             unionPath, ids, sketch, fetchImpl }) {
    const doFetch = fetchImpl || globalThis.fetch;
    const auth = "Basic " + toBase64(`${user}:${pass}`);
    const base = host + api;

    const call = async (p, opts = {}) => {
        const r = await doFetch(base + p, { ...opts, headers: { Authorization: auth, Accept: "application/json", ...(opts.headers || {}) } });
        const text = await r.text();
        if (!r.ok && r.status !== 304) throw new Error(`${p} -> ${r.status} ${text.slice(0, 160)}`);
        return text;
    };
    const json = async (p) => { const t = await call(p); return t ? JSON.parse(t) : undefined; };

    // resolve a repo path to a resource id by walking the tree - the API is id-addressed
    async function idForPath(path) {
        const parts = path.replace(/^\/+/, "").split("/").filter(Boolean);
        let children = await json("/resources");
        let id = null;
        for (const seg of parts) {
            const hit = (children || []).find((r) => r.name === seg);
            if (!hit) throw new Error(`path not found: ${path} (at "${seg}")`);
            id = hit.resourceId || hit.id;
            children = await json(`/resources/${id}/resources`).catch(() => []);
        }
        return id;
    }

    const contentById = (id) => call(`/resources/${id}/content`);
    const readByPath = async (path, fallback) => {
        try { return await contentById(await idForPath(path)); }
        catch { return fallback; }
    };

    // ids may be keyed by bare name (union) or by filename (union.json) - verticle/corpus.json uses
    // the filenames, because that is what the folder listing calls them
    const pick = (k) => ids && (ids[k] || ids[k + ".json"]);
    return async () => {
        if (pick("union")) {
            return {
                union: await contentById(pick("union")),
                keys: pick("keys") ? await contentById(pick("keys")).catch(() => "{}") : "{}",
                names: pick("names") ? await contentById(pick("names")).catch(() => "{}") : "{}",
                sketch,
            };
        }
        const p = siblings(unionPath);
        const union = await readByPath(p.union, null);
        if (!union) throw new Error(`no content at ${p.union}`);
        return { union, keys: await readByPath(p.keys, "{}"), names: await readByPath(p.names, "{}"), sketch };
    };
}

/** A corpus on disk. `dir` holds union.json + optionally keys/names; `read` is node:fs readFileSync. */
export function localSource({ dir, sketch, read }) {
    const rd = read || ((p) => { throw new Error("localSource: no `read` provided"); });
    const grab = (name, fallback) => { try { return rd(dir.replace(/\/$/, "") + "/" + name); } catch { return fallback; } };
    return async () => {
        const union = grab("union.json", null);
        if (!union) throw new Error(`no union.json in ${dir}`);
        return { union, keys: grab("keys.json", "{}"), names: grab("names.json", "{}"), sketch };
    };
}

function toBase64(s) {
    if (typeof globalThis.Buffer !== "undefined") return globalThis.Buffer.from(s, "utf8").toString("base64");
    return globalThis.btoa(s);
}
