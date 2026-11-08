"""Media on disk under MEDIA_DIR/{inspection_id}/{name}."""
import hashlib
import os
import re
from pathlib import Path

from . import config

MAX_BYTES = 200 * 1024 * 1024
NAME = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9._-]{0,199}")
DOCS = {"license": "ph_license.jpg", "registration": "ph_reg.jpg", "family_proof": "ph_family.jpg"}
PRIVATE = {"ph_license", "ph_reg", "ph_family", "signature"}  # stored, never served on a report


class TooLarge(Exception):
    pass


def ok_name(name: str) -> bool:
    return bool(NAME.fullmatch(name)) and ".." not in name


def folder(inspection_id: str) -> Path:
    return config.MEDIA_DIR / inspection_id


def expected(record: dict) -> list[str]:
    """every file the phone uploads, except the spin frames (the ffmpeg fallback covers those)"""
    names = [p["file"] for p in record.get("photos", []) if not p.get("skipped") and p.get("file")]
    names += [v["file"] for v in record.get("videos", []) if v.get("file")]
    names += [d["file"] for d in record.get("damages", []) if d.get("file")]
    names.append("signature.png")
    names += [f for k, f in DOCS.items() if (record.get("documents") or {}).get(k) == "taken on site"]
    return list(dict.fromkeys(names))


async def save(inspection_id: str, name: str, chunks) -> tuple[int, str]:
    """stream to a temp file, then rename; returns (size, sha256)"""
    d = folder(inspection_id)
    d.mkdir(parents=True, exist_ok=True)
    tmp, h, size = d / f".{name}.part", hashlib.sha256(), 0
    try:
        with open(tmp, "wb") as f:
            async for chunk in chunks:
                size += len(chunk)
                if size > MAX_BYTES:
                    raise TooLarge
                h.update(chunk)
                f.write(chunk)
        os.replace(tmp, d / name)
    finally:
        tmp.unlink(missing_ok=True)
    return size, h.hexdigest()
