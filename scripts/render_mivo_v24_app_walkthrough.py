#!/usr/bin/env python3

from __future__ import annotations

import math
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "mivo-v24-walkthrough"
CAPTURES = OUT / "captures"
WIDTH, HEIGHT, FPS = 1920, 1080, 24

CREAM = (249, 244, 235)
PAPER = (255, 252, 247)
BROWN = (88, 45, 23)
ORANGE = (219, 138, 32)
BLUE = (78, 121, 177)
MUTED = (176, 143, 108)
LINE = (228, 211, 188)

REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


@dataclass
class Segment:
    duration: float
    title: str
    subtitle: str
    kicker: str
    image: Path | None = None
    tap: tuple[float, float, float] | None = None
    badge: str | None = None


SEGMENTS = [
    Segment(
        4.0,
        "A smarter pause\nbefore autopilot.",
        "A real walkthrough of Mivo on iOS.",
        "MIVO",
    ),
    Segment(
        6.5,
        "See the full\npicture.",
        "Live Apple Screen Time and today’s personalized plan meet in one calm home screen.",
        "01 / HOME",
        ROOT / "AppStoreRealPreviews" / "preview-02-home-replacement.png",
        (0.52, 0.57, 4.7),
        "LIVE SCREEN TIME",
    ),
    Segment(
        7.0,
        "AI turns observation\ninto a plan.",
        "Mivo combines the user’s estimate, goal, chosen times, and three days of observed behavior.",
        "02 / PERSONALIZED PLAN",
        ROOT / "AppStoreRealPreviews" / "preview-03-plan-ready.png",
        (0.51, 0.89, 5.3),
        "ADAPTIVE WINDOWS",
    ),
    Segment(
        7.0,
        "Find where the\ntime disappears.",
        "Patterns surface repeated triggers, longer sessions, and the periods most likely to pull the user back in.",
        "03 / PATTERNS",
        ROOT / "AppStoreRealPreviews" / "preview-04-patterns.png",
        (0.81, 0.64, 4.8),
        "BEHAVIOR INSIGHTS",
    ),
    Segment(
        7.0,
        "Pause with a\nclear intention.",
        "The intervention adapts to the moment, while the user still chooses the reason and the amount of time.",
        "04 / INTERVENTIONS",
        ROOT / "AppStoreRealPreviews" / "preview-06-interventions.png",
        (0.50, 0.56, 3.2),
        "ADAPTIVE FRICTION",
    ),
    Segment(
        6.0,
        "Stay aware while\nthe session runs.",
        "Mivo tracks only the approved session and brings the user back when that choice is complete.",
        "05 / LIVE SESSION",
        ROOT / "AppStoreRealPreviews" / "preview-07-active-session.png",
        (0.50, 0.80, 4.2),
        "USER CONTROL",
    ),
    Segment(
        6.0,
        "Turn the session\ninto useful data.",
        "A short reflection records whether the session was intentional and whether it was actually worth it.",
        "06 / REFLECTION",
        ROOT / "AppStoreRealPreviews" / "preview-08-reflection.png",
        (0.50, 0.66, 3.8),
        "WORTH-IT CHECK",
    ),
    Segment(
        7.0,
        "Test one change\nfor seven days.",
        "Users approve a focused experiment. Mivo measures the same rule for a week and reports what changed.",
        "07 / EXPERIMENTS",
        CAPTURES / "experiments.png",
        (0.49, 0.58, 4.7),
        "MEASURED CHANGE",
    ),
    Segment(
        7.0,
        "Progress becomes\nvisible.",
        "Weekly reports compare sessions, total time, extensions, daily rhythm, and estimated impact.",
        "08 / WEEKLY REPORT",
        ROOT / "AppStoreRealPreviews" / "preview-10-weekly-report.png",
        (0.50, 0.45, 4.9),
        "BEFORE + AFTER",
    ),
    Segment(
        7.0,
        "Keep the useful\nparts of social.",
        "Mivo Clear BETA opens focused tools for messaging, search, profiles, playlists, and longer videos.",
        "09 / MIVO CLEAR",
        CAPTURES / "clear.png",
        (0.28, 0.40, 4.8),
        "LESS ENDLESS FEED",
    ),
    Segment(
        4.5,
        "AI personalizes.\nThe user decides.",
        "Mivo is live on iOS.",
        "USEMIVO.APP",
    ),
]


def font(size: int, bold: bool = False, rounded: bool = False) -> ImageFont.FreeTypeFont:
    path = ROUNDED if rounded else BOLD if bold else REGULAR
    return ImageFont.truetype(path, size=size)


def ease(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def text_wrap(draw: ImageDraw.ImageDraw, text: str, selected_font, width: int) -> list[str]:
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split()
        current = ""
        for word in words:
            candidate = word if not current else f"{current} {word}"
            if draw.textbbox((0, 0), candidate, font=selected_font)[2] <= width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def draw_wrapped(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    text: str,
    selected_font,
    fill,
    width: int,
    spacing: int,
) -> int:
    x, y = xy
    lines = text_wrap(draw, text, selected_font, width)
    line_height = selected_font.size + spacing
    for line in lines:
        draw.text((x, y), line, font=selected_font, fill=fill)
        y += line_height
    return y


def rounded_screen(image: Image.Image, target_height: int) -> Image.Image:
    ratio = image.width / image.height
    size = (round(target_height * ratio), target_height)
    resized = image.convert("RGB").resize(size, Image.Resampling.LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=56, fill=255)
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    result.paste(resized, (0, 0), mask)
    return result


def phone_layer(screen: Image.Image, scale: float = 1.0) -> Image.Image:
    pad = 14
    canvas = Image.new(
        "RGBA",
        (screen.width + pad * 2, screen.height + pad * 2),
        (0, 0, 0, 0),
    )
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (0, 0, canvas.width - 1, canvas.height - 1),
        radius=66,
        fill=(32, 25, 21),
    )
    canvas.alpha_composite(screen, (pad, pad))
    if abs(scale - 1.0) > 0.001:
        canvas = canvas.resize(
            (round(canvas.width * scale), round(canvas.height * scale)),
            Image.Resampling.LANCZOS,
        )
    return canvas


def logo_image(size: int) -> Image.Image:
    logo = Image.open(ROOT / "Mivo" / "Assets.xcassets" / "MivoLogo.imageset" / "mivo_logo.png")
    return logo.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def draw_rings(draw: ImageDraw.ImageDraw) -> None:
    for offset in (0, 70, 140):
        draw.arc(
            (WIDTH - 420 - offset, -330 - offset, WIDTH + 270 + offset, 360 + offset),
            20,
            178,
            fill=LINE,
            width=2,
        )
    for offset in (0, 65):
        draw.arc(
            (-280 - offset, HEIGHT - 260 - offset, 310 + offset, HEIGHT + 330 + offset),
            190,
            355,
            fill=LINE,
            width=2,
        )


def render_frame(
    segment: Segment,
    local_t: float,
    segment_index: int,
    screen_cache: dict[Path, Image.Image],
    total_progress: float,
) -> Image.Image:
    frame = Image.new("RGB", (WIDTH, HEIGHT), CREAM)
    draw = ImageDraw.Draw(frame)
    draw_rings(draw)

    intro = ease(local_t / 0.65)
    outro = ease((segment.duration - local_t) / 0.45)
    alpha = min(intro, outro)
    text_x = round(170 - (1.0 - intro) * 70)

    if segment.image is None:
        logo_size = round(116 + 12 * math.sin(min(local_t, 1.2) * math.pi / 1.2))
        logo = logo_image(logo_size)
        frame.paste(logo, ((WIDTH - logo_size) // 2, 170), logo)
        title_font = font(72, bold=True, rounded=True)
        title_lines = segment.title.split("\n")
        y = 350
        for line in title_lines:
            box = draw.textbbox((0, 0), line, font=title_font)
            draw.text(((WIDTH - (box[2] - box[0])) // 2, y), line, font=title_font, fill=BROWN)
            y += 84
        sub_font = font(30)
        box = draw.textbbox((0, 0), segment.subtitle, font=sub_font)
        draw.text(((WIDTH - (box[2] - box[0])) // 2, y + 26), segment.subtitle, font=sub_font, fill=ORANGE)
        kicker_font = font(18, bold=True)
        kicker = segment.kicker
        box = draw.textbbox((0, 0), kicker, font=kicker_font)
        draw.text(
            ((WIDTH - (box[2] - box[0])) // 2, HEIGHT - 118),
            kicker,
            font=kicker_font,
            fill=BLUE,
        )
    else:
        kicker_font = font(18, bold=True)
        draw.text((text_x, 196), segment.kicker, font=kicker_font, fill=BLUE)
        draw.line((text_x, 238, text_x + 76, 238), fill=ORANGE, width=6)

        title_font = font(66, bold=True, rounded=True)
        title_y = draw_wrapped(
            draw,
            (text_x, 282),
            segment.title,
            title_font,
            BROWN,
            730,
            8,
        )
        subtitle_font = font(30)
        draw_wrapped(
            draw,
            (text_x, title_y + 32),
            segment.subtitle,
            subtitle_font,
            ORANGE,
            680,
            12,
        )

        if segment.badge:
            badge_font = font(16, bold=True)
            badge_box = draw.textbbox((0, 0), segment.badge, font=badge_font)
            badge_width = badge_box[2] - badge_box[0] + 42
            badge_y = 800
            draw.rounded_rectangle(
                (text_x, badge_y, text_x + badge_width, badge_y + 52),
                radius=26,
                fill=PAPER,
                outline=LINE,
                width=2,
            )
            draw.text(
                (text_x + 21, badge_y + 16),
                segment.badge,
                font=badge_font,
                fill=BROWN,
            )

        screen = screen_cache[segment.image]
        pulse = 1.0
        if segment.tap:
            tap_time = segment.tap[2]
            tap_distance = abs(local_t - tap_time)
            if tap_distance < 0.22:
                pulse = 1.0 - 0.012 * (1.0 - tap_distance / 0.22)
        phone = phone_layer(screen, pulse)
        phone_x = round(1240 + (1.0 - intro) * 130)
        phone_y = (HEIGHT - phone.height) // 2

        shadow = Image.new("RGBA", frame.size, (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_draw.rounded_rectangle(
            (
                phone_x + 15,
                phone_y + 20,
                phone_x + phone.width + 15,
                phone_y + phone.height + 20,
            ),
            radius=70,
            fill=(67, 38, 24, 65),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(24))
        frame = Image.alpha_composite(frame.convert("RGBA"), shadow)
        phone.putalpha(round(255 * alpha))
        frame.alpha_composite(phone, (phone_x, phone_y))

        if segment.tap:
            tap_x, tap_y, tap_time = segment.tap
            delta = local_t - tap_time
            if -0.18 <= delta <= 0.72:
                normalized = max(0.0, min(1.0, (delta + 0.18) / 0.9))
                radius = round(15 + 50 * ease(normalized))
                ring_alpha = round(220 * (1.0 - normalized))
                content_x = phone_x + 14
                content_y = phone_y + 14
                px = round(content_x + screen.width * tap_x)
                py = round(content_y + screen.height * tap_y)
                overlay = Image.new("RGBA", frame.size, (0, 0, 0, 0))
                overlay_draw = ImageDraw.Draw(overlay)
                overlay_draw.ellipse(
                    (px - radius, py - radius, px + radius, py + radius),
                    outline=(*ORANGE, ring_alpha),
                    width=7,
                )
                overlay_draw.ellipse(
                    (px - 10, py - 10, px + 10, py + 10),
                    fill=(*ORANGE, min(235, ring_alpha + 30)),
                )
                frame = Image.alpha_composite(frame, overlay)

    progress_y = HEIGHT - 28
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle((0, progress_y, WIDTH, HEIGHT), radius=0, fill=PAPER)
    draw.rectangle((0, progress_y, round(WIDTH * total_progress), HEIGHT), fill=BLUE)
    return frame.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    screen_cache: dict[Path, Image.Image] = {}
    for segment in SEGMENTS:
        if segment.image:
            image = Image.open(segment.image)
            screen_cache[segment.image] = rounded_screen(image, 930)

    total_duration = sum(segment.duration for segment in SEGMENTS)
    output = OUT / "Mivo_2.4_Animated_App_Walkthrough.mp4"
    command = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{WIDTH}x{HEIGHT}",
        "-r",
        str(FPS),
        "-i",
        "-",
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "18",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(output),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    elapsed = 0.0
    try:
        for index, segment in enumerate(SEGMENTS):
            frame_count = round(segment.duration * FPS)
            for frame_index in range(frame_count):
                local_t = frame_index / FPS
                total_progress = min(1.0, (elapsed + local_t) / total_duration)
                frame = render_frame(segment, local_t, index, screen_cache, total_progress)
                process.stdin.write(frame.tobytes())
            elapsed += segment.duration
    finally:
        process.stdin.close()
        return_code = process.wait()
        if return_code:
            raise SystemExit(return_code)
    print(output)
    print(f"duration={total_duration:.1f}s")


if __name__ == "__main__":
    main()
