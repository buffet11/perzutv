"""Perzutv 图标 —— 生成并导出到项目各平台位置。

方案 A：青蓝渐变圆角方块 + 居中播放三角。
配色带一点紫调（用户指定：往紫靠，但不要太紫）。

用法：
    python tools/build_icons.py --preview      # 只出配色对比图
    python tools/build_icons.py --palette mid  # 导出全套（默认 mid）
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

APP = Path(__file__).resolve().parent.parent

SIZE = 1024
SS = 2
W = SIZE * SS
BG_RADIUS = 0.225
WHITE = (255, 255, 255)

# 播放三角（归一化坐标）
TRI = [(0.365, 0.275), (0.365, 0.725), (0.745, 0.500)]

# 三档紫度，供挑选
PALETTES = {
    "light": ((74, 171, 242), (74, 99, 224)),     # #4AABF2 -> #4A63E0  微紫
    "mid": ((74, 158, 245), (90, 82, 232)),       # #4A9EF5 -> #5A52E8  中紫（默认）
    "vivid": ((84, 143, 245), (107, 71, 229)),    # #548FF5 -> #6B47E5  偏紫
}
DEFAULT_PALETTE = "mid"


def render(palette: str) -> Image.Image:
    c1, c2 = PALETTES[palette]

    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for y in range(W):
        t = y / (W - 1)
        d.line([(0, y), (W, y)],
               fill=tuple(int(a + (b - a) * t) for a, b in zip(c1, c2)))

    bg_mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(bg_mask).rounded_rectangle(
        [0, 0, W - 1, W - 1], radius=int(BG_RADIUS * W), fill=255)

    out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    out.paste(img, (0, 0), bg_mask)

    tri = Image.new("L", (W, W), 0)
    ImageDraw.Draw(tri).polygon([(x * W, y * W) for x, y in TRI], fill=255)
    tri = tri.filter(ImageFilter.GaussianBlur(0.017 * W)).point(
        lambda v: 255 if v > 140 else 0)
    out.paste(Image.new("RGB", (W, W), WHITE), (0, 0), tri)

    return out.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------- 导出

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
ICO_FILES = [
    "windows/runner/resources/app_icon.ico",
    "assets/images/logo/logo_lanczos.ico",
    "assets/images/logo/logo_windows.ico",
]
PNG_FILES = [
    "assets/images/logo/logo_rounded.png",
    "assets/images/logo/logo_android.png",
    "assets/images/logo/logo_ios.png",
    "assets/images/logo/logo_linux.png",
]
ANDROID_MIPMAP = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
APPICONSET = {
    "macos/Runner/Assets.xcassets/AppIcon.appiconset": {
        "app_icon_16.png": 16, "app_icon_32.png": 32, "app_icon_64.png": 64,
        "app_icon_128.png": 128, "app_icon_256.png": 256,
        "app_icon_512.png": 512, "app_icon_1024.png": 1024,
    },
    "ios/Runner/Assets.xcassets/AppIcon.appiconset": {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    },
}


def export(img: Image.Image) -> list[str]:
    done = []

    for rel in ICO_FILES:
        p = APP / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
        done.append(rel)

    for rel in PNG_FILES:
        p = APP / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, format="PNG")
        done.append(rel)

    for folder, px in ANDROID_MIPMAP.items():
        p = APP / "android/app/src/main/res" / folder / "ic_launcher.png"
        if p.parent.is_dir():
            img.resize((px, px), Image.LANCZOS).save(p, format="PNG")
            done.append(str(p.relative_to(APP)))

    for folder, files in APPICONSET.items():
        base = APP / folder
        if not base.is_dir():
            continue
        for name, px in files.items():
            img.resize((px, px), Image.LANCZOS).save(base / name, format="PNG")
        done.append(f"{folder}/({len(files)} 个)")

    return done


def preview() -> Path:
    out = APP.parent / "tools/_icon_drafts"
    out.mkdir(parents=True, exist_ok=True)
    icons = [(k, render(k)) for k in ("light", "mid", "vivid")]

    pad, big = 40, 400
    sheet = Image.new("RGB", (pad + 3 * (big + pad), pad + big + pad + 96 + pad),
                      (255, 255, 255))
    for i, (key, im) in enumerate(icons):
        x = pad + i * (big + pad)
        sheet.paste(im.resize((big, big), Image.LANCZOS), (x, pad))
        # 小尺寸预览
        xx = x
        for s in (64, 32, 16):
            tile = Image.new("RGBA", (96, 96), (245, 246, 248, 255))
            th = im.resize((s, s), Image.LANCZOS)
            tile.paste(th, ((96 - s) // 2, (96 - s) // 2), th)
            sheet.paste(tile, (xx, pad + big + pad))
            xx += 96
    path = out / "palette_compare.png"
    sheet.save(path)
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--palette", default=DEFAULT_PALETTE, choices=list(PALETTES))
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()

    p = preview()
    print(f"配色对比图: {p}")

    if args.preview:
        return 0

    img = render(args.palette)
    print(f"导出配色: {args.palette}  {PALETTES[args.palette]}")
    for rel in export(img):
        print(f"  -> {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
