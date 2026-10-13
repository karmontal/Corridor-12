"""Draws the app icon (a road through a checkpoint to a district) into assets/icon/.

Run: python3 tools/make_icon.py   (needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
BG = (27, 33, 41, 255)
ROAD = (92, 195, 138, 255)
RISK = (229, 98, 94, 255)
GATE = (242, 165, 65, 255)
DEPOT = (90, 169, 230, 255)
HOME = (238, 241, 244, 255)


def draw(size: int, background: bool, foreground: bool) -> Image.Image:
    img = Image.new("RGBA", (size, size), BG if background else (0, 0, 0, 0))
    if not foreground:
        return img
    d = ImageDraw.Draw(img)
    s = size / 512.0

    def p(x, y):
        return (x * s, y * s)

    w = int(26 * s)
    d.line([p(400, 256), p(256, 256)], fill=ROAD, width=w)
    d.line([p(256, 256), p(130, 150)], fill=ROAD, width=w)
    d.line([p(256, 256), p(130, 362)], fill=RISK, width=w)
    r = 38 * s
    d.polygon([p(256, 256 - 52), p(256 + 52, 256), p(256, 256 + 52), p(256 - 52, 256)], fill=GATE)
    d.rectangle([p(400 - 40, 256 - 40), p(400 + 40, 256 + 40)], fill=DEPOT)
    for cx, cy in [(130, 150), (130, 362)]:
        d.ellipse([cx * s - r, cy * s - r, cx * s + r, cy * s + r], fill=HOME)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    draw(512, True, True).save(OUT / "icon_512.png")
    draw(432, True, False).save(OUT / "background_432.png")
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    # Adaptive icons crop to the middle ~66%, so the drawing sits inside that.
    fg.paste(draw(288, False, True), (72, 72))
    fg.save(OUT / "foreground_432.png")


if __name__ == "__main__":
    main()
