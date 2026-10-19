"""Export source without upstream clone, build caches, credentials, or generated IPAs."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
files = [ROOT / name for name in ("README.md", "AUDIT.md", "Package.swift", ".gitignore", ".gitattributes", "LICENSE", "THIRD_PARTY.md")]
for directory in ("WLoc", "WLoc.xcodeproj", "Tests", "scripts", ".github", "Surge"):
    files.extend(path for path in (ROOT / directory).rglob("*")
                 if path.is_file() and "__pycache__" not in path.parts)
output = ROOT / "dist/WLoc-iOS-source.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, "WLoc-iOS/" + path.relative_to(ROOT).as_posix())
print(f"Source archive: {output} ({len(files)} files)")
