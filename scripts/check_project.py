"""Cross-platform structural checks. This is not a substitute for an Xcode build."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    info = plistlib.loads((ROOT / "WLoc/Resources/Info.plist").read_bytes())
    assert info["CFBundleExecutable"] == "$(EXECUTABLE_NAME)"
    project = (ROOT / "WLoc.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    declarations = re.findall(r"^\s*([A-F0-9]{24}) = \{", project, re.M)
    assert len(declarations) == len(set(declarations)), "Duplicate project object ID"
    refs = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    assert refs == set(declarations), "Dangling project object reference"
    sources = list((ROOT / "WLoc").glob("**/*.swift"))
    for source in sources:
        assert f'path = "{source.relative_to(ROOT).as_posix()}";' in project, source
    for path in re.findall(r'path = "([^"]+)"; sourceTree = "<group>"', project):
        assert (ROOT / path).exists(), f"Missing source: {path}"
    scheme = ET.parse(ROOT / "WLoc.xcodeproj/xcshareddata/xcschemes/WLoc.xcscheme")
    for ref in scheme.findall(".//BuildableReference"):
        assert ref.attrib["BlueprintIdentifier"] in declarations
    for contents in (ROOT / "WLoc/Resources/Assets.xcassets").glob("**/Contents.json"):
        data = json.loads(contents.read_text())
        for image in data.get("images", []):
            assert (contents.parent / image["filename"]).is_file()
    assert 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;' in project
    print(f"Structure OK: {len(sources)} Swift sources, {len(declarations)} project objects, plist, scheme, and assets")


if __name__ == "__main__":
    main()

