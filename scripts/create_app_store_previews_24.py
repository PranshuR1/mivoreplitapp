from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "app-store-previews"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1242, 2688
FONT = "/System/Library/Fonts/SFNS.ttf"
ROUNDED_FONT = "/System/Library/Fonts/SFNSRounded.ttf"

CREAM = "#FAF3E8"
SURFACE = "#F0E4CC"
WHITE = "#FFFFFF"
BROWN = "#5C3317"
HERO = "#8B4E28"
ORANGE = "#D4872A"
BLUE = "#4A6FA5"
MUTED = "#C8A882"
INK = "#161008"


def font(size: int, rounded: bool = False):
    return ImageFont.truetype(ROUNDED_FONT if rounded else FONT, size=size)


def fit_text(draw, text, max_width, start_size, min_size=44, rounded=False):
    size = start_size
    while size > min_size:
        f = font(size, rounded)
        if draw.textbbox((0, 0), text, font=f)[2] <= max_width:
            return f
        size -= 2
    return font(min_size, rounded)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius, fill=255)
    return mask


def add_phone(canvas, screenshot_path, box, angle=0):
    x, y, width, height = box
    source = Image.open(screenshot_path).convert("RGB")
    source = ImageOps.fit(source, (width - 34, height - 34), method=Image.Resampling.LANCZOS)

    shell = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (width + 100, height + 100), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((50, 50, width + 18, height + 18), 104, fill=(22, 16, 12, 75))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    shell.alpha_composite(shadow.crop((35, 35, 35 + width, 35 + height)))
    ImageDraw.Draw(shell).rounded_rectangle((0, 0, width - 1, height - 1), 92, fill=INK)
    shell.paste(source, (17, 17), rounded_mask(source.size, 76))

    if angle:
        shell = shell.rotate(angle, Image.Resampling.BICUBIC, expand=True)
        x -= (shell.width - width) // 2
        y -= (shell.height - height) // 2
    canvas.alpha_composite(shell, (x, y))


def add_brand(draw, light=False):
    color = CREAM if light else BROWN
    logo = Image.open(ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png").convert("RGB")
    logo = ImageOps.fit(logo, (118, 118), method=Image.Resampling.LANCZOS)
    logo_canvas = Image.new("RGB", (118, 118), CREAM)
    logo_canvas.paste(logo, (0, 0))
    draw._image.paste(logo_canvas, (76, 50), rounded_mask((118, 118), 26))
    draw.text((224, 82), "MIVO", font=font(31, True), fill=color)
    draw.text((344, 86), "SCREEN TIME, WITH INTENTION", font=font(22), fill=color)


def add_motif(draw, motif, palette):
    main, faint = palette
    if motif == "rings":
        for i, width in enumerate((9, 7, 5)):
            pad = i * 46
            draw.arc((880 + pad, 120 + pad, 1370 - pad, 610 - pad), 105, 286, fill=faint, width=width)
        draw.ellipse((1035, 276, 1099, 340), fill=main)
    elif motif == "bars":
        for i, h in enumerate((54, 102, 156, 218, 282)):
            x = 920 + i * 58
            draw.rounded_rectangle((x, 510 - h, x + 30, 510), 15, fill=main if i > 2 else faint)
    elif motif == "path":
        pts = [(850, 430), (940, 320), (1035, 390), (1128, 230), (1228, 276)]
        draw.line(pts, fill=faint, width=12, joint="curve")
        for x, y in pts:
            draw.ellipse((x - 17, y - 17, x + 17, y + 17), fill=main)
    elif motif == "grid":
        for row in range(4):
            for col in range(6):
                x, y = 870 + col * 62, 210 + row * 62
                fill = main if row * 6 + col < 9 else faint
                draw.rounded_rectangle((x, y, x + 42, y + 42), 10, fill=fill)


def make_preview(index, headline, subhead, screenshot, background, foreground, accent, motif, angle=0):
    canvas = Image.new("RGBA", (W, H), background)
    draw = ImageDraw.Draw(canvas)
    light = foreground == CREAM
    add_brand(draw, light=light)
    add_motif(draw, motif, (accent, MUTED if not light else "#E5C9A0"))

    lines = headline.split("\n")
    y = 190
    for line in lines:
        f = fit_text(draw, line, 1080, 92, min_size=68, rounded=True)
        draw.text((76, y), line, font=f, fill=foreground)
        y += 104
    sub_font = fit_text(draw, subhead, 1030, 36, min_size=30)
    draw.text((78, y + 22), subhead, font=sub_font, fill=foreground)

    phone_y = max(620, y + 155)
    add_phone(canvas, screenshot, (171, phone_y, 900, 2030), angle=angle)
    canvas.convert("RGB").save(OUT / f"Mivo_Preview_{index:02d}.png", quality=96)


def main():
    existing = ROOT / "AppStoreRealPreviews"
    specs = [
        ("Pause before\nautopilot.", "A five-second reset before the scroll begins.", "/tmp/mivo-onboarding.png", CREAM, BROWN, ORANGE, "rings", -1),
        ("See your time\ndifferently.", "Turn invisible hours into something you can act on.", "/tmp/mivo-time.png", HERO, CREAM, ORANGE, "grid", 1),
        ("Choose what gets\nyour attention.", "Protect the apps most likely to pull you into a loop.", "/tmp/mivo-apps.png", BLUE, CREAM, ORANGE, "path", -1),
        ("Social, without the\nendless feed.", "Message, search, and watch longer videos with Mivo Clear.", "/tmp/mivo-clear.png", CREAM, BROWN, BLUE, "bars", 1),
        ("See the pattern.\nBreak the loop.", "Daily behavior, triggers, and progress in one clear view.", "/tmp/mivo-patterns.png", ORANGE, CREAM, BLUE, "path", -1),
        ("Get your weekly\ntruth.", "Compare your days and notice what actually changed.", "/tmp/mivo-weekly-chart.png", CREAM, BROWN, ORANGE, "bars", 1),
        ("Measure the time\nyou got back.", "Mivo turns small choices into a visible weekly effect.", "/tmp/mivo-weekly-impact.png", HERO, CREAM, BLUE, "rings", -1),
        ("Reflect without\nthe guilt.", "Notice what was useful, what drifted, and what to try next.", existing / "preview-08-reflection.png", BLUE, CREAM, ORANGE, "grid", 1),
        ("Build a rhythm\nthat fits you.", "Personal schedules and calmer late-night protection.", "/tmp/mivo-settings.png", CREAM, BROWN, BLUE, "path", -1),
        ("Recover time for\nwhat matters.", "Tiny pauses add up to days you can choose differently.", "/tmp/mivo-recovery.png", ORANGE, CREAM, HERO, "rings", 1),
    ]
    for i, spec in enumerate(specs, 1):
        make_preview(i, *spec)
    print(OUT)


if __name__ == "__main__":
    main()
