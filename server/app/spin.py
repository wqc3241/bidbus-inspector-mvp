"""ffmpeg fallback for the 36 spin frames, when the phone did not send them."""
import subprocess
from pathlib import Path

FRAMES = 36


def frame(k: int) -> str:
    return f"spin-{k:02d}.jpg"


def have_frames(d: Path) -> bool:
    return all((d / frame(k)).exists() for k in range(1, FRAMES + 1))


def ensure_frames(d: Path) -> None:
    missing = [k for k in range(1, FRAMES + 1) if not (d / frame(k)).exists()]
    videos = sorted(d.glob("video_360.*"))
    if not missing or not videos:
        return
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(videos[0])],
                           capture_output=True, text=True, check=True, timeout=60)
    duration = float(probe.stdout.strip())
    for k in missing:  # frame k at (k - 0.5) / 36 of the video
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", f"{(k - 0.5) / FRAMES * duration:.3f}", "-i", str(videos[0]),
                        "-frames:v", "1", "-vf", "scale=1600:-2", str(d / frame(k))], check=True, timeout=120)
