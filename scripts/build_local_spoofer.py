"""Reproduce the local-only response script from the pinned, attributed upstream."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Surge/vendor/location-spoofer.upstream.js"
HOOK = '''
    // WLoc Native modification: use only the phone's persistent target.
    // No remote config fetch; missing, corrupt, or disabled targets pass through.
    try {
      var local = JSON.parse($persistentStore.read("wloc_native_target_v2"));
      if (!local || typeof local.enabled !== "boolean" ||
          typeof local.latitude !== "number" || typeof local.longitude !== "number" ||
          !isFinite(local.latitude) || !isFinite(local.longitude) ||
          Math.abs(local.latitude) > 90 || Math.abs(local.longitude) > 180 ||
          typeof local.horizontalAccuracy !== "number" || !isFinite(local.horizontalAccuracy) || local.horizontalAccuracy < 1 || local.horizontalAccuracy > 1000000) {
        local = { enabled: false };
      }
      cfg = mergeConfig(cfg, local);
    } catch (localError) { cfg.enabled = false; }
'''


def main():
    text = SOURCE.read_text(encoding="utf-8")
    anchor = "    var configUrl = resolveConfigUrl(args);\n    var debug = parseBoolean(cfg.debug, false);"
    assert text.count(anchor) == 1, "Upstream changed: inspect local config insertion"
    text = text.replace(anchor, HOOK + '\n    var configUrl = "";\n    var debug = parseBoolean(cfg.debug, false);')
    notice = """// SPDX-License-Identifier: AGPL-3.0-or-later
// Derived from mekos2772/ios-location-spoofer, commit 06feaf2f2279ab966567f946d87ead9461564634.
// Modified by JavaWeh WLoc Native: persistent local target; no configUrl or server.
// See LICENSE and THIRD_PARTY.md. Rebuild with scripts/build_local_spoofer.py.
"""
    target = ROOT / "Surge/location-spoofer-local.js"
    target.write_text(notice + text, encoding="utf-8", newline="\n")
    print("Generated local spoofer; upstream SHA-256:", hashlib.sha256(SOURCE.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
