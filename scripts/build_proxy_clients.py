"""Build attributed v3 adapters from the same pinned WLOC core as Surge v2."""
from pathlib import Path
from build_local_spoofer import HOOK

ROOT = Path(__file__).resolve().parents[1]
CLIENTS = ('surge', 'loon', 'stash', 'quantumultX', 'shadowrocket')


def outputs():
    core = (ROOT / 'Surge/vendor/location-spoofer.upstream.js').read_text(encoding='utf-8')
    anchor = '    var configUrl = resolveConfigUrl(args);\n    var debug = parseBoolean(cfg.debug, false);'
    assert core.count(anchor) == 1
    core = core.replace(anchor, HOOK + '\n    cfg.debug = false;\n    var configUrl = "";\n    var debug = false;')
    prefix = '''// SPDX-License-Identifier: AGPL-3.0-or-later
// Derived from mekos2772/ios-location-spoofer, 06feaf2f2279ab966567f946d87ead9461564634.
// WLoc v3: local persistent target; QX storage/binary adapter; no remote config.
// Reproduce with scripts/build_proxy_clients.py. See LICENSE and THIRD_PARTY.md.
(function (nativeStore, nativeDone, nativeResponse, isQX) {
  var $persistentStore = isQX ? {
    read: function (key) { return $prefs.valueForKey(key); },
    write: function (value, key) { return $prefs.setValueForKey(value, key); }
  } : nativeStore;
  var $argument = "mode=response&debug=false";
  var $response = nativeResponse;
  if (isQX) {
    $response = {headers: nativeResponse.headers || {}, status: nativeResponse.statusCode || 200,
      body: nativeResponse.bodyBytes ? new Uint8Array(nativeResponse.bodyBytes) : null};
  }
  var $done = function (value) {
    if (isQX && value && value.body != null) {
      var body = value.body;
      nativeDone({headers: value.headers || {}, bodyBytes: body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)});
    } else { nativeDone(value); }
  };
'''
    suffix = '''
})(typeof $persistentStore === "undefined" ? null : $persistentStore, $done,
   typeof $response === "undefined" ? null : $response, typeof $prefs !== "undefined" && typeof $task !== "undefined");
'''
    control = (ROOT / 'scripts/proxy_control.js').read_text(encoding='utf-8')
    result = {f'{client}-control.js': control.replace('__CLIENT__', client) for client in CLIENTS}
    result['response.js'] = prefix + core + suffix
    result['prepare.js'] = '''// SPDX-License-Identifier: AGPL-3.0-or-later
(function () {
  var headers = {}, original = $request.headers || {};
  Object.keys(original).forEach(function (key) { if (key.toLowerCase() !== "accept-encoding") headers[key] = original[key]; });
  headers["Accept-Encoding"] = "identity";
  $done({headers: headers});
})();
'''
    return result


if __name__ == '__main__':
    folder = ROOT / 'ProxyClients/v3'
    folder.mkdir(parents=True, exist_ok=True)
    for name, content in outputs().items():
        (folder / name).write_text(content, encoding='utf-8', newline='\n')
    print('Generated five v3 control adapters, shared response and prepare scripts')
