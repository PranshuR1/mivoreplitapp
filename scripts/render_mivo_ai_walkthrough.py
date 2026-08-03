#!/usr/bin/env python3

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "mivo-ai-walkthrough"
SCENES = [
    "intro",
    "infrastructure",
    "personalized-plan",
    "patterns",
    "adaptive-interventions",
    "experiments",
    "outcomes",
    "close",
]


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def duration(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(json.loads(result.stdout)["format"]["duration"])


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rendered_scenes: list[Path] = []

    for index, slug in enumerate(SCENES, start=1):
        number = f"{index:02d}"
        narration = OUTPUT / f"narration-{number}.txt"
        raw_audio = OUTPUT / f"voice-{number}-raw.aiff"
        audio = OUTPUT / f"voice-{number}.m4a"
        image = OUTPUT / f"scene-{number}-{slug}.png"
        video = OUTPUT / f"video-{number}.mp4"

        run(
            "say",
            "-v",
            "Samantha",
            "-r",
            "174",
            "-f",
            str(narration),
            "-o",
            str(raw_audio),
        )
        run(
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(raw_audio),
            "-af",
            "adelay=350,apad=pad_dur=0.85",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            str(audio),
        )

        scene_duration = duration(audio)
        fade_out = max(0.5, scene_duration - 0.35)
        frame_count = max(1, round(scene_duration * 30))
        video_filter = (
            "scale=1940:1091,"
            f"zoompan=z='min(zoom+0.000045,1.018)':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            f"d={frame_count}:s=1920x1080:fps=30,"
            "fade=t=in:st=0:d=0.25,"
            f"fade=t=out:st={fade_out:.3f}:d=0.35,"
            "format=yuv420p"
        )
        run(
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-loop",
            "1",
            "-i",
            str(image),
            "-i",
            str(audio),
            "-vf",
            video_filter,
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-t",
            f"{scene_duration:.3f}",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "18",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-movflags",
            "+faststart",
            str(video),
        )
        rendered_scenes.append(video)

    manifest = OUTPUT / "video-manifest.txt"
    manifest.write_text(
        "".join(f"file '{scene.name}'\n" for scene in rendered_scenes),
        encoding="utf-8",
    )
    final_video = OUTPUT / "Mivo_AI_Product_Walkthrough.mp4"
    run(
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(manifest),
        "-c",
        "copy",
        "-movflags",
        "+faststart",
        str(final_video),
    )

    for path in OUTPUT.glob("voice-*-raw.aiff"):
        path.unlink()

    print(final_video)
    print(f"duration={duration(final_video):.2f}s")


if __name__ == "__main__":
    main()
