#!/usr/bin/env python3
"""Renders the onboarding tour's captures from the real app, then imports them as assets.

The app runs once in its tour capture mode (see DroppyCode/Support/TourCaptures.swift):
it opens the real window with mock data over a curated gradient backdrop, photographs
each tour scene as a 16:10 still into build.noindex/tour-captures, and quits. This
script then resizes every still to exactly 1320x824 and writes it into the tour
imagesets, composing the four theme stills into one 2x2 collage. Needs Pillow (pip).

    scripts/tour_captures.py                 # build, capture, import into the asset catalog
    scripts/tour_captures.py --website       # ...and export the full-size set for the website
    scripts/tour_captures.py --export-only   # export the website set from the last run
    scripts/tour_captures.py --upload        # ...and push it to R2 (wrangler signed in)
"""

import json
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
CAPTURES = ROOT / "build.noindex" / "tour-captures"
DERIVED = ROOT / "build.noindex" / "tour"
APP = DERIVED / "Build/Products/Debug/Droppy Code.app"
ASSETS = ROOT / "DroppyCode" / "Resources" / "Assets.xcassets"

WIDTH = 1320
HEIGHT = 824
SCENES = ["welcome", "hydra", "pairs", "slider", "panels"]
CONTENTS = {"info": {"author": "xcode", "version": 1}}


def step(title):
    print(f"\n==> {title}", flush=True)


def build():
    step("Building Droppy Code (Debug)")
    subprocess.run(["xcodegen", "generate", "--quiet"], cwd=ROOT, check=True)
    result = subprocess.run([
        "xcodebuild", "-project", "DroppyCode.xcodeproj", "-scheme", "DroppyCode", "-configuration", "Debug",
        "-destination", "platform=macOS", "-derivedDataPath", str(DERIVED), "-skipPackagePluginValidation", "build",
    ], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print("\n".join(line for line in result.stdout.splitlines() if "error:" in line))
        sys.exit("Build failed")


def capture():
    step("Capturing the tour scenes")
    shutil.rmtree(CAPTURES, ignore_errors=True)
    CAPTURES.mkdir(parents=True)
    # Through LaunchServices, not the binary: an app launched from a shell is refused
    # activation, and the captures need the key window of the active app. Not waited on:
    # the run is force-killed at its budget, so a stall can never leave it running.
    marker = "tour-captures " + str(CAPTURES)
    subprocess.run(["open", "-n", str(APP), "--args", "--tour-captures", str(CAPTURES)], check=True)
    deadline = time.time() + 150
    while time.time() < deadline:
        time.sleep(2)
        alive = subprocess.run(["pgrep", "-f", marker], capture_output=True, text=True).stdout.strip()
        if not alive:
            break
    else:
        subprocess.run(["pkill", "-9", "-f", marker])
        print("  the run overran its budget and was killed")
    log = CAPTURES / "run.log"
    if log.exists():
        print("  " + log.read_text().strip().splitlines()[-1])


def fit(image, width, height):
    """Centre-crop to the target aspect (a no-op when already exact, up to rounding),
    then resize to exactly width x height."""
    from PIL import Image, ImageDraw
    if abs(image.width / image.height - width / height) > 1e-9:
        target = width / height
        if image.width / image.height > target:
            want = round(image.height * target)
            left = (image.width - want) // 2
            image = image.crop((left, 0, left + want, image.height))
        else:
            want = round(image.width / target)
            top = (image.height - want) // 2
            image = image.crop((0, top, image.width, top + want))
    return image.resize((width, height), Image.LANCZOS)


def write_imageset(name, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{name}@2x.png"
    image.save(path, "PNG")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}@2x.png", "idiom": "universal", "scale": "2x"}],
        **CONTENTS,
    }, indent=2) + "\n")
    print(f"  {path.relative_to(ROOT)}")


def encode():
    from PIL import Image, ImageDraw
    step("Importing")
    for scene in SCENES:
        source = CAPTURES / f"tour-{scene}.png"
        if not source.exists():
            sys.exit(f"The capture run wrote no tour-{scene}.png; see {CAPTURES / 'run.log'}")
        write_imageset(f"tour-{scene}", fit(Image.open(source).convert("RGB"), WIDTH, HEIGHT))
    themes = sorted(CAPTURES.glob("tour-theme-*.png"))
    if len(themes) != 4:
        sys.exit(f"Expected 4 tour-theme-*.png, found {len(themes)}; see {CAPTURES / 'run.log'}")
    gap = 8
    tile_w = (WIDTH - gap) // 2
    tile_h = (HEIGHT - gap) // 2
    radius = 18
    background = Image.open(themes[0]).convert("RGB").getpixel((0, 0))
    collage = Image.new("RGB", (WIDTH, HEIGHT), background)
    mask = Image.new("L", (tile_w, tile_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile_w, tile_h], radius=radius, fill=255)
    for index, source in enumerate(themes):
        tile = fit(Image.open(source).convert("RGB"), tile_w, tile_h)
        collage.paste(tile, ((tile_w + gap) * (index % 2), (tile_h + gap) * (index // 2)), mask)
    write_imageset("tour-themes", collage)


WEB_OUT = ROOT / "website" / "assets" / "app" / "tour"
R2_BUCKET = "droppy-releases"
R2_PREFIX = "site-assets/droppy-code/tour"
# The website's set: every scene at the capture's own 2x pixels (2688x1680 for a 16:10
# rect), as near-lossless WebP, plus the four themes as one collage at the same size.
WEB_SCENES = SCENES + ["window"]


def website():
    from PIL import Image, ImageDraw
    step(f"Exporting the website's set to {WEB_OUT.relative_to(ROOT)}")
    WEB_OUT.mkdir(parents=True, exist_ok=True)
    for name in WEB_SCENES:
        source = CAPTURES / f"tour-{name}.png"
        if not source.exists():
            print(f"  (no tour-{name}.png)")
            continue
        image = Image.open(source).convert("RGB")
        image.save(WEB_OUT / f"{name}.webp", "WEBP", quality=92, method=6)
        print(f"  {name}.webp {image.size[0]}x{image.size[1]}  {(WEB_OUT / f'{name}.webp').stat().st_size // 1024} KB")
    themes = sorted(CAPTURES.glob("tour-theme-*.png"))
    for source in themes:
        name = source.stem.removeprefix("tour-")
        image = Image.open(source).convert("RGB")
        image.save(WEB_OUT / f"{name}.webp", "WEBP", quality=90, method=6)
        print(f"  {name}.webp {image.size[0]}x{image.size[1]}")
    if len(themes) == 4:
        first = Image.open(themes[0]).convert("RGB")
        gap = 16
        tile_w = (first.size[0] - gap) // 2
        tile_h = round(tile_w * 10 / 16)
        collage = Image.new("RGB", (tile_w * 2 + gap, tile_h * 2 + gap), first.getpixel((0, 0)))
        for index, source in enumerate(themes):
            tile = fit(Image.open(source).convert("RGB"), tile_w, tile_h)
            mask = Image.new("L", tile.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, tile.size[0] - 1, tile.size[1] - 1), radius=36, fill=255)
            x = (index % 2) * (tile_w + gap)
            y = (index // 2) * (tile_h + gap)
            collage.paste(tile, (x, y), mask)
        collage.save(WEB_OUT / "themes.webp", "WEBP", quality=92, method=6)
        print(f"  themes.webp {collage.size[0]}x{collage.size[1]}")


def upload():
    step(f"Uploading to R2 ({R2_BUCKET}/{R2_PREFIX})")
    for path in sorted(WEB_OUT.glob("*.webp")):
        key = f"{R2_PREFIX}/{path.name}"
        subprocess.run([
            "wrangler", "r2", "object", "put", f"{R2_BUCKET}/{key}", "--file", str(path),
            "--content-type", "image/webp", "--cache-control", "public, max-age=31536000, immutable", "--remote",
        ], check=True, capture_output=True)
        print(f"  {key}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--export-only" not in args:
        build()
        capture()
        encode()
        print(f"\nReady: {ASSETS}")
    if "--website" in args or "--export-only" in args or "--upload" in args:
        website()
    if "--upload" in args:
        upload()
