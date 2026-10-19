// SPDX-License-Identifier: AGPL-3.0-or-later
// Native WLoc control endpoint, synthesized entirely inside Surge.
(function () {
  "use strict";
  var marker = "wloc-native-v2", storeKey = "wloc_native_target_v2";
  function reply(status, payload) {
    payload.bridge = marker;
    $done({ response: { status: status, headers: {
      "Content-Type": "application/json", "Cache-Control": "no-store", "X-WLoc-Bridge": marker
    }, body: JSON.stringify(payload) } });
  }
  function valid(c) {
    return c && typeof c.enabled === "boolean" && typeof c.latitude === "number" && typeof c.longitude === "number" &&
      isFinite(c.latitude) && isFinite(c.longitude) && Math.abs(c.latitude) <= 90 && Math.abs(c.longitude) <= 180 &&
      typeof c.horizontalAccuracy === "number" && isFinite(c.horizontalAccuracy) && c.horizontalAccuracy >= 1;
  }
  function read() {
    try { var c = JSON.parse($persistentStore.read(storeKey)); if (valid(c)) return c; } catch (_) {}
    return { enabled: false, latitude: 0, longitude: 0, horizontalAccuracy: 39 };
  }
  var route = String($request.url || "").split("?")[0].split("/").pop();
  var method = String($request.method || "GET").toUpperCase();
  if (route === "health" && method === "GET") { reply(200, {}); return; }
  var argument = String(typeof $argument === "undefined" ? "" : $argument);
  var expected = argument.indexOf("key=") === 0 ? argument.slice(4) : "";
  if (!/^[A-Za-z0-9]{16,128}$/.test(expected)) { reply(503, { error: "Set module key argument first" }); return; }
  var headers = $request.headers || {}, supplied = "";
  Object.keys(headers).forEach(function (key) { if (key.toLowerCase() === "x-wloc-key") supplied = String(headers[key]); });
  var diff = supplied.length ^ expected.length;
  for (var i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ (supplied.charCodeAt(i) || 0);
  if (diff !== 0) { reply(403, { error: "Pairing key mismatch" }); return; }
  if (route === "config" && method === "GET") { reply(200, read()); return; }
  if (method !== "POST" || (route !== "config" && route !== "disable")) { reply(404, { error: "Unknown endpoint" }); return; }
  var value;
  if (route === "disable") { value = read(); value.enabled = false; }
  else {
    var body = String($request.body || "");
    if (body.length > 16384) { reply(413, { error: "Body too large" }); return; }
    try { value = JSON.parse(body); } catch (_) { reply(400, { error: "Invalid JSON" }); return; }
    if (!valid(value)) { reply(400, { error: "Invalid coordinates" }); return; }
    value = { enabled: value.enabled, latitude: value.latitude, longitude: value.longitude,
      horizontalAccuracy: Math.round(value.horizontalAccuracy) };
  }
  if (!$persistentStore.write(JSON.stringify(value), storeKey)) { reply(500, { error: "Storage unavailable" }); return; }
  reply(200, value);
})();
