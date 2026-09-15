#!/usr/bin/env python3
"""Renders the marketing site's app captures from the real app, then cuts and encodes them.

    scripts/website_captures.py            # build, capture, encode into website/assets/app
    scripts/website_captures.py --encode   # encode again from the last capture run
    scripts/website_captures.py --upload   # push the encoded set to R2 (with either of the above)

The app runs once in its capture mode (see SwarmAI/Support/WebsiteCaptures.swift): it
opens the real window over this Mac's wallpaper with mock data, plays each scene, writes
stills and 60 fps HEVC film masters to build.noindex/website-captures, and quits. This
script then cuts what the site shows (whole windows, or one self-contained region on empty
glass), encodes every film twice, H.264 for everyone and HEVC for Safari, at the capture's
own 2x pixels, and saves the stills as near-lossless WebP. Needs ffmpeg (brew), Pillow (pip)
and, for --upload, wrangler signed in to the SwarmAI Cloudflare account.
"""

import json
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
CAPTURES = ROOT / "build.noindex" / "website-captures"
DERIVED = ROOT / "build.noindex" / "website"
APP = DERIVED / "Build/Products/Debug/SwarmAI.app"
OUT = ROOT / "website" / "assets" / "app"
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
FFPROBE = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"
R2_BUCKET = "swarmai-releases"
R2_PREFIX = "site-assets/swarmai"

# Every capture is 2x with a 72 point (144 px) wallpaper margin on every side. The wide
# window is 1320x860 points, so its captures are 2928x2008; the narrow one is 860x560 points,
# 2008x1408. A width here only ever caps, never scales up.
MARGIN = 144
FILMS = {
    # name: (master, output width, hevc bitrate)
    "hero": ("editing", 2400, "4500k"),
    "question": ("question", 2080, "3500k"),
    "queue": ("queue", 2080, "3500k"),
    "slider": ("slider", 2008, "3000k"),
}
STILLS = {
    # name: (source still, crop, output width)
    "hero": ("editing", None, 2400),
    "diff": ("diff", None, 2080),
    "palette": ("palette", None, 2080),
    "switcher": ("switcher", None, 2008),
    "sidebar": ("editing", (0, MARGIN, MARGIN + 540, MARGIN + 1720), 684),
    "plans": ("plans", "pane", 2080),
}
THEME_WIDTH = 2080


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
    step("Capturing the scenes")
    shutil.rmtree(CAPTURES, ignore_errors=True)
    CAPTURES.mkdir(parents=True)
    # Through LaunchServices, not the binary: an app launched from a shell is refused activation,
    # and the captures need the key window of the active app, traffic lights lit. Not waited on:
    # the run is force-killed at its budget, so a stall can never leave a recording running.
    marker = "website-captures " + str(CAPTURES)
    subprocess.run(["open", "-n", str(APP), "--args", "--website-captures", str(CAPTURES)], check=True)
    deadline = time.time() + 120
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
    for master, _, _ in FILMS.values():
        film = CAPTURES / "films" / f"{master}.mov"
        if not film.exists() or film.stat().st_size == 0:
            sys.exit(f"The capture run wrote no {master} film; see {log}")


def probe(path):
    result = subprocess.run([
        FFPROBE, "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,avg_frame_rate,color_space,color_transfer,color_primaries,color_range",
        "-of", "json", str(path),
    ], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)["streams"][0]


def color_flags(stream):
    """The master's own colour tags, carried through so nothing shifts on the way to the web."""
    flags = []
    for key, flag in (("color_primaries", "-color_primaries"), ("color_transfer", "-color_trc"), ("color_space", "-colorspace")):
        value = stream.get(key)
        if value and value != "unknown":
            flags += [flag, value]
    return flags


def encode_film(name, master, width, hevc_bitrate):
    source = CAPTURES / "films" / f"{master}.mov"
    stream = probe(source)
    scale = f"scale='min({width},iw)':-2:flags=lanczos"
    common = ["-vf", scale, "-r", "60", "-fps_mode", "cfr", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an"]
    common += color_flags(stream)
    subprocess.run([
        FFMPEG, "-y", "-loglevel", "error", "-i", str(source), *common,
        "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-profile:v", "high", "-level", "5.1", "-g", "120",
        str(OUT / f"{name}.mp4"),
    ], check=True)
    subprocess.run([
        FFMPEG, "-y", "-loglevel", "error", "-i", str(source), *common,
        "-c:v", "hevc_videotoolbox", "-b:v", hevc_bitrate, "-tag:v", "hvc1", "-g", "120",
        str(OUT / f"{name}-hevc.mp4"),
    ], check=True)
    # The poster is the film's own first frame.
    poster = CAPTURES / "films" / f"{master}-first.png"
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", str(source), "-frames:v", "1", str(poster)], check=True)
    still(f"{name}-poster", poster, None, width)


def pane_crop(image, blank):
    """The chat pane, from just above its first content down to the window's bottom edge, for a
    scene staged on an otherwise empty thread. Found by comparing against the empty thread."""
    from PIL import ImageChops
    pane = (MARGIN + 540, MARGIN + 100, MARGIN + 2620, MARGIN + 1480)
    diff = ImageChops.difference(image.crop(pane), blank.crop(pane)).convert("L").point(lambda v: 255 if v > 18 else 0)
    box = diff.getbbox()
    top = pane[1] + (box[1] if box else 0) - 40
    return (MARGIN + 540, max(MARGIN, top), MARGIN + 2620, MARGIN + 1720)


def still(name, source, crop, width, quality=92):
    from PIL import Image
    image = Image.open(source).convert("RGB")
    if crop == "pane":
        crop = pane_crop(image, Image.open(CAPTURES / "blank-wide.png").convert("RGB"))
    if crop:
        image = image.crop(crop)
    if image.width > width:
        image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
    image.save(OUT / f"{name}.webp", "WEBP", quality=quality, method=6)
    return image.size


def encode():
    step("Encoding")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (master, width, bitrate) in FILMS.items():
        encode_film(name, master, width, bitrate)
        size = probe(OUT / f"{name}.mp4")
        print(f"  {name}.mp4 {size['width']}x{size['height']}  "
              f"{(OUT / f'{name}.mp4').stat().st_size // 1024} KB  + hevc {(OUT / f'{name}-hevc.mp4').stat().st_size // 1024} KB")
    for name, (source, crop, width) in STILLS.items():
        size = still(name, CAPTURES / f"{source}.png", crop, width)
        print(f"  {name}.webp {size[0]}x{size[1]}  {(OUT / f'{name}.webp').stat().st_size // 1024} KB")
    themes = OUT / "themes"
    themes.mkdir(exist_ok=True)
    for source in sorted(CAPTURES.glob("theme-*.png")):
        name = source.stem.removeprefix("theme-")
        still(f"themes/{name}", source, None, THEME_WIDTH, quality=86)
    print(f"  themes/  {len(list(themes.glob('*.webp')))} stills")


def upload():
    step(f"Uploading to R2 ({R2_BUCKET}/{R2_PREFIX})")
    for path in sorted(OUT.rglob("*")):
        if not path.is_file():
            continue
        key = f"{R2_PREFIX}/{path.relative_to(OUT)}"
        content_type = {"mp4": "video/mp4", "webp": "image/webp", "png": "image/png"}.get(path.suffix[1:], "application/octet-stream")
        subprocess.run([
            "wrangler", "r2", "object", "put", f"{R2_BUCKET}/{key}", "--file", str(path),
            "--content-type", content_type, "--cache-control", "public, max-age=31536000, immutable", "--remote",
        ], check=True, capture_output=True)
        print(f"  {key}")


if __name__ == "__main__":
    if "--encode" not in sys.argv and "--upload-only" not in sys.argv:
        build()
        capture()
    if "--upload-only" not in sys.argv:
        encode()
    if "--upload" in sys.argv or "--upload-only" in sys.argv:
        upload()
    print(f"\nReady: {OUT}")
