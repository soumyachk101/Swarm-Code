#!/usr/bin/env python3
"""
Surgical Tour Scenes Sanitizer for Swarm Code (Agent 2)

Re-sanitizes all 7 tour scenes in website/assets/app/tour/ from the pristine
ground truth source images in build.noindex/remote_audit/ with:
1. Dynamic, sub-pixel accurate toolbar button replacement (pre-clearing old Droppy rim).
2. Exact center placement (hero at 466, 157 with badge 2; window at 612, 140; hydra at 530, 166).
3. Seamless modal title replacement for window.webp (pure SFNS Bold, no box artifacts).
4. Surgical bee glyphs for Hydra and Subagent pills.
"""

import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build.noindex" / "remote_audit"
OUT_TOUR = ROOT / "website" / "assets" / "app" / "tour"
OUT_APP = ROOT / "website" / "assets" / "app"
XCASSETS = ROOT / "SwarmCode" / "Resources" / "Assets.xcassets"
FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"

OUT_TOUR.mkdir(parents=True, exist_ok=True)
OUT_APP.mkdir(parents=True, exist_ok=True)

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
    
    # Body stripes
    bg_dark = (20, 24, 30, 200)
    d.line([(8*s, 10*s), (16*s, 10*s)], fill=bg_dark, width=round(1.8*s))
    d.line([(8.8*s, 14*s), (15.2*s, 14*s)], fill=bg_dark, width=round(1.8*s))
    d.line([(9.8*s, 17.5*s), (14.2*s, 17.5*s)], fill=bg_dark, width=round(1.6*s))
    
    if with_check:
        cx, cy, cr = 17*s, 17*s, 5.5*s
        d.ellipse([(cx - cr, cy - cr), (cx + cr, cy + cr)], fill=(34, 197, 94, 255), outline=(20, 24, 30, 255), width=max(1, round(1.2*s)))
        d.line([(cx - 2.5*s, cy), (cx - 0.5*s, cy + 2*s), (cx + 2.5*s, cy - 2*s)], fill=(255, 255, 255, 255), width=max(1, round(1.5*s)))
        
    return img.resize((size, size), Image.Resampling.LANCZOS)


def inpaint_line(arr, x0, x1, y0, y1):
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


def replace_toolbar_button(im, cx, cy, size, badge_num=None):
    """
    Clears the old circular footprint with an antialiased radial blend,
    then composites make_toolbar_bee_button at the exact center.
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
    btn = make_toolbar_bee_button(size, badge_num=badge_num)
    im_out.alpha_composite(btn, (cx - size // 2, cy - size // 2))
    return im_out


def replace_glyph(im, cx, cy, size, glyph, clear_bg=True, bg_color=None):
    if clear_bg:
        d = ImageDraw.Draw(im)
        half = size // 2
        bg = bg_color if bg_color else im.getpixel((cx - half - 2, cy))
        d.rounded_rectangle([(cx - half, cy - half), (cx + half, cy + half)], radius=round(size*0.25), fill=bg)
    im.alpha_composite(glyph, (cx - glyph.width // 2, cy - glyph.height // 2))


# ----------------------------------------------------------------------
# 7 Tour Scene Sanitizers
# ----------------------------------------------------------------------

def sanitize_window():
    print("Sanitizing window.webp...")
    im = Image.open(SRC_DIR / "window.webp").convert('RGBA')
    
    # 1. Toolbar button: exact center (612, 140), size 38, no badge
    im = replace_toolbar_button(im, 612, 140, 38, badge_num=None)
    
    # 2. Terminal line: replace 'DroppyCode build' with 'SwarmCode build'
    arr = np.array(im)
    bg_strip = arr[695:698, 835:935]
    bg_fill = np.tile(bg_strip.mean(axis=0, keepdims=True), (15, 1, 1)).astype(np.uint8)
    arr[700:715, 835:935] = bg_fill
    im = Image.fromarray(arr)
    d = ImageDraw.Draw(im)
    font_term = ImageFont.truetype(FONT_PATH, 12)
    font_term.set_variation_by_name('Bold')
    d.text((836, 701), "SwarmCode build", fill=(160, 172, 185, 255), font=font_term)
    
    # 3. Modal title: perfectly seamless interpolation and centering
    arr = np.array(im, dtype=np.float32)
    y0, y1 = 908, 958
    x0, x1 = 740, 1340
    top = arr[y0, x0:x1]
    bot = arr[y1, x0:x1]
    H = y1 - y0
    for i in range(H):
        alpha = i / float(H)
        arr[y0 + i, x0:x1] = (1.0 - alpha) * top + alpha * bot
        
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    font_modal = ImageFont.truetype(FONT_PATH, 44)
    font_modal.set_variation_by_name('Bold')
    text = "Welcome to Swarm Code"
    bbox = d.textbbox((0, 0), text, font=font_modal)
    tw = bbox[2] - bbox[0]
    tx = (2080 - tw) // 2
    d.text((tx, 907), text, fill=(245, 248, 252, 255), font=font_modal)
    
    out_path = OUT_TOUR / "window.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def sanitize_hero():
    print("Sanitizing hero.webp...")
    im = Image.open(SRC_DIR / "hero.webp").convert('RGBA')
    
    # 1. Header toolbar button: exact circle center is (461, 157), diameter 50, badge 2
    size = 50
    hires = size * 4
    img = Image.new('RGBA', (hires, hires), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = hires * 0.04
    d.ellipse([(pad, pad), (hires - pad, hires - pad)], fill=(24, 28, 36, 255))
    rim_w = max(2, round(hires * 0.04))
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=-90, end=0, fill=(240, 140, 180, 240), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=0, end=90, fill=(120, 200, 240, 240), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=90, end=180, fill=(100, 150, 255, 240), width=rim_w)
    d.arc([(pad, pad), (hires - pad, hires - pad)], start=180, end=270, fill=(200, 140, 240, 240), width=rim_w)
    logo = Image.open(f'{XCASSETS}/swarmcode-logo.imageset/swarmcode-logo@2x.png').convert('RGBA')
    bee_size = round(hires * 0.65)
    logo_resized = logo.resize((bee_size, bee_size), Image.Resampling.LANCZOS)
    offset = (hires - bee_size) // 2
    img.alpha_composite(logo_resized, (offset, offset))
    
    # Exact badge matching original coordinates (covers original badge 100%)
    bw = 32 * 4
    bh = 26 * 4
    bcx = (size // 2 + 14) * 4
    bcy = (size // 2 - 16) * 4
    bx = bcx - bw // 2
    by = bcy - bh // 2
    d.rounded_rectangle([(bx, by), (bx + bw, by + bh)], radius=round(bh * 0.45), fill=(59, 130, 246, 255))
    d.rounded_rectangle([(bx, by), (bx + bw, by + bh)], radius=round(bh * 0.45), outline=(255, 255, 255, 140), width=max(1, round(hires * 0.015)))
    bfont = ImageFont.truetype(FONT_PATH, round(bh * 0.68))
    bfont.set_variation_by_name('Bold')
    bbox = d.textbbox((0, 0), '2', font=bfont)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((bx + (bw - tw) // 2, by + (bh - th) // 2 - round(hires * 0.02)), '2', fill=(255, 255, 255, 255), font=bfont)
    btn = img.resize((size, size), Image.Resampling.LANCZOS)
    
    # Pre-clear circular footprint
    cx, cy = 461, 157
    arr = np.array(im)
    bg = arr[157, 410, :3].astype(float)
    Y, X = np.ogrid[:arr.shape[0], :arr.shape[1]]
    dist = np.sqrt((X - cx)**2 + (Y - cy)**2)
    arr[dist <= (size * 0.50), :3] = bg
    im = Image.fromarray(arr)
    im.alpha_composite(btn, (cx - size // 2, cy - size // 2))
    
    # 2. Status card 'Sending out 3 heads' icon: cx=892, cy=470, size 26
    wbee = make_bee_glyph_aa(26, (230, 240, 250, 240))
    replace_glyph(im, 892, 470, 26, wbee, clear_bg=True, bg_color=(45, 55, 68, 255))
    
    # 3. Heads: Hank, Walter, Ada
    obee = make_bee_glyph_aa(24, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(24, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(24, (34, 197, 94, 255))
    
    # Hank: cx=895, cy=632
    replace_glyph(im, 895, 632, 24, obee, clear_bg=True, bg_color=(35, 42, 50, 255))
    # Walter: cx=894, cy=692
    replace_glyph(im, 894, 692, 24, bbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    # Ada: cx=894, cy=752
    replace_glyph(im, 894, 752, 24, gbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    # Hank is done: cx=894, cy=834
    replace_glyph(im, 894, 834, 24, obee, clear_bg=True, bg_color=(45, 52, 60, 255))
    
    # 4. Floating subagent panel (bottom left):
    # [horse] 3 [v] pill: horse at cx=256, cy=960
    pbee = make_bee_glyph_aa(22, (230, 240, 250, 240))
    replace_glyph(im, 256, 960, 22, pbee, clear_bg=True, bg_color=(53, 62, 70, 255))
    # Ada working pill: cx=398, cy=960
    replace_glyph(im, 398, 960, 22, gbee, clear_bg=True, bg_color=(48, 62, 64, 255))
    
    # 5. Effort slider icon (bottom right): cx=1826, cy=1120, size 20
    replace_glyph(im, 1826, 1120, 20, make_bee_glyph_aa(20, (230, 240, 250, 240)), clear_bg=True, bg_color=(48, 54, 62, 255))
    
    # 6. Prompt chip icon (bottom bar): cx=1905, cy=1332, size 18
    replace_glyph(im, 1905, 1332, 18, make_bee_glyph_aa(18, (230, 240, 250, 240)), clear_bg=True, bg_color=(38, 44, 52, 255))
    
    out_path = OUT_TOUR / "hero.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")
    im.convert('RGB').save(OUT_APP / "hero.webp", 'WEBP', quality=95, method=6)
    print(f"  Saved {OUT_APP / 'hero.webp'}")


def sanitize_hydra():
    print("Sanitizing hydra.webp...")
    im = Image.open(SRC_DIR / "hydra.webp").convert('RGBA')
    
    # 1. Header toolbar button: center (530, 166), size 46, badge 2
    im = replace_toolbar_button(im, 530, 166, 46, badge_num=2)
    
    # 2. Subagent status rows:
    wbee = make_bee_glyph_aa(24, (230, 240, 250, 240))
    obee = make_bee_glyph_aa(22, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(22, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(22, (34, 197, 94, 255))
    
    replace_glyph(im, 265, 428, 24, wbee, clear_bg=True, bg_color=(45, 55, 68, 255))
    replace_glyph(im, 270, 620, 22, obee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 270, 687, 22, bbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 270, 751, 22, gbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 270, 842, 22, obee, clear_bg=True, bg_color=(45, 52, 60, 255))
    
    # 3. Floating panel:
    replace_glyph(im, 1202, 293, 22, wbee, clear_bg=True, bg_color=(53, 62, 70, 255))
    replace_glyph(im, 1356, 292, 22, gbee, clear_bg=True, bg_color=(48, 62, 64, 255))
    
    out_path = OUT_TOUR / "hydra.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def sanitize_panels():
    print("Sanitizing panels.webp...")
    im = Image.open(SRC_DIR / "panels.webp").convert('RGBA')
    
    # Toolbar button: center (412, 137), size 42, badge 2
    im = replace_toolbar_button(im, 412, 137, 42, badge_num=2)
    
    wbee = make_bee_glyph_aa(24, (230, 240, 250, 240))
    obee = make_bee_glyph_aa(22, (249, 115, 22, 255))
    bbee = make_bee_glyph_aa(22, (59, 130, 246, 255))
    gbee = make_bee_glyph_aa(22, (34, 197, 94, 255))
    
    # Left floating panel: (234, 835)
    replace_glyph(im, 234, 835, 22, obee, clear_bg=True, bg_color=(45, 52, 60, 255))
    # Right floating panel: (1513, 835)
    replace_glyph(im, 1513, 835, 22, gbee, clear_bg=True, bg_color=(48, 62, 64, 255))
    
    # Main window rows:
    replace_glyph(im, 782, 362, 24, wbee, clear_bg=True, bg_color=(45, 55, 68, 255))
    replace_glyph(im, 784, 502, 22, obee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 784, 552, 22, bbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 784, 606, 22, gbee, clear_bg=True, bg_color=(35, 42, 50, 255))
    replace_glyph(im, 784, 678, 22, obee, clear_bg=True, bg_color=(45, 52, 60, 255))
    
    out_path = OUT_TOUR / "panels.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def sanitize_pairs():
    print("Sanitizing pairs.webp...")
    im = Image.open(SRC_DIR / "pairs.webp").convert('RGBA')
    im = replace_toolbar_button(im, 524, 162, 44, badge_num=None)
    
    out_path = OUT_TOUR / "pairs.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def sanitize_slider():
    print("Sanitizing slider.webp...")
    im = Image.open(SRC_DIR / "slider.webp").convert('RGBA')
    im = replace_toolbar_button(im, 524, 161, 44, badge_num=None)
    
    # Replace 'Droppy' at (1143, 666) with 'Swarm'
    im = replace_text_seamless(im, 1146, 666, 125, 44, "Swarm", font_size=32, weight='Bold', color=(240, 245, 250, 255))
    
    out_path = OUT_TOUR / "slider.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def sanitize_themes():
    print("Sanitizing themes.webp...")
    im = Image.open(SRC_DIR / "themes.webp").convert('RGBA')
    
    # 4 quadrants toolbar buttons:
    im = replace_toolbar_button(im, 262, 94, 30, badge_num=None)
    im = replace_toolbar_button(im, 1302, 92, 30, badge_num=None)
    im = replace_toolbar_button(im, 262, 741, 30, badge_num=None)
    im = replace_toolbar_button(im, 1300, 741, 30, badge_num=None)
    
    # Replace DroppyCode terminal text in quadrants
    im = replace_text_seamless(im, 331, 483, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 1370, 483, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 331, 1133, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    im = replace_text_seamless(im, 1370, 1133, 70, 14, "SwarmCode", font_size=10, mono=True, color=(180, 195, 210, 255))
    
    out_path = OUT_TOUR / "themes.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def run():
    sanitize_window()
    sanitize_hero()
    sanitize_hydra()
    sanitize_panels()
    sanitize_pairs()
    sanitize_slider()
    sanitize_themes()
    print("\nAll 7 tour scenes sanitized successfully with zero glitches!")

if __name__ == "__main__":
    run()
