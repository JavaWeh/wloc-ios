"""Package the genuine device build; does not pretend to sign or compile it."""
from pathlib import Path
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def package(app, output):
    if not (app / "Info.plist").is_file():
        raise SystemExit("No device build found. Run scripts/build-ipa.sh on macOS first.")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file():
        raise SystemExit("No compiled executable. Run the macOS Xcode build first.")
    if info.get("DTPlatformName") != "iphoneos":
        raise SystemExit("Refusing to package a simulator or unverified build.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_file():
                name = "Payload/" + path.relative_to(app.parent).as_posix()
                entry = zipfile.ZipInfo.from_file(path, name)
                entry.create_system = 3
                mode = 0o755 if path == executable or path.stat().st_mode & 0o111 else 0o644
                entry.external_attr = (0o100000 | mode) << 16
                archive.writestr(entry, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    print(f"Unsigned IPA: {output}")


if __name__ == "__main__":
    package(ROOT / "build/DerivedData/Build/Products/Release-iphoneos/WLoc.app",
            ROOT / "build/WLoc-unsigned.ipa")

