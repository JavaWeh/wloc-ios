"""Draw the app's simple geometric pin icon; no external image assets."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[1]
assets = ROOT / "WLoc/Resources/Assets.xcassets"
icon_dir = assets / "AppIcon.appiconset"
icon_dir.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#1668D4")
draw = ImageDraw.Draw(image)
draw.ellipse((122, 122, 902, 902), fill="#2379E5")
draw.ellipse((238, 186, 786, 734), fill="white")
draw.polygon([(277, 600), (747, 600), (512, 864)], fill="white")
draw.ellipse((400, 348, 624, 572), fill="#1668D4")
draw.ellipse((654, 668, 878, 892), fill="#54E1BD")
draw.line([(708, 780), (752, 824), (830, 738)], fill="#064D55", width=27)
image.save(icon_dir / "AppIcon.png")
(icon_dir / "Contents.json").write_text(json.dumps({"images": [{
    "filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"
}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
accent = assets / "AccentColor.colorset"
accent.mkdir(exist_ok=True)
(accent / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {
    "color-space": "srgb", "components": {"red": "0.086", "green": "0.408", "blue": "0.831", "alpha": "1.000"}
}}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(icon_dir / "AppIcon.png")

