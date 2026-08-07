/* lens-sign.js - the WRITE half of the lens: sign a claim about a figure, in the browser.
 *
 * lens.js answers "where did this come from?". This answers "and I, personally, vouch for it."
 *
 * The three-part split is the whole design:
 *   - your identity comes from Bonfire (which may itself have brokered it from ORCID / Keycloak /
 *     GitHub / Google) via an OAuth2 authorization-code + PKCE flow - a public client, no secret;
 *   - your KEY is generated here with `extractable: false` and lives in IndexedDB. It cannot be
 *     read back out, exported, or exfiltrated by any script on the page - not even this one;
 *   - the BINDING between the two is a `sec:controller` claim signed by the instance (the bridge),
 *     which is the mechanism kton-examples example 07 already defines. A key is an identity; an
 *     authority vouches for whose it is. We add no new crypto.
 *
 * The claim payload is canonicalized and framed by the kton WASM kernel (plktBuildClaim /
 * plktSealClaim), so a claim signed here is byte-identical to the same claim signed by the
 * `nekton` CLI - same bytes, same claim id, dedupes correctly in a federated union.
 *
 *   <script src="lens-sign.js"
 *           data-bridge="http://localhost:8789"
 *           data-bonfire="http://localhost:4000"
 *           data-client-id="...."></script>
 *
 * Load it AFTER lens.js. lens.js calls window.ktonSign.attach() if this file is present, so the
 * read-only lens keeps working unchanged when it is not.
 */
(function () {
  "use strict";
  var S = document.currentScript;
  var CFG = {
    bridge: (S.getAttribute("data-bridge") || "").replace(/\/$/, ""),
    bonfire: (S.getAttribute("data-bonfire") || "").replace(/\/$/, ""),
    clientId: S.getAttribute("data-client-id") || "",
    wasm: S.getAttribute("data-wasm") || "graph.wasm",
    wasmExec: S.getAttribute("data-wasm-exec") || "wasm_exec.js",
    // pav:reviewedBy - a PUBLISHED term. kton's vocabulary policy is to reuse an existing ontology
    // wherever one fits and mint nk: terms only for what none covers; gxp: terms are reserved for
    // actually GxP-validated processes and must never be used for ordinary review.
    predicate: S.getAttribute("data-predicate") || "http://purl.org/pav/reviewedBy",
  };

  /* ---------- tiny helpers ---------------------------------------------------------------- */
  function hex(buf) { return [].map.call(new Uint8Array(buf), function (b) { return b.toString(16).padStart(2, "0"); }).join(""); }
  function b64(buf) { var s = ""; new Uint8Array(buf).forEach(function (b) { s += String.fromCharCode(b); }); return btoa(s); }
  function b64ToBytes(b) { var s = atob(b), a = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i); return a; }
  function b64url(buf) { return b64(buf).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }
  function rand(n) { var a = new Uint8Array(n); crypto.getRandomValues(a); return a; }

  /* ---------- 1. identity: OAuth2 authorization-code + PKCE against Bonfire ----------------
   * PKCE with a PUBLIC client (token_endpoint_auth_method=none) is what lets a static page do
   * this at all: there is no client secret to hide, and the code is useless without the verifier
   * that never left this browser.
   */
  var TOKEN_KEY = "kton-access-token", VERIFIER_KEY = "kton-pkce-verifier";

  function token() { try { return sessionStorage.getItem(TOKEN_KEY) || ""; } catch (e) { return ""; } }

  async function login() {
    if (!CFG.bonfire || !CFG.clientId) throw new Error("no data-bonfire / data-client-id configured");
    var verifier = b64url(rand(32));
    sessionStorage.setItem(VERIFIER_KEY, verifier);
    var challenge = b64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
    var q = new URLSearchParams({
      response_type: "code",
      client_id: CFG.clientId,
      redirect_uri: redirectUri(),
      scope: "openid profile",
      code_challenge: challenge,
      code_challenge_method: "S256",
    });
    location.href = CFG.bonfire + "/openid/authorize?" + q.toString();
  }

  // The redirect target must match what was registered EXACTLY, so strip query/hash.
  function redirectUri() { return location.origin + location.pathname; }

  // Called on load: if we came back from Bonfire with ?code=, trade it for an access token.
  async function completeLogin() {
    var p = new URLSearchParams(location.search);
    var code = p.get("code");
    if (!code) return false;
    var verifier = sessionStorage.getItem(VERIFIER_KEY) || "";
    // Clean the URL first, so a refresh cannot replay a spent code.
    history.replaceState({}, "", redirectUri());
    sessionStorage.removeItem(VERIFIER_KEY);
    var body = new URLSearchParams({
      grant_type: "authorization_code",
      code: code,
      client_id: CFG.clientId,
      redirect_uri: redirectUri(),
      code_verifier: verifier,
    });
    var r = await fetch(CFG.bonfire + "/openid/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    if (!r.ok) throw new Error("token exchange failed (HTTP " + r.status + "): " + (await r.text()).slice(0, 200));
    var j = await r.json();
    if (!j.access_token) throw new Error("no access_token in the token response");
    sessionStorage.setItem(TOKEN_KEY, j.access_token);
    return true;
  }

  /* ---------- 2. the key: non-extractable Ed25519 in IndexedDB ------------------------------ */
  var DB = "kton-lens", STORE = "identity";

  function idb() {
    return new Promise(function (res, rej) {
      var rq = indexedDB.open(DB, 1);
      rq.onupgradeneeded = function () { rq.result.createObjectStore(STORE); };
      rq.onsuccess = function () { res(rq.result); };
      rq.onerror = function () { rej(rq.error); };
    });
  }
  function idbGet(k) {
    return idb().then(function (db) {
      return new Promise(function (res, rej) {
        var rq = db.transaction(STORE, "readonly").objectStore(STORE).get(k);
        rq.onsuccess = function () { res(rq.result); };
        rq.onerror = function () { rej(rq.error); };
      });
    });
  }
  function idbPut(k, v) {
    return idb().then(function (db) {
      return new Promise(function (res, rej) {
        var tx = db.transaction(STORE, "readwrite");
        tx.objectStore(STORE).put(v, k);
        tx.oncomplete = function () { res(); };
        tx.onerror = function () { rej(tx.error); };
      });
    });
  }

  function ed25519Supported() {
    // Feature-detect properly at call time; a stale UA string proves nothing.
    return crypto.subtle && typeof crypto.subtle.generateKey === "function";
  }

  // ensureIdentity returns {privateKey, pubHex, principal, label}, creating and REGISTERING the
  // key on first use. Registration is what makes the key mean something: the bridge signs a
  // sec:controller claim binding it to whoever the access token says you are.
  async function ensureIdentity() {
    var saved = await idbGet("signing");
    if (saved && saved.privateKey && saved.principal) return saved;

    var pair;
    try {
      // extractable:false - the private key can never be exported, by us or by anything else.
      pair = await crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign", "verify"]);
    } catch (e) {
      throw new Error("this browser has no WebCrypto Ed25519, so it cannot sign here");
    }
    var pubHex = hex(await crypto.subtle.exportKey("raw", pair.publicKey));

    var r = await fetch(CFG.bridge + "/keys", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + token() },
      body: JSON.stringify({ pubHex: pubHex }),
    });
    if (!r.ok) throw new Error("key registration refused: " + (await r.text()).slice(0, 200));
    var reg = await r.json();

    var ident = { privateKey: pair.privateKey, pubHex: pubHex, principal: reg.principal, label: reg.label };
    await idbPut("signing", ident);
    return ident;
  }

  /* ---------- 3. the kernel: load graph.wasm lazily ---------------------------------------- */
  var wasmReady = null;
  function loadWasm() {
    if (wasmReady) return wasmReady;
    // ~3 MB: only ever fetched when someone actually chooses to sign, never on page load.
    wasmReady = new Promise(function (res, rej) {
      var s = document.createElement("script");
      s.src = CFG.wasmExec;
      s.onload = async function () {
        try {
          var go = new Go();
          var r = await WebAssembly.instantiateStreaming(fetch(CFG.wasm), go.importObject);
          go.run(r.instance);                     // never resolves by design; the module stays alive
          // give the module a tick to install its globals
          setTimeout(function () { window.plktBuildClaim ? res() : rej(new Error("the WASM kernel did not export plktBuildClaim - is graph.wasm current?")); }, 0);
        } catch (e) { rej(e); }
      };
      s.onerror = function () { rej(new Error("could not load " + CFG.wasmExec)); };
      document.head.appendChild(s);
    });
    return wasmReady;
  }

  /* ---------- 4. sign ---------------------------------------------------------------------- */
  async function signClaim(hash, why) {
    await loadWasm();
    var ident = await ensureIdentity();

    var spec = {
      subject: [{ hash: hash }],
      predicate: CFG.predicate,
      object: { id: ident.principal },
      by: ident.principal,
      when: new Date().toISOString().replace(/\.\d+Z$/, "Z"),  // RFC 3339, whole seconds
    };
    if (why) spec.why = why;

    var built = window.plktBuildClaim(JSON.stringify(spec));
    if (built.error) throw new Error(built.error);

    // The one operation the kernel does NOT do: the raw signature, made by WebCrypto over a key
    // Go never sees.
    var sig = await crypto.subtle.sign({ name: "Ed25519" }, ident.privateKey, b64ToBytes(built.toSign));

    var sealed = window.plktSealClaim(built.payload, b64(sig), ident.pubHex);
    if (sealed.error) throw new Error(sealed.error);

    var r = await fetch(CFG.bridge + "/claims", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + token() },
      body: sealed.record,
    });
    if (!r.ok) throw new Error("the instance refused the claim: " + (await r.text()).slice(0, 200));
    return Object.assign(await r.json(), { principal: ident.principal, label: ident.label });
  }

  /* ---------- 5. the affordance ------------------------------------------------------------ */
  var CSS = "\
.lens-sign{position:absolute;right:44px;bottom:8px;width:30px;height:30px;border-radius:50%;\
  background:#fff;box-shadow:0 1px 5px rgba(0,0,0,.28);border:2px solid #3a45cf;color:#3a45cf;\
  cursor:pointer;font:700 15px/26px ui-sans-serif,system-ui,sans-serif;text-align:center;padding:0;z-index:2}\
.lens-sign:hover{transform:scale(1.12)}\
.lens-sign[disabled]{opacity:.5;cursor:progress}\
.lens-signed{border-color:#12b886;color:#12b886}\
.lens-say{position:fixed;inset:0;z-index:100000;background:rgba(10,14,22,.62);display:flex;align-items:center;justify-content:center}\
.lens-say .box{background:#141922;color:#e8ebf2;border-radius:14px;padding:20px;width:min(460px,92vw);\
  font:13px/1.55 ui-sans-serif,system-ui,sans-serif;box-shadow:0 18px 60px rgba(0,0,0,.55)}\
.lens-say h3{margin:0 0 6px;font-size:15px}\
.lens-say code{font:11px ui-monospace,Menlo,monospace;color:#98a1b2;word-break:break-all}\
.lens-say textarea{width:100%;margin:12px 0;background:#0f131a;color:#e8ebf2;border:1px solid #2a3140;\
  border-radius:8px;padding:9px;font:13px ui-sans-serif,system-ui,sans-serif;resize:vertical;min-height:64px}\
.lens-say .row{display:flex;gap:9px;justify-content:flex-end}\
.lens-say button{all:unset;cursor:pointer;border-radius:8px;padding:7px 15px;font:600 12px ui-sans-serif,system-ui,sans-serif}\
.lens-say .go{background:#3a45cf;color:#fff} .lens-say .no{background:rgba(255,255,255,.13);color:#e8ebf2}\
.lens-say .err{color:#ff8785;margin-top:9px} .lens-say .ok{color:#4fd39a;margin-top:9px}\
.lens-say .who{color:#98a1b2;margin-top:2px}\
";
  var injected = false;
  function inject() { if (injected) return; injected = true; var s = document.createElement("style"); s.textContent = CSS; document.head.appendChild(s); }

  function dialog(hash, onDone) {
    var ov = document.createElement("div"); ov.className = "lens-say";
    ov.innerHTML =
      '<div class="box"><h3>Sign a claim about this figure</h3>' +
      '<code>' + hash + '</code>' +
      '<div class="who">Signed in your browser with a key only you hold, as ' +
      (token() ? "your signed-in identity" : "— you will be asked to sign in first") + '.</div>' +
      '<textarea placeholder="Optionally, why? (e.g. checked against the source data)"></textarea>' +
      '<div class="row"><button class="no">Cancel</button><button class="go">Sign</button></div>' +
      '<div class="msg"></div></div>';
    var msg = ov.querySelector(".msg"), go = ov.querySelector(".go");
    function close() { ov.remove(); document.removeEventListener("keydown", onk); }
    function onk(e) { if (e.key === "Escape") close(); }
    ov.querySelector(".no").onclick = close;
    ov.addEventListener("click", function (e) { if (e.target === ov) close(); });
    document.addEventListener("keydown", onk);
    go.onclick = async function () {
      go.disabled = true; msg.className = "msg"; msg.textContent = "Signing…";
      try {
        if (!token()) { await login(); return; }        // navigates away; we resume after redirect
        var out = await signClaim(hash, ov.querySelector("textarea").value.trim());
        msg.className = "msg ok";
        msg.textContent = "Signed as " + (out.label || out.principal) + " · claim " + out.claimId.slice(0, 19) + "…";
        onDone && onDone(out);
        setTimeout(close, 2200);
      } catch (e) {
        msg.className = "msg err"; msg.textContent = String(e.message || e);
        go.disabled = false;
      }
    };
    document.body.appendChild(ov);
  }

  /* ---------- public surface used by lens.js ------------------------------------------------ */
  window.ktonSign = {
    // available() is checked by lens.js before it renders the button, so a browser without
    // Ed25519 gets NO sign affordance rather than one that fails when pressed.
    available: function () { return !!(CFG.bridge && CFG.bonfire && CFG.clientId && ed25519Supported()); },
    attach: function (wrap, hash) {
      if (!this.available()) return;
      inject();
      var b = document.createElement("button");
      b.className = "lens-sign";
      b.textContent = "✎";
      b.title = "sign a claim about this figure";
      b.setAttribute("aria-label", "sign a claim about this figure");
      b.onclick = function (e) {
        e.stopPropagation();
        dialog(hash, function () { b.className = "lens-sign lens-signed"; b.title = "you have signed a claim about this figure"; });
      };
      wrap.appendChild(b);
    },
  };

  // Resume an interrupted sign-in as soon as we land back on the page.
  if (CFG.clientId) {
    completeLogin().catch(function (e) { console.warn("[lens-sign] " + e.message); });
  }
})();
