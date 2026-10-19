const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const api = require('../Surge/vendor/location-spoofer.upstream.js');
const responseSource = fs.readFileSync(path.join(root, 'ProxyClients/v3/response.js'), 'utf8');
const prepareSource = fs.readFileSync(path.join(root, 'ProxyClients/v3/prepare.js'), 'utf8');
// Fixture-only credential, never a user's key.
const key = '0123456789abcdef0123456789abcdef';
const base = 'https://gs-loc.apple.com/wloc-native/v3/';
const target = {enabled: true, latitude: -33.86, longitude: 151.2, horizontalAccuracy: 39};
if (process.argv.includes('--fixtures')) {
  const fixtures = JSON.parse(fs.readFileSync(path.join(root, 'build/install-fixtures/configurations.json'), 'utf8'));
  assert.equal(fixtures.length, 5);
  for (const fixture of fixtures) {
    const patterns = fixture.patterns.map(pattern => {assert(fixture.content.includes(pattern)); return new RegExp(pattern);});
    const matches = url => patterns.some(pattern => pattern.test(url));
    assert(matches(base + key + '/config'));
    assert(matches(base + 'health'));
    assert(!matches(base + 'f'.repeat(32) + '/config'));
    assert(!matches(base + key + '/config?extra=1'));
    assert(!fixture.content.includes('127.0.0.1'));
  }
  console.log('Swift-generated configuration patterns: exact key authorization PASS');
}
function fixture() {
  const location = api.concatBytes([api.makeVarintField(1, api.coordToInt(10)), api.makeVarintField(2, api.coordToInt(20)), api.makeVarintField(3, 25)]);
  const wifi = api.concatBytes([api.makeLengthDelimitedField(1, api.binaryStringToBytes('00:11:22:33:44:55')), api.makeLengthDelimitedField(2, location)]);
  return api.buildAppleWLocResponse(api.concatBytes([api.makeLengthDelimitedField(2, wifi)]));
}
for (const client of ['surge', 'loon', 'stash', 'quantumultX', 'shadowrocket']) {
  const qx = client === 'quantumultX', storage = new Map();
  let writable = true;
  const persistent = {read: k => storage.get(k) || null, write: (v, k) => {if (!writable) return false; storage.set(k, v); return true;}};
  const globals = {Uint8Array, ArrayBuffer, console: {log() {throw Error('Do not log coordinates or credentials');}}};
  if (qx) { globals.$prefs = {valueForKey: persistent.read, setValueForKey: persistent.write}; globals.$task = {fetch() {throw Error('No remote configuration');}}; }
  else {globals.$persistentStore = persistent; globals.$environment = {product: client === 'surge' ? 'Surge' : client};}
  if (client === 'loon') globals.$loon = {};
  globals.$httpClient = {get() {throw Error('No remote configuration');}};
  const control = fs.readFileSync(path.join(root, `ProxyClients/v3/${client}-control.js`), 'utf8');
  function request(route, method = 'GET', body, header = key, pathKey = key, bytes = false) {
    const url = base + (route === 'health' ? 'health' : pathKey + '/' + route);
    // Model the EXACT key match emitted by InstallConfiguration; a wrong path
    // must never reach the publicly available, key-independent control script.
    if (route !== 'health' && pathKey !== key) return {status: 404};
    let value, count = 0;
    const req = {url, method, headers: {'X-WLoc-Key': header}};
    if (body !== undefined) {
      const text = typeof body === 'string' ? body : JSON.stringify(body);
      if (bytes) req.bodyBytes = Uint8Array.from(Buffer.from(text)).buffer; else req.body = text;
    }
    vm.runInNewContext(control, {...globals, $request: req, $done(r) {count++; value = qx ? r : r.response;}});
    assert.equal(count, 1);
    return {status: qx ? Number(value.status.split(' ')[1]) : value.status, data: JSON.parse(value.body)};
  }
  function rewrite(payload = fixture()) {
    let result, count = 0;
    const response = qx ? {bodyBytes: payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength), headers: {}} : {body: payload, headers: {}, status: 200};
    vm.runInNewContext(responseSource, {...globals, $request: {url: 'https://gs-loc.apple.com/clls/wloc', method: 'POST', headers: {}},
      $response: response, $done(r) {result = r; count++;}});
    assert.equal(count, 1);
    return qx ? result.bodyBytes : result.body;
  }
  assert.equal(request('health', 'GET', undefined, '').data.client, client);
  assert.equal(request('health', 'POST').status, 405);
  assert.equal(request('config', 'GET', undefined, 'wrong').status, 403);
  assert.equal(request('config', 'POST', target, 'wrong', 'f'.repeat(32)).status, 404);
  assert.equal(request('config').data.enabled, false);
  if (qx) assert.equal(request('status').data.enabled, false);
  assert.equal(rewrite(), undefined);
  assert.equal(request('config', 'POST', target, key, key, qx).status, 200);
  const binary = rewrite();
  assert(binary, `${client} must rewrite binary WLOC`);
  if (qx) assert.equal(Object.prototype.toString.call(binary), '[object ArrayBuffer]');
  const summary = api.patchedPayloadSummary(api.extractAppleWLocPayload(api.bodyToBytes(binary)).payload);
  const coordinates = summary.match(/firstWifi=([\d.-]+),([\d.-]+)/);
  assert(coordinates, summary);
  assert(Math.abs(Number(coordinates[1]) - target.latitude) < 2e-8);
  assert(Math.abs(Number(coordinates[2]) - target.longitude) < 2e-8);
  assert.equal(request('config', 'POST', {...target, latitude: 91}).status, 400);
  assert.equal(request('config', 'POST', {...target, horizontalAccuracy: 1e300}).status, 400);
  assert.equal(request('config', 'POST', '{broken').status, 400);
  assert.equal(request('config', 'POST', ' '.repeat(16385)).status, 413);
  assert.equal(request('config').data.latitude, target.latitude);
  assert.equal(request('disable', 'POST', {}).data.enabled, false);
  assert.equal(rewrite(), undefined);
  for (const invalid of ['{bad', JSON.stringify({...target, horizontalAccuracy: 1e300})]) {
    storage.set('wloc_native_target_v2', invalid); assert.equal(rewrite(), undefined);
  }
  writable = false;
  assert.equal(request('config', 'POST', target).status, 500);
  let prepared;
  vm.runInNewContext(prepareSource, {$request: {headers: {'accept-encoding': 'gzip', 'Other': 'kept'}}, $done(r) {prepared = r;}});
  assert.deepEqual(Object.keys(prepared.headers).sort(), ['Accept-Encoding', 'Other']);
  assert.equal(prepared.headers['Accept-Encoding'], 'identity');
  console.log(`${client}: control authentication, storage, binary rewrite, disable and passthrough PASS`);
}
