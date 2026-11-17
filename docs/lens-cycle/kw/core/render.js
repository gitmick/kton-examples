/**
 * A rendered document and how it came about: the render verticle's viewer model.
 *
 * Like the feed, it does not read the registry. The render package's queries answer, through
 * `cockpit ask` (trusted keys only), and the viewer arranges what they say:
 *
 *   document   render-document   the document, the run (foton) that made it, protocol, environment, signer
 *   inputs     render-inputs     what that run used - source, template, command file - and who made those
 *   claims     render-claims     what trusted keys said about the document or the run (approved, ...)
 *
 * The bytes of the document are not in the graph. The host hands them over as a URL (files.document),
 * and the source too if it wants it shown (files.source); the protocol descriptor likewise
 * (files.protocol), because the image a run used sits in its descriptor, which the graph does not carry.
 * For answers holding several documents, files.docs maps each document's hex to its own such files.
 */
import { rows } from "./feed.js";

export { rows };

/** https://kton.dev/o/<hex> -> sha256:<hex>; anything else unchanged. */
export function hashOf(iri) {
    const m = /\/o\/([0-9a-f]{64})$/.exec(iri || "");
    return m ? "sha256:" + m[1] : iri || "";
}
export const short = (h) => (h || "").replace(/^sha256:/, "").slice(0, 12);
const tail = (iri) => (iri || "").split("/").pop();

/**
 * What an input was to the run, by its path: a render step names its slots (source.md, template.docx,
 * render.sh), so the path says it. Anything unrecognised is just an input - never guessed into a role.
 */
export function roleOf(path) {
    const p = (path || "").toLowerCase(), base = p.split("/").pop();
    if (/(^|[-_.])template([-_.]|$)|\.(dotx|potx)$|reference\.docx$/.test(base)) return "template";
    if (/\.(sh|bash|ps1|py|r)$/.test(base) || /^(command|render)([-_.]|$)/.test(base)) return "command";
    if (/(^|[-_.])source([-_.]|$)|\.(md|qmd|rmd|markdown|rst|tex|txt)$/.test(base)) return "source";
    return "input";
}
const ORDER = { source: 0, template: 1, command: 2, input: 3 };

/** The format of a document by its path; decides how the preview shows it. */
export function formatOf(path) {
    const ext = ((path || "").toLowerCase().match(/\.([a-z0-9]+)$/) || [])[1] || "";
    if (ext === "pdf") return "pdf";
    if (["html", "htm"].includes(ext)) return "html";
    if (["md", "txt", "csv", "json", "rq", "tex", "rst"].includes(ext)) return "text";
    if (["png", "jpg", "jpeg", "gif", "svg", "webp"].includes(ext)) return "image";
    return ext || "unknown";        // docx, pptx, ...: no in-page preview, the host opens it
}

/**
 * The image a run used, from its protocol descriptor: a script's envRef ("oci://<image>@sha256:<digest>",
 * as a foton records it) or a command's first argument ("<image>@sha256:<digest>\n..."). Only a
 * pinned image counts.
 */
export function imageOf(protocol) {
    const p = protocol?.protocol ?? protocol, d = p?.descriptor ?? p;
    const args = d?.command?.args ?? d?.args;
    const first = d?.envRef || (typeof args === "string" ? args.split("\n")[0] : Array.isArray(args) ? args[0] : "");
    const img = String(first || "").replace(/^oci:\/\//, "");
    return /@sha256:[0-9a-f]{64}$/.test(img) ? img : "";
}

/**
 * The run that made a document: of the fotons the merged graph says generated it, the one that did
 * not also use it - a later step that passes a file through (a pdf step next to its docx) did not make it.
 */
function maker(drows, inputs) {
    const used = new Set(rows(inputs).filter((r) => r.input === drows[0].doc).map((r) => r.foton));
    return (drows.find((r) => !used.has(r.foton)) || drows[0]).foton;
}

/**
 * The documents the answers hold, for a picker: each once, by the run that made it, with its paths.
 * A file only passed through a run (used and "generated" by the same foton, never made by another)
 * is left out. Title and time come from the host (files.docs[hex].title, .when), if it has them.
 */
export function documentsOf({ document, inputs, files } = {}) {
    const by = new Map();
    for (const r of rows(document)) { if (!by.has(r.doc)) by.set(r.doc, []); by.get(r.doc).push(r); }
    const usedBy = new Map();
    for (const r of rows(inputs)) { if (!usedBy.has(r.input)) usedBy.set(r.input, new Set()); usedBy.get(r.input).add(r.foton); }
    const out = [];
    for (const [iri, rs] of by) {
        const made = rs.filter((r) => !usedBy.get(iri)?.has(r.foton));
        if (!made.length) continue;
        const foton = made[0].foton, hex = tail(iri);
        const paths = [...new Set(made.filter((r) => r.foton === foton).map((r) => r.path).filter(Boolean))];
        out.push({ hash: hashOf(iri), hex, foton: hashOf(foton), path: paths[0] || "", format: formatOf(paths[0]),
                   title: files?.docs?.[hex]?.title || "", when: files?.docs?.[hex]?.when || "" });
    }
    // by title, the newest rendering first, pdf before docx
    return out.sort((a, b) => (a.title || a.path).localeCompare(b.title || b.path) || (b.when || "").localeCompare(a.when || "")
        || a.format.localeCompare(b.format));
}

/**
 * Join the answers into one model. Rows for several documents may come in (a host that ran the
 * queries unbound); `doc` picks one, the newest-listed otherwise.
 *   { doc: {hash, path, paths, format}, run: {hash, kind, protocol, environment, signer, verified,
 *     conditional, image}, inputs: [{hash, paths, role, madeBy}], claims: [...], missing: [...] }
 */
export function buildRender({ document, inputs, claims, protocol } = {}, doc = "") {
    const want = (doc || "").replace(/^sha256:/, "");
    const drows = rows(document).filter((r) => !want || tail(r.doc) === want);
    const missing = [];
    if (!drows.length) return { doc: null, run: null, inputs: [], claims: [], missing: ["document"] };

    const foton = maker(drows, inputs), d = drows.find((r) => r.foton === foton);
    const run = {
        hash: hashOf(d.foton), kind: d.kind || "", protocol: hashOf(d.protocol), environment: hashOf(d.environment),
        signer: d.signerName || (d.signer ? tail(d.signer) : ""), verified: d.verified === "true" || d.verified === true,
        conditional: d.conditional === "true" || d.conditional === true, image: imageOf(protocol),
    };
    const paths = [...new Set(drows.filter((r) => r.foton === d.foton).map((r) => r.path).filter(Boolean))];
    const out = { doc: { hash: hashOf(d.doc), path: paths[0] || "", paths, format: formatOf(paths[0]) }, run };

    // one entry per input hash: the default graph merges every run's paths for the same bytes, so
    // a file may carry several names - keep them all, show the first
    const ins = new Map();
    for (const r of rows(inputs)) {
        if (r.foton && r.foton !== d.foton) continue;
        const h = hashOf(r.input);
        if (!ins.has(h)) ins.set(h, { hash: h, paths: [], madeBy: "" });
        const e = ins.get(h);
        if (r.path && !e.paths.includes(r.path)) e.paths.push(r.path);
        if (r.madeBy) e.madeBy = hashOf(r.madeBy);
    }
    out.inputs = [...ins.values()].map((e) => ({ ...e, role: e.paths.map(roleOf).sort((a, b) => ORDER[a] - ORDER[b])[0] || "input" }))
        .sort((a, b) => ORDER[a.role] - ORDER[b.role] || (a.paths[0] || "").localeCompare(b.paths[0] || ""));
    if (!out.inputs.length) missing.push("inputs");

    out.claims = rows(claims).filter((c) => !c.doc || c.doc === d.doc).map((c) => ({
        id: hashOf(c.claim), on: c.on || "", predicate: tail(c.predicate), title: c.title || "", text: c.text || "",
        why: c.why || "", outcome: c.outcome || "", signer: (c.signer || "").replace(/^lane-/, "").replace(/-claims$/, ""), when: c.when || "",
    })).sort((a, b) => (a.when < b.when ? 1 : -1));
    if (!run.image) missing.push("image");
    out.missing = missing;
    return out;
}
