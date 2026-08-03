#!/usr/bin/env python3

from pathlib import Path
from textwrap import wrap

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "mivo-ai-walkthrough"
OUT.mkdir(parents=True, exist_ok=True)

WIDTH = 1920
HEIGHT = 1080

CREAM = "#FAF3E8"
CREAM_DARK = "#F0DFC0"
WHITE = "#FFFDFC"
BROWN = "#5B2E18"
ORANGE = "#D88922"
ORANGE_DARK = "#B76018"
BLUE = "#5279B2"
BLUE_DARK = "#365E96"
GREEN = "#3E783A"
MUTED = "#B99872"
LINE = "#E3CDAE"
BLACK = "#19120E"

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"


def font(size: int, rounded: bool = False):
    return ImageFont.truetype(FONT_ROUNDED if rounded else FONT_REGULAR, size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius, fill=255)
    return mask


def draw_wrapped(draw, text, xy, size, color, max_width, spacing=10, rounded=False):
    x, y = xy
    chosen_font = font(size, rounded)
    lines = []
    for paragraph in text.split("\n"):
        if not paragraph:
            lines.append("")
            continue
        current = ""
        for word in paragraph.split():
            candidate = f"{current} {word}".strip()
            if draw.textbbox((0, 0), candidate, font=chosen_font)[2] <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    line_height = size + spacing
    for line in lines:
        draw.text((x, y), line, font=chosen_font, fill=color)
        y += line_height
    return y


def background(accent=ORANGE):
    image = Image.new("RGB", (WIDTH, HEIGHT), CREAM)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 18, HEIGHT), fill=accent)
    draw.ellipse((1420, -500, 2220, 300), outline=LINE, width=3)
    draw.ellipse((1510, -410, 2130, 210), outline=LINE, width=3)
    draw.ellipse((-280, 830, 250, 1360), outline=LINE, width=3)
    return image


def add_brand(image, label="AI PRODUCT WALKTHROUGH"):
    draw = ImageDraw.Draw(image)
    logo_path = ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png"
    logo = Image.open(logo_path).convert("RGB").resize((72, 72), Image.Resampling.LANCZOS)
    image.paste(logo, (74, 56), rounded_mask((72, 72), 15))
    draw.text((166, 68), "MIVO", font=font(28), fill=BROWN)
    draw.text((278, 73), label, font=font(19), fill=ORANGE_DARK)
    draw.line((74, 150, 1846, 150), fill=LINE, width=2)
    draw.rounded_rectangle((1630, 60, 1844, 112), radius=26, fill=WHITE, outline=LINE, width=2)
    draw.ellipse((1652, 77, 1670, 95), fill=GREEN)
    draw.text((1685, 72), "LIVE IN iOS", font=font(18), fill=BROWN)


def add_phone(image, screenshot_path, xy=(1270, 175), height=825, crop=None):
    screenshot = Image.open(screenshot_path).convert("RGB")
    if crop:
        screenshot = screenshot.crop(crop)
    ratio = height / screenshot.height
    width = int(screenshot.width * ratio)
    screenshot = screenshot.resize((width, height), Image.Resampling.LANCZOS)

    frame = Image.new("RGBA", (width + 30, height + 30), (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle(
        (0, 0, frame.width - 1, frame.height - 1),
        radius=42,
        fill="#15100D",
    )
    frame.paste(screenshot, (15, 15), rounded_mask((width, height), 32))

    shadow = Image.new("RGBA", (frame.width + 90, frame.height + 90), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (45, 45, frame.width + 44, frame.height + 44),
        radius=48,
        fill=(67, 37, 19, 80),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    image.paste(shadow, (xy[0] - 45, xy[1] - 35), shadow)
    image.paste(frame, xy, frame)


def pill(draw, xy, text, fill=WHITE, text_color=BROWN, outline=LINE):
    x, y = xy
    label_font = font(19)
    box = draw.textbbox((0, 0), text, font=label_font)
    width = box[2] + 44
    draw.rounded_rectangle((x, y, x + width, y + 48), radius=24, fill=fill, outline=outline, width=2)
    draw.text((x + 22, y + 12), text, font=label_font, fill=text_color)
    return x + width


def bullet(draw, y, title, detail, color=ORANGE):
    draw.ellipse((88, y + 7, 108, y + 27), fill=color)
    draw.text((132, y), title, font=font(29, rounded=True), fill=BROWN)
    draw_wrapped(draw, detail, (132, y + 43), 22, MUTED, 900, spacing=7)


def title_block(draw, eyebrow, title, subtitle):
    draw.text((78, 188), eyebrow.upper(), font=font(21), fill=ORANGE_DARK)
    y = draw_wrapped(draw, title, (78, 230), 60, BROWN, 1040, spacing=7, rounded=True)
    draw_wrapped(draw, subtitle, (78, y + 28), 27, ORANGE_DARK, 1040, spacing=10)


def save(image, index, slug):
    path = OUT / f"scene-{index:02d}-{slug}.png"
    image.save(path)
    return path


def scene_intro():
    image = background(BLUE)
    draw = ImageDraw.Draw(image)
    logo_path = ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png"
    logo = Image.open(logo_path).convert("RGB").resize((190, 190), Image.Resampling.LANCZOS)
    image.paste(logo, (865, 140), rounded_mask((190, 190), 38))
    title_width = draw.textbbox((0, 0), "How AI powers Mivo", font=font(78, rounded=True))[2]
    draw.text(((WIDTH - title_width) / 2, 382), "How AI powers Mivo", font=font(78, rounded=True), fill=BROWN)
    subtitle = "A live product walkthrough of personalized schedules,\nbehavioral insights, and adaptive interventions."
    bbox = draw.multiline_textbbox((0, 0), subtitle, font=font(31), spacing=14, align="center")
    draw.multiline_text(
        ((WIDTH - (bbox[2] - bbox[0])) / 2, 500),
        subtitle,
        font=font(31),
        fill=ORANGE_DARK,
        spacing=14,
        align="center",
    )
    x = 640
    x = pill(draw, (x, 680), "APPLE SCREEN TIME", fill=WHITE) + 18
    pill(draw, (x, 680), "MIVO AI", fill=BLUE, text_color=WHITE, outline=BLUE)
    draw.text((WIDTH / 2, 885), "Pranshu Raithatha + Harsh Mehta", font=font(24), fill=MUTED, anchor="mm")
    return save(image, 1, "intro")


def scene_infrastructure():
    image = background(BLUE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "01 / THE FOUNDATION",
        "Trusted device data.\nPersonalized guidance.",
        "Apple supplies usage and protection. Mivo interprets behavior.",
    )
    bullet(draw, 530, "Apple Screen Time", "DeviceActivity reports usage and FamilyControls protects selected apps.", BLUE)
    bullet(draw, 680, "Mivo AI", "Works from structured behavioral summaries - never messages or social content.", ORANGE)
    add_phone(
        image,
        ROOT / "AppStoreRealPreviews" / "preview-02-home-replacement.png",
        xy=(1370, 170),
        height=830,
    )
    return save(image, 2, "infrastructure")


def scene_plan():
    image = background(ORANGE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "02 / PERSONALIZED SCHEDULES",
        "A plan built from\nreal behavior.",
        "The schedule is personalized after Mivo's observation period.",
    )
    bullet(draw, 545, "Inputs", "Self-report, selected times, three observed days, recent sessions, and the user's goal.", BLUE)
    bullet(draw, 705, "AI output", "A daily target plus 2-4 adaptive scroll windows with personalized timing and minutes.", ORANGE)
    x = pill(draw, (82, 885), "ONLINE LANGUAGE MODEL", fill=BROWN, text_color=WHITE, outline=BROWN)
    pill(draw, (x + 14, 885), "LOCAL FALLBACK", fill=WHITE)
    add_phone(
        image,
        ROOT / "AppStoreRealPreviews" / "preview-03-plan-ready.png",
        xy=(1370, 178),
        height=820,
    )
    return save(image, 3, "personalized-plan")


def scene_patterns():
    image = background(BLUE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "03 / PATTERN INTELLIGENCE",
        "Mivo finds where\ntime disappears.",
        "Behavior is translated into one understandable next step.",
    )
    bullet(draw, 535, "Repeated triggers", "Which intentions and opening patterns appear most often.", ORANGE)
    bullet(draw, 670, "Risk periods", "When sessions become longer, extensions rise, or estimates miss reality.", BLUE)
    bullet(draw, 805, "Daily insight", "A concise explanation of the pattern and a practical suggestion for tomorrow.", ORANGE)
    add_phone(
        image,
        ROOT / "AppStoreRealPreviews" / "preview-04-patterns.png",
        xy=(1370, 175),
        height=825,
    )
    return save(image, 4, "patterns")


def scene_interventions():
    image = background(ORANGE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "04 / ADAPTIVE INTERVENTIONS",
        "The pause changes\nwith the moment.",
        "Useful behavior receives less friction. Repeated drift receives more.",
    )
    bullet(draw, 550, "Adaptive pause", "The first opening uses a five-second pause; repeated openings can increase it to ten.", BLUE)
    bullet(draw, 715, "AI emergency review", "A language model checks whether an unlock reason is concrete and time-sensitive.", ORANGE)
    draw.rounded_rectangle((80, 884, 1050, 969), radius=12, fill=BROWN)
    draw.text((112, 909), "The user always keeps control of approved choices.", font=font(25), fill=WHITE)
    add_phone(
        image,
        ROOT / "AppStoreRealPreviews" / "preview-06-interventions.png",
        xy=(1370, 175),
        height=825,
    )
    return save(image, 5, "adaptive-interventions")


def scene_experiments():
    image = background(BLUE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "05 / SEVEN-DAY EXPERIMENTS",
        "One change.\nMeasured for a week.",
        "Mivo converts a recurring pattern into a test the user approves.",
    )

    cards = [
        ("Protect a risky window", "Measure minutes outside planned times", ORANGE),
        ("Reduce extensions", "Measure extension rate", BLUE),
        ("Pause repeated openings", "Measure cancellation after a pause", BROWN),
    ]
    y = 555
    for idx, (name, metric, color) in enumerate(cards, start=1):
        draw.rounded_rectangle((82, y, 1050, y + 102), radius=12, fill=WHITE, outline=LINE, width=2)
        draw.rounded_rectangle((104, y + 22, 160, y + 78), radius=12, fill=color)
        draw.text((132, y + 50), str(idx), font=font(24), fill=WHITE, anchor="mm")
        draw.text((187, y + 18), name, font=font(28, rounded=True), fill=BROWN)
        draw.text((187, y + 60), metric, font=font(20), fill=ORANGE_DARK)
        y += 122

    panel = Image.new("RGBA", (610, 720), (255, 253, 252, 255))
    pd = ImageDraw.Draw(panel)
    pd.text((44, 42), "ACTIVE EXPERIMENT", font=font(20), fill=BLUE_DARK)
    pd.text((44, 88), "Pause repeated openings", font=font(35, rounded=True), fill=BROWN)
    pd.text((44, 144), "Day 4 of 7", font=font(25), fill=ORANGE_DARK)
    for i in range(7):
        fill = BLUE if i < 4 else CREAM_DARK
        pd.rounded_rectangle((44 + i * 72, 218, 99 + i * 72, 238), radius=10, fill=fill)
    pd.rounded_rectangle((44, 300, 566, 520), radius=16, fill=CREAM, outline=LINE, width=2)
    pd.text((74, 330), "PRIMARY METRIC", font=font(18), fill=MUTED)
    pd.text((74, 375), "Repeated openings", font=font(30, rounded=True), fill=BROWN)
    pd.text((74, 430), "Compared before and after", font=font(22), fill=ORANGE_DARK)
    pd.rounded_rectangle((44, 566, 566, 642), radius=12, fill=BROWN)
    pd.text((305, 604), "Review progress", font=font(24), fill=WHITE, anchor="mm")
    panel = panel.filter(ImageFilter.GaussianBlur(0.2))
    image.paste(panel, (1240, 230), rounded_mask(panel.size, 28))
    return save(image, 6, "experiments")


def scene_outcomes():
    image = background(ORANGE)
    add_brand(image)
    draw = ImageDraw.Draw(image)
    title_block(
        draw,
        "06 / MEASURABLE OUTCOMES",
        "Mivo checks whether\nthe change helped.",
        "The system measures behavior instead of claiming success from app opens.",
    )
    bullet(draw, 545, "Weekly truth", "Scrolling minutes, estimate accuracy, extensions, and planned-window adherence.", BLUE)
    bullet(draw, 700, "Worth-it reflection", "Sessions are measured against whether the user felt the time was worthwhile.", ORANGE)
    bullet(draw, 855, "Before and after", "Experiments report helped, no clear change, or made things worse.", BROWN)
    add_phone(
        image,
        ROOT / "AppStoreRealPreviews" / "preview-10-weekly-report.png",
        xy=(1370, 175),
        height=830,
    )
    return save(image, 7, "outcomes")


def scene_close():
    image = background(BLUE)
    draw = ImageDraw.Draw(image)
    logo_path = ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png"
    logo = Image.open(logo_path).convert("RGB").resize((180, 180), Image.Resampling.LANCZOS)
    image.paste(logo, (870, 130), rounded_mask((180, 180), 36))
    title = "AI personalizes.\nScreen Time protects.\nThe user decides."
    bbox = draw.multiline_textbbox((0, 0), title, font=font(66, rounded=True), spacing=9, align="center")
    draw.multiline_text(
        ((WIDTH - (bbox[2] - bbox[0])) / 2, 365),
        title,
        font=font(66, rounded=True),
        fill=BROWN,
        spacing=9,
        align="center",
    )
    subtitle = "Mivo is live on iOS today."
    bbox2 = draw.textbbox((0, 0), subtitle, font=font(31))
    draw.text(((WIDTH - (bbox2[2] - bbox2[0])) / 2, 665), subtitle, font=font(31), fill=ORANGE_DARK)
    x = 545
    x = pill(draw, (x, 760), "PERSONALIZED PLANS", fill=WHITE) + 16
    x = pill(draw, (x, 760), "ADAPTIVE FRICTION", fill=WHITE) + 16
    pill(draw, (x, 760), "MEASURED EXPERIMENTS", fill=WHITE)
    draw.text((WIDTH / 2, 935), "usemivo.app", font=font(24), fill=BLUE_DARK, anchor="mm")
    return save(image, 8, "close")


def main():
    scenes = [
        scene_intro(),
        scene_infrastructure(),
        scene_plan(),
        scene_patterns(),
        scene_interventions(),
        scene_experiments(),
        scene_outcomes(),
        scene_close(),
    ]

    narration = [
        "This is Mivo, an AI-assisted behavior-change app designed to help people use social media intentionally.",
        "Apple's Screen Time APIs provide trusted device usage and app protection. Mivo's AI layer works from structured behavioral summaries, not messages or social content, to decide what guidance is relevant.",
        "After a three-day observation period, Mivo combines the user's estimate, chosen scrolling times, observed sessions, and personal goal. An online language model generates a personalized daily target and two to four adaptive scrolling windows. A local planning system keeps the experience available if the network is offline.",
        "Mivo analyzes when sessions happen, which intentions repeat, how often users extend, and where their estimates differ from reality. It turns those signals into personalized insights about triggers and higher-risk periods.",
        "Interventions adapt as well. The first opening uses a five-second pause, while repeated openings can increase it to ten seconds. Mivo's language model can also review whether an emergency unlock reason is concrete and time-sensitive.",
        "Mivo can propose one seven-day experiment, such as protecting a risky time window, reducing extensions, or adding friction after repeated openings. The user approves every change, and Mivo compares behavior before and after.",
        "Weekly reports measure scrolling minutes, truth-check accuracy, extensions, planned-window adherence, and whether sessions felt worthwhile. Experiments finish with a clear result rather than a vague promise of improvement.",
        "Mivo uses AI to personalize the intervention, Apple's Screen Time framework to enforce the user's choices, and reflection to keep the user in control. These features are live in Mivo on iOS today.",
    ]

    (OUT / "narration.txt").write_text("\n\n".join(narration), encoding="utf-8")
    for index, text in enumerate(narration, start=1):
        (OUT / f"narration-{index:02d}.txt").write_text(text, encoding="utf-8")

    print("\n".join(str(path) for path in scenes))


if __name__ == "__main__":
    main()
