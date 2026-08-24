/* bonfire-lens.js - loads the lens into a Bonfire instance.
 *
 * Injected into every Bonfire HTML page by the kton-web proxy, which also serves the lens assets
 * and the bridge from the SAME origin - so there is no CORS anywhere and no second port.
 *
 * Two things make Bonfire different from the static demo page:
 *
 *   1. It is a LiveView app. The DOM is patched over a websocket long after DOMContentLoaded, so a
 *      one-shot scan at load would badge the first feed render and nothing afterwards. A
 *      MutationObserver re-scans (debounced) whenever images appear.
 *
 *   2. Not every <img> is a figure. Avatars, banners and emoji are uploads too. Bonfire files them
 *      under distinct prefixes (bonfire_files definitions: images / icons / banners / docs /
 *      emoji / videos), so the selector targets `/images/` and `/docs/` and leaves faces alone.
 *
 * A figure only gets a badge if the instance registry knows its bytes. Note that Bonfire RESIZES
 * and re-encodes uploaded images (Bonfire.Files.ImageUploader, max_width 580, everything except
 * GIF), so the served bytes are a derivative of what was uploaded - register the upload as a foton
 * with stack/register-figure.sh and the badge resolves through that transformation to the original.
 */
(function () {
  "use strict";
  var S = document.currentScript;
  var BRIDGE = (S.getAttribute("data-bridge") || "/kton-api").replace(/\/$/, "");
  var ASSETS = (S.getAttribute("data-assets") || "/kton-assets").replace(/\/$/, "");

  // Bonfire's own upload paths. `/images/` is post/article figures; `/docs/` is any non-image
  // attachment, which is the case where the bytes survive upload untouched.
  var SELECTOR = 'img[src*="/data/uploads/"][src*="/images/"],' +
                 'img[src*="/data/uploads/"][src*="/docs/"],' +
                 'img.lens,img[data-kton]';

  function load(src, attrs) {
    return new Promise(function (res, rej) {
      var s = document.createElement("script");
      s.src = src;
      Object.keys(attrs || {}).forEach(function (k) { s.setAttribute(k, attrs[k]); });
      s.onload = res;
      s.onerror = function () { rej(new Error("could not load " + src)); };
      document.body.appendChild(s);
    });
  }

  async function boot() {
    // The sign half first: lens.js only renders the ✎ button if window.ktonSign already exists.
    var cfg = null;
    try { cfg = await (await fetch(ASSETS + "/lens-client.json", { cache: "no-store" })).json(); } catch (e) {}
    if (cfg && cfg.client_id) {
      await load(ASSETS + "/lens-sign.js", {
        "data-bridge": BRIDGE,
        "data-issuer": cfg.issuer,
        "data-client-id": cfg.client_id,
        "data-wasm": ASSETS + "/graph.wasm",
        "data-wasm-exec": ASSETS + "/wasm_exec.js",
      });
    }

    await load(ASSETS + "/lens.js", {
      "data-planktons": BRIDGE + "/kton/union.json",
      "data-viewer": ASSETS + "/viewer.html",
      "data-logo": ASSETS + "/logo.png",
      "data-selector": SELECTOR,
    });

    watch();
  }

  // Re-scan when LiveView patches new images in. Debounced because a single feed render fires
  // many mutations, and each scan re-fetches the union.
  function watch() {
    if (!window.MutationObserver || !window.ktonLens) return;
    var timer = null;
    new MutationObserver(function (records) {
      var sawImage = records.some(function (r) {
        return [].some.call(r.addedNodes, function (n) {
          return n.nodeType === 1 && (n.matches && n.matches(SELECTOR) || n.querySelector && n.querySelector(SELECTOR));
        });
      });
      if (!sawImage) return;
      clearTimeout(timer);
      timer = setTimeout(function () { window.ktonLens.scan(); }, 250);
    }).observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
