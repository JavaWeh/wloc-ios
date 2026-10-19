const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const control = fs.readFileSync(path.join(root, 'Surge/wloc-control.js'), 'utf8');
const responseSource = fs.readFileSync(path.join(root, 'Surge/location-spoofer-local.js'), 'utf8');
const api = require('../Surge/vendor/location-spoofer.upstream.js');
const storage = new Map();
const key = '0123456789abcdef0123456789abcdef';
let writes = true;
const persistent = {read: k => storage.get(k) || null, write: (data, k) => {
  if (!writes) return false;
  storage.set(k, data); return true;
}};
function request(route, method = 'GET', body, supplied = key) {
  let completed = 0, result;
  vm.runInNewContext(control, {
    $request: {url: 'https://gs-loc.apple.com/wloc-native/v1/' + route, method,
      body: body == null ? '' : JSON.stringify(body), headers: {'x-wloc-key': supplied}},
    $argument: 'key=' + key, $persistentStore: persistent,
    $done: value => {completed++; result = value.response;}
  });
  assert.equal(completed, 1, 'Each request must finish exactly once');
  return {status: result.status, data: JSON.parse(result.body)};
}
function fixture() {
  const location = api.concatBytes([api.makeVarintField(1, api.coordToInt(10)), api.makeVarintField(2, api.coordToInt(20)), api.makeVarintField(3, 25)]);
  const wifi = api.concatBytes([api.makeLengthDelimitedField(1, api.binaryStringToBytes('00:11:22:33:44:55')), api.makeLengthDelimitedField(2, location)]);
  return api.buildAppleWLocResponse(api.concatBytes([api.makeLengthDelimitedField(2, wifi)]));
}
function rewrite() {
  let result, doneCount = 0;
  vm.runInNewContext(responseSource, {
    $request: {url: 'https://gs-loc.apple.com/clls/wloc', method: 'POST', headers: {}},
    $response: {body: fixture(), headers: {}}, $argument: 'mode=response',
    $environment: {product: 'Surge'}, $persistentStore: persistent,
    $httpClient: {get: () => {throw Error('Must not fetch any remote configuration');}},
    Uint8Array, ArrayBuffer, console: {log(){}},
    $done: value => {result = value; doneCount++;}
  });
  assert.equal(doneCount, 1);
  return result;
}
assert.equal(request('health', 'GET', null, '').data.bridge, 'wloc-native-v2');
assert.equal(request('config', 'GET', null, 'wrong').status, 403);
assert.equal(request('config').data.enabled, false);
assert.equal(rewrite().body, undefined, 'No target must pass through');
const target = {enabled: true, latitude: -33.86, longitude: 151.2, horizontalAccuracy: 10};
assert.equal(request('config', 'POST', target).status, 200);
assert.equal(request('config').data.latitude, target.latitude);
const rewritten = rewrite();
assert(rewritten.body, 'Saved target must rewrite a real WLOC fixture');
const extracted = api.extractAppleWLocPayload(api.bodyToBytes(rewritten.body));
const summary = api.patchedPayloadSummary(extracted.payload);
const pair = summary.match(/firstWifi=([\d.-]+),([\d.-]+)/);
assert(pair, summary);
assert(Math.abs(Number(pair[1]) - target.latitude) < 2e-8, summary);
assert(Math.abs(Number(pair[2]) - target.longitude) < 2e-8, summary);
assert.equal(request('config', 'POST', {...target, latitude: 91}).status, 400);
assert.equal(request('config').data.latitude, target.latitude, 'Invalid request must preserve saved location');
assert.equal(request('disable', 'POST', {}).data.enabled, false);
assert.equal(rewrite().body, undefined, 'Disabled target must pass through without reverting to Apple Park');
storage.set('wloc_native_target_v2', '{bad json');
assert.equal(rewrite().body, undefined, 'Corrupt storage must pass through');
writes = false;
assert.equal(request('config', 'POST', target).status, 500);
console.log('Surge control + real binary WLOC rewrite integration: all assertions passed');
