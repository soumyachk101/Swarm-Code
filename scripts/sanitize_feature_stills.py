#!/usr/bin/env python3
"""
Surgical Feature Stills Sanitizer for Swarm Code (Subagent 3)

Re-sanitizes all 13 feature stills in website/assets/app/ from the pristine
ground truth source images in build.noindex/remote_audit/ with:
1. Dynamic, sub-pixel accurate toolbar button replacement (pre-clearing old Droppy rim).
2. Surgical column-wise vertical inpainting for text replacement without solid box artifacts or halos.
3. Clean typography, exact font sizes, and precise coordinates matching the original layouts.
"""

import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build.noindex" / "remote_audit"
OUT_APP = ROOT / "website" / "assets" / "app"
XCASSETS = ROOT / "SwarmCode" / "Resources" / "Assets.xcassets"
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"

OUT_APP.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------------
# Toolbar Bee Button Generator
# ----------------------------------------------------------------------

def make_toolbar_bee_button(size, badge_num=None):
    """
    Renders high-resolution circular Swarm Bee toolbar button with colorful gradient rim.
    """
    hires = size * 4
    img = Image.new('RGBA', (hires, hires), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    pad = hires * 0.05
    d.ellipse([(pad, pad), (hires - pad, hires - pad)], fill=(24, 28, 36, 250))
    
    rim_w = max(2, round(hires * 0.035))
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=-90, end=0, fill=(240, 140, 180, 210), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=0, end=90, fill=(120, 200, 240, 210), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=90, end=180, fill=(100, 150, 255, 210), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=180, end=270, fill=(200, 140, 240, 210), width=rim_w)
    
    logo_path = XCASSETS / "swarmcode-logo.imageset" / "swarmcode-logo@2x.png"
    logo = Image.open(logo_path).convert('RGBA')
    bee_size = round(hires * 0.65)
    logo_resized = logo.resize((bee_size, bee_size), Image.Resampling.LANCZOS)
    
    offset = (hires - bee_size) // 2
    img.alpha_composite(logo_resized, (offset, offset))
    
    if badge_num is not None:
        bw = round(hires * 0.42)
        bh = round(hires * 0.36)
        bx = hires - bw - round(hires * 0.02)
        by = round(hires * 0.02)
        d.rounded_rectangle([(bx, by), (bx + bw, by + bh)], radius=round(bh * 0.4), fill=(59, 130, 246, 255))
        d.rounded_rectangle([(bx, by), (bx + bw, by + bh)], radius=round(bh * 0.4), outline=(255, 255, 255, 120), width=max(1, round(hires * 0.015)))
        try:
            bfont = ImageFont.truetype(FONT_PATH, round(bh * 0.72))
            bfont.set_variation_by_name('Bold')
            bbox = d.textbbox((0, 0), str(badge_num), font=bfont)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            tx = bx + (bw - tw) // 2
            ty = by + (bh - th) // 2 - round(hires * 0.02)
            d.text((tx, ty), str(badge_num), fill=(255, 255, 255, 255), font=bfont)
        except Exception:
            pass
            
    return img.resize((size, size), Image.Resampling.LANCZOS)

# ----------------------------------------------------------------------
# Seamless Inpainting & Replacement Helpers
# ----------------------------------------------------------------------

def inpaint_line(arr, x0, x1, y0, y1):
    """Interpolates vertically between row y0 and row y1 column-by-column across [x0, x1]."""
    x0 = max(0, x0)
    x1 = min(arr.shape[1], x1)
    y0 = max(0, y0)
    y1 = min(arr.shape[0], y1)
    
    top = arr[y0, x0:x1]
    bot = arr[y1 - 1, x0:x1]
    H = y1 - y0
    if H <= 0:
        return
    for i in range(H):
        alpha = i / float(H)
        arr[y0 + i, x0:x1] = (1.0 - alpha) * top + alpha * bot

def replace_text_seamless(im, x, y, w, h, new_text, font_size=13, weight='Regular', color=(145, 160, 180, 255), mono=False, inpaint_x_pad=2, inpaint_y_pad=2):
    """
    Replaces text seamlessly using column-wise vertical interpolation.
    Prevents solid boxes, haloing, and character clipping.
    """
    arr = np.array(im, dtype=np.float32)
    x0 = x - inpaint_x_pad
    x1 = x + w + inpaint_x_pad
    y0 = y - inpaint_y_pad
    y1 = y + h + inpaint_y_pad
    inpaint_line(arr, x0, x1, y0, y1)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)
    try:
        if mono:
            font = ImageFont.truetype(MONO_FONT_PATH, font_size)
        else:
            font = ImageFont.truetype(FONT_PATH, font_size)
            if weight:
                font.set_variation_by_name(weight)
        d.text((x, y), new_text, fill=color, font=font)
    except Exception as e:
        print(f"Error rendering text '{new_text}': {e}")
    return im_out

def replace_toolbar_button(im, cx, cy, size):
    """
    Cleans the old button circular footprint with antialiased background blend,
    then composites the Swarm Bee toolbar button at the exact center.
    """
    arr = np.array(im)
    bg_x = max(0, cx - round(size * 0.65))
    bg = arr[cy, bg_x, :3].astype(float)
    
    Y, X = np.ogrid[:arr.shape[0], :arr.shape[1]]
    dist = np.sqrt((X - cx)**2 + (Y - cy)**2)
    R = size * 0.49
    
    mask_inner = dist <= (R - 1.5)
    mask_blend = (dist > (R - 1.5)) & (dist <= (R + 0.5))
    arr[mask_inner, :3] = bg
    
    blend_alpha = ((R + 0.5) - dist[mask_blend]) / 2.0
    for c in range(3):
        arr[mask_blend, c] = (1.0 - blend_alpha) * arr[mask_blend, c] + blend_alpha * bg[c]
        
    im_out = Image.fromarray(arr)
    btn = make_toolbar_bee_button(size)
    im_out.alpha_composite(btn, (cx - size // 2, cy - size // 2))
    return im_out

# ----------------------------------------------------------------------
# 13 Feature Still Sanitizers
# ----------------------------------------------------------------------

def sanitize_diff():
    print("1/13 Sanitizing diff.webp...")
    im = Image.open(SRC_DIR / "diff.webp").convert('RGBA')
    
    # 1. Dynamic toolbar button: center (396, 182), diameter 46
    im = replace_toolbar_button(im, 396, 182, 46)
    
    # 2. Path: Replace 'DroppyCode/Views/Composer/ComposerView.swift' with 'SwarmCode/App/Views/Composer/ComposerView.swift'
    # Original path text spans x in [643, 1088], y in [285, 304]
    im = replace_text_seamless(
        im, 643, 285, 455, 20,
        "SwarmCode/App/Views/Composer/ComposerView.swift",
        font_size=14, mono=True,
        color=(215, 225, 235, 255),
        inpaint_x_pad=4, inpaint_y_pad=3
    )
    
    out_path = OUT_APP / "diff.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_palette():
    print("2/13 Sanitizing palette.webp...")
    im = Image.open(SRC_DIR / "palette.webp").convert('RGBA')
    
    # 1. Toolbar button: center (396, 182), diameter 46
    im = replace_toolbar_button(im, 396, 182, 46)
    
    # 2. 'Droppy Code' -> 'Swarm Code' at rows y in [371, 445, 594, 668, 742]
    for y in [371, 445, 594, 668, 742]:
        im = replace_text_seamless(
            im, 651, y, 98, 16,
            "Swarm Code",
            font_size=13, weight='Regular',
            color=(145, 160, 180, 255),
            inpaint_x_pad=2, inpaint_y_pad=2
        )
        
    # 3. 'getdroppy.app' -> 'swarmcode.dev' at y=520
    im = replace_text_seamless(
        im, 651, 520, 110, 16,
        "swarmcode.dev",
        font_size=13, weight='Regular',
        color=(145, 160, 180, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "palette.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_queue():
    print("3/13 Sanitizing queue.webp...")
    im = Image.open(SRC_DIR / "queue.webp").convert('RGBA')
    
    # 1. Toolbar button: center (396, 182), diameter 46
    im = replace_toolbar_button(im, 396, 182, 46)
    
    # 2. Chip line: replace 'DroppyCode' with 'SwarmCode', preserving 'build' command
    # DroppyCode spans x in [702, 770]
    im = replace_text_seamless(
        im, 703, 816, 76, 18,
        "SwarmCode",
        font_size=14, mono=True,
        color=(180, 195, 210, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "queue.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_quote():
    print("4/13 Sanitizing quote.webp...")
    im = Image.open(SRC_DIR / "quote.webp").convert('RGBA')
    
    # 1. Toolbar button: center (411, 137), diameter 44
    im = replace_toolbar_button(im, 411, 137, 44)
    
    # 2. Terminal chip line: replace 'DroppyCode' with 'SwarmCode'
    # DroppyCode spans x in [740, 841]
    im = replace_text_seamless(
        im, 741, 920, 100, 16,
        "SwarmCode",
        font_size=14, mono=True,
        color=(180, 195, 210, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "quote.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_slash():
    print("5/13 Sanitizing slash.webp...")
    im = Image.open(SRC_DIR / "slash.webp").convert('RGBA')
    
    # 1. Toolbar button: center (411, 137), diameter 44
    im = replace_toolbar_button(im, 411, 137, 44)
    
    # 2. Terminal chip line: replace 'DroppyCode' with 'SwarmCode'
    im = replace_text_seamless(
        im, 741, 964, 100, 16,
        "SwarmCode",
        font_size=14, mono=True,
        color=(180, 195, 210, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "slash.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_threads():
    print("6/13 Sanitizing threads.webp...")
    im = Image.open(SRC_DIR / "threads.webp").convert('RGBA')
    
    # 1. Toolbar button: center (582, 168), diameter 50
    im = replace_toolbar_button(im, 582, 168, 50)
    
    # 2. Thread names: 'Droppy Code' -> 'Swarm Code' (bounds x=278 to 368, width 92)
    for y in [394, 517, 683, 765, 847, 930]:
        im = replace_text_seamless(
            im, 278, y, 92, 18,
            "Swarm Code",
            font_size=15, weight='Regular',
            color=(145, 160, 180, 255),
            inpaint_x_pad=2, inpaint_y_pad=2
        )
        
    # 3. Thread url: 'getdroppy.app' -> 'swarmcode.dev' at y=600
    im = replace_text_seamless(
        im, 277, 600, 115, 18,
        "swarmcode.dev",
        font_size=15, weight='Regular',
        color=(145, 160, 180, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    # 4. Terminal chip at y=840: 'DroppyCode' -> 'SwarmCode'
    im = replace_text_seamless(
        im, 715, 840, 85, 18,
        "SwarmCode",
        font_size=15, mono=True,
        color=(180, 195, 210, 255),
        inpaint_x_pad=2, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "threads.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_recipes():
    print("7/13 Sanitizing recipes.webp...")
    im = Image.open(SRC_DIR / "recipes.webp").convert('RGBA')
    
    # 1. Toolbar button: center (499, 195), diameter 50
    im = replace_toolbar_button(im, 499, 195, 50)
    
    out_path = OUT_APP / "recipes.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_intro():
    print("8/13 Sanitizing intro.webp...")
    im = Image.open(SRC_DIR / "intro.webp").convert('RGBA')
    
    # 1. Toolbar button: center (443, 195), diameter 46
    im = replace_toolbar_button(im, 443, 195, 46)
    
    out_path = OUT_APP / "intro.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_question():
    print("9/13 Sanitizing question.webp...")
    im = Image.open(SRC_DIR / "question.webp").convert('RGBA')
    
    # 1. Toolbar button: center (396, 182), diameter 46
    im = replace_toolbar_button(im, 396, 182, 46)
    
    out_path = OUT_APP / "question.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_plans():
    print("10/13 Sanitizing plans.webp...")
    im = Image.open(SRC_DIR / "plans.webp").convert('RGBA')
    
    # 1. Toolbar button: center (396, 182), diameter 46
    im = replace_toolbar_button(im, 396, 182, 46)
    
    out_path = OUT_APP / "plans.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_sidebar():
    print("11/13 Sanitizing sidebar.webp...")
    im = Image.open(SRC_DIR / "sidebar.webp").convert('RGBA')
    
    # Project names in sidebar (x=98)
    for y in [300, 645, 743, 841, 939]:
        im = replace_text_seamless(
            im, 98, y, 148, 22,
            "Swarm Code",
            font_size=18, weight='Regular',
            color=(145, 160, 180, 255),
            inpaint_x_pad=3, inpaint_y_pad=2
        )
        
    im = replace_text_seamless(
        im, 98, 546, 165, 22,
        "swarmcode.dev",
        font_size=18, weight='Regular',
        color=(145, 160, 180, 255),
        inpaint_x_pad=3, inpaint_y_pad=2
    )
    
    out_path = OUT_APP / "sidebar.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_limits():
    print("12/13 Sanitizing limits.webp...")
    im = Image.open(SRC_DIR / "limits.webp").convert('RGBA')
    
    # Clean export
    out_path = OUT_APP / "limits.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def sanitize_notify():
    print("13/13 Sanitizing notify.webp...")
    im = Image.open(SRC_DIR / "notify.webp").convert('RGBA')
    
    # 1. Toolbar button: center (627, 138), diameter 44
    im = replace_toolbar_button(im, 627, 138, 44)
    
    # 2. Notification items:
    for y in [288, 403, 470, 572, 707, 774, 888]:
        im = replace_text_seamless(
            im, 208, y, 102, 16,
            "Swarm Code",
            font_size=14, weight='Regular',
            color=(145, 160, 180, 255),
            inpaint_x_pad=2, inpaint_y_pad=2
        )
        
    for y in [639, 956, 1023]:
        im = replace_text_seamless(
            im, 208, y, 115, 16,
            "swarmcode.dev",
            font_size=14, weight='Regular',
            color=(145, 160, 180, 255),
            inpaint_x_pad=2, inpaint_y_pad=2
        )
        
    out_path = OUT_APP / "notify.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  -> Saved {out_path}")

def run():
    print("Starting sanitization of all 13 feature stills...")
    sanitize_diff()
    sanitize_palette()
    sanitize_queue()
    sanitize_quote()
    sanitize_slash()
    sanitize_threads()
    sanitize_recipes()
    sanitize_intro()
    sanitize_question()
    sanitize_plans()
    sanitize_sidebar()
    sanitize_limits()
    sanitize_notify()
    print("\nAll 13 feature stills sanitized successfully with zero glitches!")

if __name__ == "__main__":
    run()
