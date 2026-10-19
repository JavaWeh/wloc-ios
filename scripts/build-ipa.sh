#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Requires macOS and full Xcode. On Windows, use the included GitHub Actions workflow."
  exit 1
fi
python3 scripts/check_project.py
python3 scripts/test_packaging.py
node scripts/test_surge.cjs
/usr/bin/plutil -lint WLoc.xcodeproj/project.pbxproj WLoc/Resources/Info.plist
swift test
xcodebuild -project WLoc.xcodeproj -scheme WLoc -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  build
python3 scripts/package_ipa.py

