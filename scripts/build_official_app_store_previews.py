from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Official Previews App Store"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1320, 2868
SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

CREAM = "#FAF3E8"
BROWN = "#5C3317"
RUST = "#8B4E28"
ORANGE = "#D4872A"
BLUE = "#4A6FA5"
MUTED = "#C8A882"
INK = "#161008"


def font(size: int, rounded: bool = False):
    return ImageFont.truetype(SF_ROUNDED if rounded else SF, size=size)


def fit_text(draw, text, max_width, start_size, min_size=42, rounded=False):
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
    logo = ImageOps.fit(Image.open(logo_path).convert("RGB"), (118, 118), Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (118, 118), CREAM)
    tile.paste(logo, (0, 0))
    canvas.paste(tile, (76, 50), rounded_mask(tile.size, 26))
    draw.text((224, 82), "MIVO", font=font(31, rounded=True), fill=foreground)
    draw.text((344, 86), "SCREEN TIME, WITH INTENTION", font=font(22), fill=foreground)


def add_motif(canvas, motif, accent, foreground):
    draw = ImageDraw.Draw(canvas)
    faint = MUTED if foreground == BROWN else "#E5C9A0"
    if motif == "rings":
        for index, width in enumerate((9, 7, 5)):
            pad = index * 46
            draw.arc((930 + pad, 118 + pad, 1430 - pad, 618 - pad), 105, 286, fill=faint, width=width)
        draw.ellipse((1085, 274, 1149, 338), fill=accent)
    elif motif == "bars":
        for index, height in enumerate((54, 102, 156, 218, 282)):
            x = 970 + index * 58
            fill = accent if index > 2 else faint
            draw.rounded_rectangle((x, 520 - height, x + 30, 520), 15, fill=fill)
    elif motif == "path":
        points = [(900, 440), (990, 330), (1085, 400), (1178, 240), (1278, 286)]
        draw.line(points, fill=faint, width=12, joint="curve")
        for x, y in points:
            draw.ellipse((x - 17, y - 17, x + 17, y + 17), fill=accent)
    elif motif == "grid":
        for row in range(4):
            for col in range(6):
                x, y = 920 + col * 62, 214 + row * 62
                fill = accent if row * 6 + col < 9 else faint
                draw.rounded_rectangle((x, y, x + 42, y + 42), 10, fill=fill)


def add_copy(canvas, headline, subhead, foreground):
    draw = ImageDraw.Draw(canvas)
    y = 205
    for line in headline.split("\n"):
        title_font = fit_text(draw, line, 1160, 98, min_size=70, rounded=True)
        draw.text((76, y), line, font=title_font, fill=foreground)
        y += 112
    sub_font = fit_text(draw, subhead, 1130, 38, min_size=30)
    draw.text((78, y + 22), subhead, font=sub_font, fill=foreground)
    return max(660, y + 150)


def add_phone(canvas, screenshot_path, y, angle=0):
    width, height = 930, 2070
    x = (W - width) // 2
    source = Image.open(screenshot_path).convert("RGB")
    source = ImageOps.fit(source, (width - 34, height - 34), Image.Resampling.LANCZOS)

    phone = Image.new("RGBA", (width + 130, height + 130), (0, 0, 0, 0))
    shadow = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((70, 65, width + 54, height + 62), 110, fill=(22, 16, 12, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    phone.alpha_composite(shadow)

    shell = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shell_draw = ImageDraw.Draw(shell)
    shell_draw.rounded_rectangle((0, 0, width - 1, height - 1), 96, fill=INK)
    shell.paste(source, (17, 17), rounded_mask(source.size, 79))
    phone.alpha_composite(shell, (45, 35))

    if angle:
        phone = phone.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    x -= (phone.width - width) // 2
    y -= (phone.height - height) // 2
    canvas.alpha_composite(phone, (x, y))


def make_preview(spec, index):
    canvas = Image.new("RGBA", (W, H), spec["background"])
    foreground = spec["foreground"]
    add_brand(canvas, foreground)
    add_motif(canvas, spec["motif"], spec["accent"], foreground)
    phone_y = add_copy(canvas, spec["headline"], spec["subhead"], foreground)

    add_phone(canvas, spec["screenshot"], phone_y, spec.get("angle", 0))

    output = OUT / f"{index:02d}-{spec['slug']}.png"
    canvas.convert("RGB").save(output, quality=98)
    return output


def make_contact_sheet(paths):
    thumb_w, thumb_h, gap = 264, 574, 14
    rows = (len(paths) + 4) // 5
    sheet = Image.new("RGB", (5 * thumb_w + 6 * gap, rows * thumb_h + (rows + 1) * gap), INK)
    for index, path in enumerate(paths):
        preview = ImageOps.fit(Image.open(path).convert("RGB"), (thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = gap + (index % 5) * (thumb_w + gap)
        y = gap + (index // 5) * (thumb_h + gap)
        sheet.paste(preview, (x, y))
    sheet.save(OUT / "Official-Preview-Set-Contact-Sheet.png", quality=97)


def main():
    ai = ROOT / "output" / "mivo-v24-ai-complete" / "captures"
    walkthrough = ROOT / "output" / "mivo-v24-walkthrough" / "captures"
    still = ROOT / "output" / "mivo-still-app-store" / "captures"
    old_real = ROOT / "AppStoreRealPreviews"

    specs = [
        dict(slug="Use-Your-Phone-On-Purpose", headline="Use your phone.\nOn purpose.", subhead="Pause, choose why, then decide how long.", screenshot=walkthrough / "interventions.png", background=CREAM, foreground=BROWN, accent=ORANGE, motif="rings", angle=-1),
        dict(slug="Mivo-Clear", headline="Keep the useful parts.\nLose the feed.", subhead="Messages, search, playlists, and longer videos—without the loop.", screenshot=walkthrough / "clear.png", background=BLUE, foreground=CREAM, accent=ORANGE, motif="bars", angle=1),
        dict(slug="Mivo-Still", headline="Put it down.\nFocus starts.", subhead="The timer moves only while your phone stays face-down.", screenshot=still / "faceDown.png", background=CREAM, foreground=BROWN, accent=ORANGE, motif="path", angle=0),
        dict(slug="Protect-What-Pulls-You-In", headline="Protect what\npulls you in.", subhead="Choose the apps that deserve a pause before opening.", screenshot=ai / "onboarding-apps.png", background=RUST, foreground=CREAM, accent=ORANGE, motif="grid", angle=-1),
        dict(slug="See-A-Week-Of-Your-Life", headline="See a week\nof your life.", subhead="Turn invisible screen time into a picture you can act on.", screenshot=ai / "onboarding-time.png", background=CREAM, foreground=BROWN, accent=BLUE, motif="bars", angle=1),
        dict(slug="Turn-Patterns-Into-A-Plan", headline="Turn patterns\ninto a plan.", subhead="Try one change for seven days and see what actually helps.", screenshot=ai / "experiments.png", background=BLUE, foreground=CREAM, accent=ORANGE, motif="path", angle=-1),
        dict(slug="Focus-That-Fits-The-Moment", headline="Focus that fits\nthe moment.", subhead="Choose a reset, a sprint, or a deeper work session.", screenshot=ai / "focus.png", background=CREAM, foreground=BROWN, accent=ORANGE, motif="rings", angle=1),
        dict(slug="Know-If-It-Was-Worth-It", headline="Know if it\nwas worth it.", subhead="A quick reflection turns scrolling into something you can learn from.", screenshot=old_real / "preview-08-reflection.png", background=RUST, foreground=CREAM, accent=ORANGE, motif="grid", angle=-1),
        dict(slug="See-Your-Week-Clearly", headline="See your week.\nWithout the guilt.", subhead="Spot your quietest days, busiest moments, and real progress.", screenshot=walkthrough / "weekly-chart.png", background=BLUE, foreground=CREAM, accent=ORANGE, motif="bars", angle=1),
        dict(slug="Watch-Your-Time-Come-Back", headline="Watch your time\ncome back.", subhead="Small pauses compound into hours you can use differently.", screenshot=ai / "onboarding-recovery.png", background=ORANGE, foreground=CREAM, accent=BLUE, motif="rings", angle=-1),
    ]

    expected = {f"{index:02d}-{spec['slug']}.png" for index, spec in enumerate(specs, 1)}
    for existing in OUT.glob("[0-9][0-9]-*.png"):
        if existing.name not in expected:
            existing.unlink()

    paths = [make_preview(spec, index) for index, spec in enumerate(specs, 1)]
    make_contact_sheet(paths)
    print(OUT)


if __name__ == "__main__":
    main()
