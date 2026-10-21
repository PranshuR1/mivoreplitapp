from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "output" / "mivo-still-app-store" / "captures"
OUT = ROOT / "output" / "mivo-still-app-store" / "previews"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1320, 2868
FONT = "/System/Library/Fonts/SFNS.ttf"
ROUNDED_FONT = "/System/Library/Fonts/SFNSRounded.ttf"

CREAM = "#FAF3E8"
BROWN = "#5C3317"
INK = "#161008"
HERO = "#8B4E28"
ORANGE = "#D4872A"
BLUE = "#4A6FA5"
MUTED = "#C8A882"
GREEN = "#5F7F63"


def font(size: int, rounded: bool = False, bold: bool = False):
    path = ROUNDED_FONT if rounded else FONT
    return ImageFont.truetype(path, size=size, layout_engine=ImageFont.Layout.RAQM)


def fit_text(draw, text, max_width, start_size, min_size=48, rounded=False):
    size = start_size
    while size > min_size:
        candidate = font(size, rounded=rounded)
        if draw.textbbox((0, 0), text, font=candidate)[2] <= max_width:
            return candidate
        size -= 2
    return font(min_size, rounded=rounded)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius, fill=255)
    return mask


def add_brand(canvas, foreground):
    draw = ImageDraw.Draw(canvas)
    logo_path = ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png"
    logo = Image.open(logo_path).convert("RGB")
    logo = ImageOps.fit(logo, (110, 110), method=Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (110, 110), CREAM)
    tile.paste(logo, (0, 0))
    canvas.paste(tile, (76, 54), rounded_mask(tile.size, 25))
    draw.text((216, 76), "MIVO", font=font(32, rounded=True), fill=foreground)
    draw.rounded_rectangle((338, 74, 518, 119), 12, fill=foreground)
    draw.text((365, 84), "MIVO STILL", font=font(19), fill=CREAM if foreground != CREAM else INK)


def add_motif(draw, motif, accent, faint):
    if motif == "still-rings":
        center = (1110, 325)
        for radius, width in ((82, 8), (132, 7), (184, 6)):
            box = (center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius)
            draw.arc(box, 100, 330, fill=faint, width=width)
        draw.ellipse((1079, 294, 1141, 356), fill=accent)
    elif motif == "face-down":
        for index in range(3):
            y = 180 + index * 70
            x = 1005 + index * 12
            draw.line((x, y, 1110, y + 58, 1215 - index * 12, y), fill=faint, width=9, joint="curve")
        draw.rounded_rectangle((1084, 430, 1136, 486), 16, fill=accent)
    elif motif == "pause":
        draw.rounded_rectangle((1030, 195, 1080, 420), 25, fill=accent)
        draw.rounded_rectangle((1122, 195, 1172, 420), 25, fill=accent)
        for radius in (130, 182):
            draw.arc((1101 - radius, 307 - radius, 1101 + radius, 307 + radius), 230, 490, fill=faint, width=7)
    elif motif == "lock":
        draw.rounded_rectangle((1010, 260, 1200, 440), 34, outline=faint, width=10)
        draw.arc((1040, 150, 1170, 330), 180, 360, fill=faint, width=13)
        draw.ellipse((1084, 317, 1126, 359), fill=accent)
        draw.rounded_rectangle((1098, 344, 1112, 392), 7, fill=accent)
    elif motif == "streak":
        heights = (72, 122, 174, 236, 306)
        for index, height in enumerate(heights):
            x = 930 + index * 62
            draw.rounded_rectangle((x, 490 - height, x + 34, 490), 17, fill=accent if index >= 3 else faint)
        draw.ellipse((1170, 124, 1214, 168), fill=accent)


def add_phone(canvas, screenshot_path, box, angle=0):
    x, y, width, height = box
    screenshot = Image.open(screenshot_path).convert("RGB")
    screenshot = ImageOps.fit(screenshot, (width - 34, height - 34), method=Image.Resampling.LANCZOS)

    shadow = Image.new("RGBA", (width + 140, height + 140), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((56, 48, width + 84, height + 86), 112, fill=(12, 8, 5, 82))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))

    phone = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    phone.alpha_composite(shadow.crop((48, 40, 48 + width, 40 + height)))
    ImageDraw.Draw(phone).rounded_rectangle((0, 0, width - 1, height - 1), 98, fill=INK)
    phone.paste(screenshot, (17, 17), rounded_mask(screenshot.size, 80))

    if angle:
        phone = phone.rotate(angle, Image.Resampling.BICUBIC, expand=True)
        x -= (phone.width - width) // 2
        y -= (phone.height - height) // 2
    canvas.alpha_composite(phone, (x, y))


def make_preview(index, headline, subhead, capture, background, foreground, accent, motif, angle=0):
    canvas = Image.new("RGBA", (W, H), background)
    draw = ImageDraw.Draw(canvas)
    add_brand(canvas, foreground)
    add_motif(draw, motif, accent, MUTED if foreground != CREAM else "#E6C99F")

    y = 214
    for line in headline.split("\n"):
        title_font = fit_text(draw, line, 1110, 96, min_size=70, rounded=True)
        draw.text((76, y), line, font=title_font, fill=foreground)
        y += 108

    sub_font = fit_text(draw, subhead, 1100, 37, min_size=30)
    draw.text((78, y + 22), subhead, font=sub_font, fill=foreground)

    phone_y = max(650, y + 155)
    add_phone(canvas, CAPTURES / capture, (174, phone_y, 972, 2112), angle=angle)
    canvas.convert("RGB").save(OUT / f"Mivo_Still_Preview_{index:02d}.png", quality=97)


def make_contact_sheet():
    paths = sorted(OUT.glob("Mivo_Still_Preview_*.png"))
    thumb_w, thumb_h = 330, 717
    gap = 18
    sheet = Image.new("RGB", (thumb_w * 3 + gap * 4, thumb_h * 2 + gap * 3), INK)
    for index, path in enumerate(paths):
        image = ImageOps.fit(Image.open(path).convert("RGB"), (thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = gap + (index % 3) * (thumb_w + gap)
        y = gap + (index // 3) * (thumb_h + gap)
        sheet.paste(image, (x, y))
    sheet.save(OUT.parent / "previews-contact-sheet.png", quality=95)


def main():
    specs = [
        (
            "Put it down.\nGet into focus.",
            "Mivo Still counts the minutes your phone stays face-down.",
            "setup.png", CREAM, BROWN, ORANGE, "still-rings", -1,
        ),
        (
            "Face-down.\nFocus on.",
            "The countdown begins only when your phone is still.",
            "faceDown.png", BLUE, CREAM, ORANGE, "face-down", 1,
        ),
        (
            "The timer moves\nwhen you don't.",
            "Stay off your phone and watch focused minutes add up.",
            "active.png", HERO, CREAM, ORANGE, "still-rings", -1,
        ),
        (
            "Pick it up.\nThe timer pauses.",
            "No fake progress. Put it back down to keep going.",
            "paused.png", CREAM, BROWN, ORANGE, "pause", 1,
        ),
        (
            "Lock every app.\nNo early exit.",
            "Choose the exact time. The timer is the only way back in.",
            "lockMode.png", ORANGE, CREAM, INK, "lock", -1,
        ),
        (
            "Build a streak\nof real focus.",
            "See focused minutes, pickups, and consistency over time.",
            "complete.png", BLUE, CREAM, GREEN, "streak", 1,
        ),
    ]
    for index, spec in enumerate(specs, 1):
        make_preview(index, *spec)
    make_contact_sheet()
    print(OUT)


if __name__ == "__main__":
    main()
