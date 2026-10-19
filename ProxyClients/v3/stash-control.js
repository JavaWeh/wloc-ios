// SPDX-License-Identifier: AGPL-3.0-or-later
// Generated per-client with build_proxy_clients.py. The installed rule MUST
// match the exact per-device key path, never a wildcard credential path.
(function () {
  "use strict";
  var client = "stash", marker = "wloc-native-v3", storeKey = "wloc_native_target_v2";
  var qx = client === "quantumultX";
  var store = qx ? {
    read: function (key) { return $prefs.valueForKey(key); },
    write: function (value, key) { return $prefs.setValueForKey(value, key); }
  } : $persistentStore;
  function reply(status, payload) {
    payload.bridge = marker;
    payload.client = client;
    var response = {status: status, headers: {
      "Content-Type": "application/json", "Cache-Control": "no-store", "X-WLoc-Bridge": marker
    }, body: JSON.stringify(payload)};
    if (qx) {
      var reasons = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 500: "Internal Server Error"};
      response.status = "HTTP/1.1 " + status + " " + (reasons[status] || "Error");
      $done(response);
    } else { $done({response: response}); }
  }
  function valid(c) {
    return c && typeof c.enabled === "boolean" && typeof c.latitude === "number" && typeof c.longitude === "number" &&
      isFinite(c.latitude) && isFinite(c.longitude) && Math.abs(c.latitude) <= 90 && Math.abs(c.longitude) <= 180 &&
      typeof c.horizontalAccuracy === "number" && isFinite(c.horizontalAccuracy) && c.horizontalAccuracy >= 1 && c.horizontalAccuracy <= 1000000;
  }
  function read() {
    try { var value = JSON.parse(store.read(storeKey)); if (valid(value)) return value; } catch (_) {}
    return {enabled: false, latitude: 0, longitude: 0, horizontalAccuracy: 39};
  }
  var url = String($request.url || ""), method = String($request.method || "GET").toUpperCase();
  if (url === "https://gs-loc.apple.com/wloc-native/v3/health") {
    reply(method === "GET" ? 200 : 405, {}); return;
  }
  var match = url.match(/^https:\/\/gs-loc\.apple\.com\/wloc-native\/v3\/([A-Za-z0-9]{16,128})\/(config|disable|status)$/);
  if (!match) { reply(404, {}); return; }
  var supplied = "", headers = $request.headers || {};
  Object.keys(headers).forEach(function (key) { if (key.toLowerCase() === "x-wloc-key") supplied = String(headers[key]); });
  // The exact installed URL rule authenticates the path; the header must agree.
  var expected = match[1], diff = expected.length ^ supplied.length;
  for (var i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ (supplied.charCodeAt(i) || 0);
  if (diff !== 0) { reply(403, {}); return; }
  var route = match[2];
  if ((route === "config" || (qx && route === "status")) && method === "GET") { reply(200, read()); return; }
  if (route === "status") { reply(405, {}); return; }
  if (method !== "POST") { reply(405, {}); return; }
  var value;
  if (route === "disable") { value = read(); value.enabled = false; }
  else {
    var body = $request.body;
    if (body == null && $request.bodyBytes) {
      var bytes = new Uint8Array($request.bodyBytes);
      if (bytes.length > 16384) { reply(413, {}); return; }
      body = "";
      for (var j = 0; j < bytes.length; j++) body += String.fromCharCode(bytes[j]);
    }
    body = String(body || "");
    if (body.length > 16384) { reply(413, {}); return; }
    try { value = JSON.parse(body); } catch (_) { reply(400, {}); return; }
    if (!valid(value)) { reply(400, {}); return; }
    value = {enabled: value.enabled, latitude: value.latitude, longitude: value.longitude, horizontalAccuracy: Math.round(value.horizontalAccuracy)};
  }
  try {
    if (!store.write(JSON.stringify(value), storeKey)) { reply(500, {}); return; }
  } catch (_) { reply(500, {}); return; }
  reply(200, value);
})();
