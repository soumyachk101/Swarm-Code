#!/usr/bin/env python3
"""Renders the onboarding tour's captures from the real app, then imports them as assets.

The app runs once in its tour capture mode (see SwarmAI/Support/TourCaptures.swift):
it opens the real window with mock data over a curated gradient backdrop, photographs
each tour scene as a 16:10 still into build.noindex/tour-captures, and quits. This
script then resizes every still to exactly 1320x824 and writes it into the tour
imagesets (welcome comes from the web hero, themes from a seamless 2x2 collage).
With --website it also exports cropped-on-the-action WebP files plus per-theme shots
into website/assets/app/tour/. Needs Pillow (pip).

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
APP = DERIVED / "Build/Products/Debug/SwarmAI.app"
ASSETS = ROOT / "SwarmAI" / "Resources" / "Assets.xcassets"

WIDTH = 1320
HEIGHT = 824
SCENES = ["welcome", "hydra", "pairs", "slider", "panels"]
CONTENTS = {"info": {"author": "xcode", "version": 1}}

# App window size in points for each still. Every still is a 16:10 rect around the
# window: the frame grown by 72 pt on every side, then widened/heightened to 1.6.
WINDOW_SIZES = {
    "tour-welcome": (1200, 660),
    "web-hero": (1280, 800),
    "tour-hydra": (1080, 640),
    "tour-pairs": (900, 600),
    "tour-slider": (900, 600),
    "tour-panels": (1200, 740),
    "tour-window": (660, 600),
    "web-diff": (1200, 660),
    "web-palette": (1200, 660),
    "web-plans": (1200, 660),
    "web-question": (1200, 660),
    "web-queue": (1200, 660),
    "tour-theme-tokyoNight": (900, 560),
    "tour-theme-gruvbox": (900, 560),
    "tour-theme-catppuccinLatte": (900, 560),
    "tour-theme-rosePine": (900, 560),
    "web-theme-tokyoNight": (900, 560),
    "web-theme-gruvbox": (900, 560),
    "web-theme-catppuccinLatte": (900, 560),
    "web-theme-rosePine": (900, 560),
}
THEME_ORDER = ["tokyoNight", "gruvbox", "catppuccinLatte", "rosePine"]


def window_box(name):
    """Return (rw, rh, mx, my, w, h): still rect and margins in points."""
    stem = name.removesuffix(".png")
    if stem not in WINDOW_SIZES:
        raise KeyError(f"No window size for {name}")
    w, h = WINDOW_SIZES[stem]
    rw, rh = w + 144, h + 144
    if rw / rh < 1.6:
        rw = round(rh * 1.6)
    else:
        rh = round(rw / 1.6)
    return (rw, rh, (rw - w) / 2, (rh - h) / 2, w, h)


def crop_points(image, name, x, y, w, h):
    """Crop a window-points rect (top-left origin, may extend into the margin)."""
    rw, rh, mx, my, ww, wh = window_box(name)
    assert abs(image.width - 2 * rw) <= 2 and abs(image.height - 2 * rh) <= 2, \
        f"{name}: PNG is {image.width}x{image.height}, expected {2 * rw}x{2 * rh}"
    x0 = round(2 * (mx + x))
    y0 = round(2 * (my + y))
    x1 = round(2 * (mx + x + w))
    y1 = round(2 * (my + y + h))
    x0 = max(0, min(image.width, x0))
    y0 = max(0, min(image.height, y0))
    x1 = max(0, min(image.width, x1))
    y1 = max(0, min(image.height, y1))
    return image.crop((x0, y0, x1, y1))


def step(title):
    print(f"\n==> {title}", flush=True)


def build():
    step("Building SwarmAI (Debug)")
    subprocess.run(["xcodegen", "generate", "--quiet"], cwd=ROOT, check=True)
    result = subprocess.run([
        "xcodebuild", "-project", "SwarmAI.xcodeproj", "-scheme", "SwarmAI", "-configuration", "Debug",
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
    deadline = time.time() + 330
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


def theme_collage():
    """Seamless 2x2 collage, exactly one still's size, gradient continuous."""
    from PIL import Image
    order = [f"tour-theme-{t}.png" for t in THEME_ORDER]
    sources = [CAPTURES / n for n in order]
    missing = [s for s in sources if not s.exists()]
    if missing:
        sys.exit(f"Missing theme stills: {[p.name for p in missing]}; see {CAPTURES / 'run.log'}")
    first = Image.open(sources[0]).convert("RGB")
    full_w, full_h = first.size
    tile_w, tile_h = full_w // 2, full_h // 2
    collage = Image.new("RGB", (tile_w * 2, tile_h * 2))
    for index, source in enumerate(sources):
        tile = Image.open(source).convert("RGB").resize((tile_w, tile_h), Image.LANCZOS)
        collage.paste(tile, ((index % 2) * tile_w, (index // 2) * tile_h))
    return collage


def interior(name, inset=8):
    """The window's inside, `inset` points in from its edges: the tour card rounds its own
    corners, so a picture that still showed the window's corners would draw a second,
    tighter corner inside them."""
    from PIL import Image
    rw, rh, mx, my, w, h = window_box(name)
    image = Image.open(CAPTURES / f"{name}.png").convert("RGB")
    box = (round(2 * (mx + inset)), round(2 * (my + inset)), round(2 * (mx + w - inset)), round(2 * (my + h - inset)))
    return image.crop(box)


def theme_mosaic():
    """The four theme windows' insides, two by two with a thin dark seam, for the tour."""
    from PIL import Image
    tiles = [interior(f"tour-theme-{theme}", inset=8) for theme in THEME_ORDER]
    gap = 6
    tile_w = (WIDTH - gap) // 2
    tile_h = (HEIGHT - gap) // 2
    mosaic = Image.new("RGB", (tile_w * 2 + gap, tile_h * 2 + gap), (16, 16, 20))
    for index, tile in enumerate(tiles):
        mosaic.paste(fit(tile, tile_w, tile_h), ((index % 2) * (tile_w + gap), (index // 2) * (tile_h + gap)))
    return mosaic


def encode():
    from PIL import Image, ImageDraw
    step("Importing")
    for name, source in [("tour-welcome", "web-hero"), ("tour-hydra", "tour-hydra"), ("tour-pairs", "tour-pairs"),
                         ("tour-slider", "tour-slider"), ("tour-panels", "tour-panels")]:
        if not (CAPTURES / f"{source}.png").exists():
            sys.exit(f"The capture run wrote no {source}.png; see {CAPTURES / 'run.log'}")
        write_imageset(name, fit(interior(source), WIDTH, HEIGHT))
    write_imageset("tour-themes", fit(theme_mosaic(), WIDTH, HEIGHT))


WEB_OUT = ROOT / "website" / "assets" / "app" / "tour"
R2_BUCKET = "droppy-releases"
R2_PREFIX = "site-assets/droppy-code/tour"
# The website's set: every scene at the capture's own 2x pixels (2688x1680 for a 16:10
# rect), as near-lossless WebP, plus the four themes as one collage at the same size.
WEB_SCENES = SCENES + ["window"]


def save_webp(image, dest, quality=92):
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(dest, "WEBP", quality=quality, method=6)
    print(f"  {dest.relative_to(ROOT)} {image.size[0]}x{image.size[1]}")


def website():
    from PIL import Image, ImageDraw
    step(f"Exporting the website's set to {WEB_OUT.relative_to(ROOT)}")
    WEB_OUT.mkdir(parents=True, exist_ok=True)

    def load(stem):
        source = CAPTURES / f"{stem}.png"
        if not source.exists():
            print(f"  (no {stem}.png)")
            return None
        return Image.open(source).convert("RGB")

    hero = load("web-hero")
    if hero is not None:
        save_webp(hero, WEB_OUT / "hero.webp")
        save_webp(hero, WEB_OUT / "welcome.webp")
        # Sidebar: window's left 300 pt plus the left margin, full window height.
        rw, rh, mx, my, w, h = window_box("web-hero")
        assert abs(hero.width - 2 * rw) <= 2 and abs(hero.height - 2 * rh) <= 2
        sidebar = hero.crop((0, round(2 * my), round(2 * (mx + 300)), round(2 * (my + h))))
        save_webp(sidebar, WEB_OUT / "sidebar.webp")
    for stem in ["tour-hydra", "tour-panels", "tour-window"]:
        image = load(stem)
        if image is not None:
            save_webp(image, WEB_OUT / f"{stem.removeprefix('tour-')}.webp")
    slider = load("tour-slider")
    if slider is not None:
        save_webp(crop_points(slider, "tour-slider", 900 - 640, 600 - 400, 640, 400),
                   WEB_OUT / "slider.webp")
    pairs = load("tour-pairs")
    if pairs is not None:
        save_webp(crop_points(pairs, "tour-pairs", 900 - 720, 600 - 450, 720, 450),
                   WEB_OUT / "pairs.webp")
    for stem, out in [("web-diff", "diff"), ("web-palette", "palette")]:
        image = load(stem)
        if image is not None:
            save_webp(crop_points(image, stem, (1200 - 880) / 2, 0, 880, 550),
                       WEB_OUT / f"{out}.webp")
    plans = load("web-plans")
    if plans is not None:
        save_webp(plans, WEB_OUT / "plans.webp")
    for stem, out in [("web-question", "question"), ("web-queue", "queue")]:
        image = load(stem)
        if image is not None:
            save_webp(crop_points(image, stem, (1200 - 960) / 2, 660 - 600, 960, 600),
                       WEB_OUT / f"{out}.webp")
    save_webp(theme_collage(), WEB_OUT / "themes.webp")
    for source in sorted(CAPTURES.glob("web-theme-*.png")):
        theme = source.stem.removeprefix("web-theme-")
        image = Image.open(source).convert("RGB")
        want_w = 2080
        want_h = round(image.height * want_w / image.width)
        save_webp(image.resize((want_w, want_h), Image.LANCZOS),
                   WEB_OUT / "themes" / f"{theme}.webp", quality=86)


def upload():
    step(f"Uploading to R2 ({R2_BUCKET}/{R2_PREFIX})")
    for path in sorted(WEB_OUT.rglob("*.webp")):
        key = f"{R2_PREFIX}/{path.relative_to(WEB_OUT)}"
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
