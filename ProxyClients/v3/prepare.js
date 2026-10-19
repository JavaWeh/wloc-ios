// SPDX-License-Identifier: AGPL-3.0-or-later
(function () {
  var headers = {}, original = $request.headers || {};
  Object.keys(original).forEach(function (key) { if (key.toLowerCase() !== "accept-encoding") headers[key] = original[key]; });
  headers["Accept-Encoding"] = "identity";
  $done({headers: headers});
})();
