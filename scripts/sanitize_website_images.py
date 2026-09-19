#!/usr/bin/env python3
"""
Sanitizes all website images and tour assets for Swarm Code:
1. Replaces all Droppy horse/unicorn icons with the official Swarm Bee logo.
2. Replaces all occurrences of "Droppy Code", "getdroppy.app", and "DroppyCode build"
   with "Swarm Code", "swarmcode.dev", and "SwarmCode build".
3. Uses surgical per-column vertical interpolation for seamless text replacement without rectangular box artifacts.
4. Correctly locates each window's toolbar button center (no hardcoding wrong coordinates across different images).
5. Outputs pristine WebP files directly into website/assets/app/ and website/assets/app/tour/
   so the marketing site runs 100% locally with zero external dependencies.
6. Updates in-app xcassets tour imagesets.
"""

import os
import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build.noindex" / "remote_audit"
OUT_APP = ROOT / "website" / "assets" / "app"
OUT_TOUR = OUT_APP / "tour"
OUT_THEMES = OUT_APP / "themes"
XCASSETS = ROOT / "SwarmCode" / "Resources" / "Assets.xcassets"
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"

OUT_APP.mkdir(parents=True, exist_ok=True)
OUT_TOUR.mkdir(parents=True, exist_ok=True)
OUT_THEMES.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------------
# Glyphs & Badges
# ----------------------------------------------------------------------

def make_toolbar_bee_button(size, badge_num=None):
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


def make_bee_glyph_aa(size, color, with_check=False):
    hires = size * 4
    img = Image.new('RGBA', (hires, hires), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = hires / 24.0
    
    # Antennae
    d.line([(10*s, 3.5*s), (7.5*s, 1*s)], fill=color, width=round(1.8*s))
    d.line([(14*s, 3.5*s), (16.5*s, 1*s)], fill=color, width=round(1.8*s))
    d.ellipse([(6.5*s, 0.5*s), (8.5*s, 2.5*s)], fill=color)
    d.ellipse([(15.5*s, 0.5*s), (17.5*s, 2.5*s)], fill=color)
    
    # Wings
    d.ellipse([(3*s, 4*s), (11*s, 11*s)], fill=color)
    d.ellipse([(13*s, 4*s), (21*s, 11*s)], fill=color)
    
    # Body
    d.polygon([
        (12*s, 4*s), (16.5*s, 7*s), (16*s, 14*s), (12*s, 21.5*s), (8*s, 14*s), (7.5*s, 7*s)
    ], fill=color)
    
    # Body stripes (dark translucent)
    bg_dark = (20, 24, 30, 200)
    d.line([(8*s, 10*s), (16*s, 10*s)], fill=bg_dark, width=round(1.8*s))
    d.line([(8.8*s, 14*s), (15.2*s, 14*s)], fill=bg_dark, width=round(1.8*s))
    d.line([(9.8*s, 17.5*s), (14.2*s, 17.5*s)], fill=bg_dark, width=round(1.6*s))
    
    if with_check:
        # Green check circle at bottom-right
        cx, cy, cr = 17*s, 17*s, 5.5*s
        d.ellipse([(cx - cr, cy - cr), (cx + cr, cy + cr)], fill=(34, 197, 94, 255), outline=(20, 24, 30, 255), width=max(1, round(1.2*s)))
        # White checkmark
        d.line([(cx - 2.5*s, cy), (cx - 0.5*s, cy + 2*s), (cx + 2.5*s, cy - 2*s)], fill=(255, 255, 255, 255), width=max(1, round(1.5*s)))
        
    return img.resize((size, size), Image.Resampling.LANCZOS)


def inpaint_line(arr, x0, x1, y0, y1):
    """Interpolates vertically between (y0, x) and (y1, x) across all columns in [x0, x1]."""
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


def replace_text_seamless(im, x, y, w, h, new_text, font_size=13, weight='Regular', color=(145, 160, 180, 255), mono=False):
    arr = np.array(im, dtype=np.float32)
    inpaint_line(arr, x - 2, x + w + 2, y - 2, y + h + 2)
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


# ----------------------------------------------------------------------
# Sanitizers
# ----------------------------------------------------------------------

def sanitize_window():
    print("Sanitizing window.webp...")
    im = Image.open(SRC_DIR / "window.webp").convert('RGBA')
    
    # 1. Header toolbar button: center is (611, 144), diameter 34
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (611 - 17, 144 - 17))
    
    # 2. Terminal line: replace 'DroppyCode build' seamlessly using cloned background gradient
    arr = np.array(im)
    bg_strip = arr[695:698, 835:935]
    bg_fill = np.tile(bg_strip.mean(axis=0, keepdims=True), (15, 1, 1)).astype(np.uint8)
    arr[700:715, 835:935] = bg_fill
    im = Image.fromarray(arr)
    
    d = ImageDraw.Draw(im)
    font_term = ImageFont.truetype(FONT_PATH, 12)
    font_term.set_variation_by_name('Bold')
    d.text((836, 701), "SwarmCode build", fill=(160, 172, 185, 255), font=font_term)
    
    # 3. Modal title: replace 'Droppy Code' with 'Swarm Code' seamlessly
    c_modal = im.getpixel((1025, 930))
    d.rectangle([(1020, 905), (1345, 960)], fill=c_modal)
    
    font_modal = ImageFont.truetype(FONT_PATH, 46)
    font_modal.set_variation_by_name('Bold')
    d.text((1025, 910), "Swarm Code", fill=(245, 248, 252, 255), font=font_modal)
    
    out_path = OUT_TOUR / "window.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_hero():
    print("Sanitizing hero.webp...")
    im = Image.open(SRC_DIR / "hero.webp").convert('RGBA')
    
    # 1. Header toolbar button: center (458, 148), diameter 44, badge 2
    btn = make_toolbar_bee_button(44, badge_num=2)
    im.alpha_composite(btn, (458 - 22, 148 - 22))
    
    # 2. Status card 'Sending out 3 heads'
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([(872, 452), (908, 488)], radius=6, fill=(45, 55, 68, 255))
    wbee = make_bee_glyph_aa(26, (230, 240, 250, 240))
    im.alpha_composite(wbee, (876, 456))
    
    # 3. Sent out Hank (orange), Walter (blue), Ada (green)
    obee = make_bee_glyph_aa(24, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(24, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(24, (34, 197, 94, 255))
    
    d.rounded_rectangle([(876, 614), (908, 644)], radius=5, fill=(35, 42, 50, 255))
    im.alpha_composite(obee, (880, 616))
    
    d.rounded_rectangle([(876, 674), (908, 704)], radius=5, fill=(35, 42, 50, 255))
    im.alpha_composite(bbee, (880, 676))
    
    d.rounded_rectangle([(876, 734), (908, 764)], radius=5, fill=(35, 42, 50, 255))
    im.alpha_composite(gbee, (880, 736))
    
    # Hank is done
    d.rounded_rectangle([(876, 816), (908, 846)], radius=5, fill=(45, 52, 60, 255))
    im.alpha_composite(obee, (880, 818))
    
    # 4. Floating subagent panel (bottom left):
    # In [horse] 3 [v] pill, replace ONLY the horse icon at (251, 953):
    d.rounded_rectangle([(246, 948), (275, 980)], radius=4, fill=(53, 62, 70, 255))
    im.alpha_composite(make_bee_glyph_aa(22, (230, 240, 250, 240)), (248, 952))
    # Digit '3' stays untouched at x=285!
    
    # 'Ada working': x=384, y=952
    d.rounded_rectangle([(378, 946), (416, 982)], radius=6, fill=(48, 62, 64, 255))
    im.alpha_composite(gbee, (383, 950))
    
    # 5. Effort slider icon (bottom right): x=1815, y=1111
    d.rounded_rectangle([(1810, 1106), (1838, 1132)], radius=4, fill=(48, 54, 62, 255))
    im.alpha_composite(make_bee_glyph_aa(20, (230, 240, 250, 240)), (1814, 1109))
    
    # 6. Prompt chip icon (bottom bar): x=1895, y=1324
    d.rounded_rectangle([(1890, 1318), (1918, 1344)], radius=4, fill=(38, 44, 52, 255))
    im.alpha_composite(make_bee_glyph_aa(18, (230, 240, 250, 240)), (1894, 1321))
    
    out_path = OUT_TOUR / "hero.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_hydra():
    print("Sanitizing hydra.webp...")
    im = Image.open(SRC_DIR / "hydra.webp").convert('RGBA')
    
    # 1. Header toolbar button: center (511, 168), diameter 44, badge 2
    btn = make_toolbar_bee_button(44, badge_num=2)
    im.alpha_composite(btn, (511 - 22, 168 - 22))
    
    # 2. Status card & pills at x=254
    d = ImageDraw.Draw(im)
    wbee = make_bee_glyph_aa(24, (230, 240, 250, 240))
    obee = make_bee_glyph_aa(22, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(22, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(22, (34, 197, 94, 255))
    
    # Sending out 3 heads
    d.rounded_rectangle([(250, 426), (284, 458)], radius=5, fill=(45, 55, 68, 255))
    im.alpha_composite(wbee, (254, 429))
    
    # Sent out Hank, Walter, Ada
    d.rounded_rectangle([(250, 602), (282, 630)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(obee, (254, 604))
    
    d.rounded_rectangle([(250, 670), (282, 698)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(bbee, (254, 671))
    
    d.rounded_rectangle([(250, 736), (282, 764)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(gbee, (254, 737))
    
    # Hank is done
    d.rounded_rectangle([(250, 824), (282, 854)], radius=4, fill=(45, 52, 60, 255))
    im.alpha_composite(obee, (254, 826))
    
    # Walter and Ada are working (at y=924):
    d.rounded_rectangle([(255, 920), (315, 955)], radius=6, fill=(35, 42, 50, 255))
    im.alpha_composite(bbee, (260, 926))
    im.alpha_composite(gbee, (280, 926))
    
    # Hank finished working (at y=995):
    d.rounded_rectangle([(306, 990), (345, 1030)], radius=6, fill=(45, 52, 60, 255))
    im.alpha_composite(make_bee_glyph_aa(22, (249, 115, 22, 255), with_check=True), (310, 994))
    
    # Floating panel (top right in hydra.webp):
    # In [horse] 3 [v] pill:
    d.rounded_rectangle([(1190, 288), (1225, 320)], radius=4, fill=(53, 62, 70, 255))
    im.alpha_composite(wbee, (1194, 292))
    # Digit '3' stays untouched at 1230!
    
    # Ada working pill:
    d.rounded_rectangle([(1344, 288), (1378, 320)], radius=6, fill=(48, 62, 64, 255))
    im.alpha_composite(gbee, (1348, 292))
    
    out_path = OUT_TOUR / "hydra.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_diff():
    print("Sanitizing diff.webp...")
    im = Image.open(SRC_DIR / "diff.webp").convert('RGBA')
    # Toolbar button at (395, 186)
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (395 - 17, 186 - 17))
    
    # Header path: DroppyCode/Views/Composer/ComposerView.swift
    im = replace_text_seamless(im, 643, 288, 450, 18, "SwarmCode/App/Views/Composer/ComposerView.swift", font_size=15, mono=True, color=(210, 225, 240, 255))
    
    out_path = OUT_APP / "diff.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_palette():
    print("Sanitizing palette.webp...")
    im = Image.open(SRC_DIR / "palette.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (395 - 17, 186 - 17))
    
    for y in [371, 445, 594, 668, 742]:
        im = replace_text_seamless(im, 651, y, 115, 14, "Swarm Code", font_size=13, color=(145, 160, 180, 255))
        
    im = replace_text_seamless(im, 651, 520, 125, 14, "swarmcode.dev", font_size=13, color=(145, 160, 180, 255))
    
    out_path = OUT_APP / "palette.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_queue():
    print("Sanitizing queue.webp...")
    im = Image.open(SRC_DIR / "queue.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (395 - 17, 186 - 17))
    
    im = replace_text_seamless(im, 704, 817, 115, 18, "SwarmCode", font_size=14, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_APP / "queue.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_quote():
    print("Sanitizing quote.webp...")
    im = Image.open(SRC_DIR / "quote.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (411 - 17, 137 - 17))
    
    im = replace_text_seamless(im, 741, 920, 105, 16, "SwarmCode", font_size=14, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_APP / "quote.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_slash():
    print("Sanitizing slash.webp...")
    im = Image.open(SRC_DIR / "slash.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (411 - 17, 137 - 17))
    
    im = replace_text_seamless(im, 741, 964, 105, 16, "SwarmCode", font_size=14, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_APP / "slash.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_slider():
    print("Sanitizing slider.webp...")
    im = Image.open(SRC_DIR / "slider.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (518 - 17, 175 - 17))
    
    im = replace_text_seamless(im, 1143, 666, 160, 44, "Swarm", font_size=32, weight='Bold', color=(240, 245, 250, 255))
    
    out_path = OUT_TOUR / "slider.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_sidebar():
    print("Sanitizing sidebar.webp...")
    im = Image.open(SRC_DIR / "sidebar.webp").convert('RGBA')
    # Sidebar crop has no window toolbar button!
    
    for y in [300, 645, 743, 841, 939]:
        im = replace_text_seamless(im, 98, y, 140, 24, "Swarm Code", font_size=18, weight='Regular', color=(145, 160, 180, 255))
        
    im = replace_text_seamless(im, 98, 546, 170, 24, "swarmcode.dev", font_size=18, weight='Regular', color=(145, 160, 180, 255))
    
    out_path = OUT_APP / "sidebar.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_threads():
    print("Sanitizing threads.webp...")
    im = Image.open(SRC_DIR / "threads.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (573 - 17, 169 - 17))
    
    for y in [394, 517, 683, 765, 847, 930]:
        im = replace_text_seamless(im, 278, y, 115, 20, "Swarm Code", font_size=15, weight='Regular', color=(145, 160, 180, 255))
        
    im = replace_text_seamless(im, 277, 600, 140, 20, "swarmcode.dev", font_size=15, weight='Regular', color=(145, 160, 180, 255))
    im = replace_text_seamless(im, 715, 840, 120, 20, "SwarmCode", font_size=15, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_APP / "threads.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_notify():
    print("Sanitizing notify.webp...")
    im = Image.open(SRC_DIR / "notify.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (630 - 17, 140 - 17))
    
    for y in [288, 403, 470, 572, 707, 774, 888]:
        im = replace_text_seamless(im, 208, y, 110, 18, "Swarm Code", font_size=14, weight='Regular', color=(145, 160, 180, 255))
        
    for y in [639, 956, 1023]:
        im = replace_text_seamless(im, 208, y, 130, 18, "swarmcode.dev", font_size=14, weight='Regular', color=(145, 160, 180, 255))
        
    out_path = OUT_APP / "notify.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_themes():
    print("Sanitizing themes.webp...")
    im = Image.open(SRC_DIR / "themes.webp").convert('RGBA')
    
    # 4 quadrants toolbar buttons: (255, 90), (1295, 90), (255, 737), (1295, 737)
    btn = make_toolbar_bee_button(28)
    im.alpha_composite(btn, (255 - 14, 90 - 14))
    im.alpha_composite(btn, (1295 - 14, 90 - 14))
    im.alpha_composite(btn, (255 - 14, 737 - 14))
    im.alpha_composite(btn, (1295 - 14, 737 - 14))
    
    im = replace_text_seamless(im, 331, 483, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 1370, 483, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 331, 1133, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 1370, 1133, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_TOUR / "themes.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_intro():
    print("Sanitizing intro.webp...")
    im = Image.open(SRC_DIR / "intro.webp").convert('RGBA')
    # Toolbar button at (437, 196)
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (437 - 17, 196 - 17))
    # DO NOT paste any random logo in the chat!
    
    out_path = OUT_APP / "intro.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_panels():
    print("Sanitizing panels.webp...")
    im = Image.open(SRC_DIR / "panels.webp").convert('RGBA')
    # Toolbar button at (411, 137) with badge 2
    btn = make_toolbar_bee_button(42, badge_num=2)
    im.alpha_composite(btn, (411 - 21, 137 - 21))
    
    d = ImageDraw.Draw(im)
    wbee = make_bee_glyph_aa(24, (230, 240, 250, 240))
    obee = make_bee_glyph_aa(22, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(22, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(22, (34, 197, 94, 255))
    
    # Left floating panel (Hank): x=225, y=826
    d.rounded_rectangle([(220, 820), (248, 850)], radius=4, fill=(45, 52, 60, 255))
    im.alpha_composite(obee, (224, 824))
    
    # Right floating panel (Ada): x=1504, y=826
    d.rounded_rectangle([(1498, 820), (1528, 850)], radius=4, fill=(48, 62, 64, 255))
    im.alpha_composite(gbee, (1502, 824))
    
    # Main window status rows:
    d.rounded_rectangle([(768, 348), (796, 376)], radius=4, fill=(45, 55, 68, 255))
    im.alpha_composite(wbee, (770, 350))
    
    d.rounded_rectangle([(770, 488), (798, 516)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(obee, (772, 490))
    
    d.rounded_rectangle([(770, 538), (798, 566)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(bbee, (772, 540))
    
    d.rounded_rectangle([(770, 592), (798, 620)], radius=4, fill=(35, 42, 50, 255))
    im.alpha_composite(gbee, (772, 594))
    
    d.rounded_rectangle([(770, 664), (798, 692)], radius=4, fill=(45, 52, 60, 255))
    im.alpha_composite(obee, (772, 666))
    
    out_path = OUT_TOUR / "panels.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_pairs():
    print("Sanitizing pairs.webp...")
    im = Image.open(SRC_DIR / "pairs.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (518 - 17, 175 - 17))
    
    out_path = OUT_TOUR / "pairs.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_recipes():
    print("Sanitizing recipes.webp...")
    im = Image.open(SRC_DIR / "recipes.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (491 - 17, 197 - 17))
    
    out_path = OUT_APP / "recipes.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_question():
    print("Sanitizing question.webp...")
    im = Image.open(SRC_DIR / "question.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (395 - 17, 186 - 17))
    
    out_path = OUT_APP / "question.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_plans():
    print("Sanitizing plans.webp...")
    im = Image.open(SRC_DIR / "plans.webp").convert('RGBA')
    btn = make_toolbar_bee_button(34)
    im.alpha_composite(btn, (395 - 17, 186 - 17))
    
    out_path = OUT_APP / "plans.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_limits():
    print("Sanitizing limits.webp...")
    im = Image.open(SRC_DIR / "limits.webp").convert('RGBA')
    # Limits has no toolbar or Droppy text
    out_path = OUT_APP / "limits.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


# ----------------------------------------------------------------------
# Main Execution
# ----------------------------------------------------------------------

def run():
    sanitize_window()
    sanitize_hero()
    sanitize_hydra()
    sanitize_diff()
    sanitize_palette()
    sanitize_queue()
    sanitize_quote()
    sanitize_slash()
    sanitize_slider()
    sanitize_sidebar()
    sanitize_threads()
    sanitize_notify()
    sanitize_themes()
    sanitize_intro()
    sanitize_panels()
    sanitize_pairs()
    sanitize_recipes()
    sanitize_question()
    sanitize_plans()
    sanitize_limits()
    
    print("\nUpdating in-app xcassets tour images...")
    tour_assets = {
        "tour-welcome@2x.png": OUT_TOUR / "window.webp",
        "tour-hydra@2x.png": OUT_TOUR / "hydra.webp",
        "tour-pairs@2x.png": OUT_TOUR / "pairs.webp",
        "tour-slider@2x.png": OUT_TOUR / "slider.webp",
        "tour-panels@2x.png": OUT_TOUR / "panels.webp",
        "tour-themes@2x.png": OUT_TOUR / "themes.webp",
        "tour-recipes@2x.png": OUT_APP / "recipes.webp",
        "tour-threads@2x.png": OUT_APP / "threads.webp",
    }
    
    for asset_name, webp_source in tour_assets.items():
        folder_name = asset_name.replace("@2x.png", ".imageset")
        target_path = XCASSETS / folder_name / asset_name
        if target_path.parent.exists():
            im = Image.open(webp_source)
            im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
            im_resized.save(target_path)
            print(f"  Updated xcasset: {target_path}")

    print("\nAll images sanitized successfully with zero glitches!")

if __name__ == "__main__":
    run()
