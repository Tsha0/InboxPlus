#!/usr/bin/env python3
"""Generate Flutter launcher icons from Inbox+'s canonical brand artwork."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps/inboxplus_flutter"
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)


def resize(image, pixels):
    return image.resize((pixels, pixels), Image.Resampling.LANCZOS)


def desktop_plate(artwork):
    canvas, inset = 1024, 100
    plate_size = canvas - inset * 2
    mask = Image.new("L", (canvas, canvas))
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, canvas - inset - 1, canvas - inset - 1),
        radius=plate_size * 0.2237,
        fill=255,
    )
    shadow = Image.new("RGBA", (canvas, canvas))
    shadow.putalpha(
        ImageChops.offset(mask, 0, round(canvas * 0.012))
        .filter(ImageFilter.GaussianBlur(canvas * 0.028))
        .point(lambda alpha: round(alpha * 0.22))
    )
    plate = Image.new("RGBA", (canvas, canvas))
    plate.paste(resize(artwork, plate_size), (inset, inset))
    plate.putalpha(mask)
    return Image.alpha_composite(shadow, plate)


def png_images():
    with Image.open(ROOT / "docs/assets/inboxplus-logo.png") as original:
        artwork = Image.new("RGB", original.size, "black")
        artwork.paste(original.convert("RGB"), mask=original.getchannel("A") if original.mode == "RGBA" else None)
    desktop = desktop_plate(artwork)
    images = {}
    images[APP / "assets/inboxplus-logo.png"] = artwork.convert("RGBA")
    android = APP / "android/app/src/main/res"
    foreground = Image.new("RGBA", artwork.size, "white")
    foreground.putalpha(ImageOps.grayscale(artwork).point(lambda alpha: 0 if alpha <= 4 else alpha))
    for density, scale in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        directory = android / ("mipmap-" + density)
        images[directory / "ic_launcher.png"] = resize(artwork, round(48 * scale))
        images[directory / "ic_launcher_foreground.png"] = resize(foreground, round(108 * scale))
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((ios / "Contents.json").read_text())["images"]:
        pixels = round(float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x")))
        images[ios / entry["filename"]] = resize(artwork, pixels)
    images[APP / "linux/resources/com.inboxplus.app.png"] = resize(desktop, 512)
    return images, desktop


def adaptive_icons():
    resources = APP / "android/app/src/main/res"
    return {
        resources / "mipmap-anydpi-v26/ic_launcher.xml": (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@android:color/black"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n'
        ),
        resources / "mipmap-anydpi-v33/ic_launcher.xml": (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@android:color/black"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n'
        ),
    }


def matches(actual, expected):
    return actual.size == expected.size and actual.convert("RGBA").tobytes() == expected.convert("RGBA").tobytes()


def generate(check=False):
    images, desktop = png_images()
    differences = []
    for path, expected in images.items():
        if check:
            if not path.is_file():
                differences.append(path)
                continue
            with Image.open(path) as actual:
                if not matches(actual, expected):
                    differences.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            expected.save(path, format="PNG", compress_level=9)
    icon = APP / "windows/runner/resources/app_icon.ico"
    if check:
        if not icon.is_file():
            differences.append(icon)
        else:
            with Image.open(icon) as actual:
                if actual.ico.sizes() != {(size, size) for size in ICO_SIZES} or any(
                    not matches(actual.ico.getimage((size, size)), resize(desktop, size)) for size in ICO_SIZES
                ):
                    differences.append(icon)
    else:
        desktop.save(icon, format="ICO", sizes=[(size, size) for size in ICO_SIZES])
    for path, expected in adaptive_icons().items():
        if check:
            if not path.is_file() or path.read_text() != expected:
                differences.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected)
    if differences:
        raise SystemExit("Launcher icons need regeneration:\n" + "\n".join(str(path.relative_to(ROOT)) for path in differences))
    print(("Verified" if check else "Generated") + " Inbox+ launcher icons for Android, iOS, Windows, and Linux.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check rendered pixels and platform icon metadata without modifying files.")
    generate(parser.parse_args().check)
