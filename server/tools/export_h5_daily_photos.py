#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

from export_person_photo import APP_ROOT, export_random, materialize_generated_image, visual_editorial

DAILY_ROOT = APP_ROOT / "ipad" / "data" / "h5_daily_photos"
ARCHIVE_ROOT = DAILY_ROOT / "archive"
EDITORIAL_FIELDS = ("poster_title", "poster_english", "ai_caption", "poster_accent")

# Keep new batches editorial and colorful even when Photos has no title/description.
# The caption is grounded in the exported photo's available scene metadata; the
# renderer then uses the accent as the title/rule color.
EDITORIAL_PALETTE = (
    ("#FF7F9E", "MEMORY IN MOTION"),
    ("#78D6C6", "A BRIGHT DAY"),
    ("#FFD166", "LIGHT ON THE WAY"),
    ("#8DB7FF", "A MOMENT TO KEEP"),
    ("#C7A6FF", "COLOR IN FRAME"),
    ("#FF9B70", "WARMTH IN FOCUS"),
)


def editorialize(item: dict, slot: int) -> dict:
    """Create stable, scene-grounded poster copy for a freshly exported photo."""
    raw = " ".join(str(item.get(key) or "").strip() for key in ("title", "description"))
    digest = hashlib.sha1(str(item.get("asset_id") or slot).encode("utf-8")).digest()
    accent, english = EDITORIAL_PALETTE[digest[0] % len(EDITORIAL_PALETTE)]
    if raw:
        caption = raw.rstrip("。！？") + "。"
        title = raw[:8]
    else:
        orientation = "横幅" if item.get("orientation") == "landscape" else "人像"
        place = str(item.get("place_display") or "").strip()
        place_hint = f"，地点在{place}" if place else ""
        caption = f"{orientation}照片记录了当时的人物与环境{place_hint}。"
        title = "光影留痕" if orientation == "人像" else "风景入镜"
    item.update({"poster_title": title, "poster_english": english, "ai_caption": caption, "poster_accent": accent})
    return item


def has_complete_editorial(payload: dict, count: int) -> bool:
    items = payload.get("items") or []
    return len(items) >= count and all(
        all(str(item.get(field) or "").strip() for field in EDITORIAL_FIELDS)
        for item in items[:count]
    )


def archive_previous_sets(current_day: str) -> list[str]:
    """Move every prior dated batch into permanent date-keyed storage."""
    ARCHIVE_ROOT.mkdir(parents=True, exist_ok=True)
    archived: list[str] = []
    for source in sorted(DAILY_ROOT.iterdir()):
        if not source.is_dir() or source.name in {current_day, ARCHIVE_ROOT.name}:
            continue
        if not source.name[:4].isdigit() or not (source / "manifest.json").exists():
            continue
        target = ARCHIVE_ROOT / source.name
        if target.exists():
            target = ARCHIVE_ROOT / f"{source.name}-{datetime.now().strftime('%H%M%S')}"
        shutil.move(str(source), str(target))
        manifest_path = target / "manifest.json"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for item in manifest.get("items") or []:
                old_name = Path(str(item.get("image_path") or item.get("image_url") or "")).name
                archived_image = target / old_name
                item["image_path"] = str(archived_image)
                item["image_url"] = f"/assets/h5-photo/archive/{target.name}/{old_name}"
            manifest["archived_at"] = datetime.now().isoformat()
            manifest["archive_directory"] = str(target)
            tmp = manifest_path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
            tmp.replace(manifest_path)
        except Exception:
            # The original files remain preserved even if metadata repair fails.
            pass
        archived.append(target.name)
    return archived


def build_daily_set(person: str = "方宇轩", count: int = 20, force: bool = False) -> dict:
    day = datetime.now().date().isoformat()
    archived_sets: list[str] = []
    day_dir = DAILY_ROOT / day
    manifest_path = day_dir / "manifest.json"
    if manifest_path.exists() and not force:
        cached = json.loads(manifest_path.read_text(encoding="utf-8"))
        if has_complete_editorial(cached, count):
            return cached

    day_dir.mkdir(parents=True, exist_ok=True)
    items: list[dict] = []
    seen: set[str] = set()
    # A balanced batch guarantees both purpose-built layouts are exercised.
    orientations = (["portrait", "landscape"] * ((count + 1) // 2))[:count]
    for slot, orientation in enumerate(orientations, 1):
        payload = None
        for _attempt in range(8):
            try:
                candidate = export_random(person, orientation)
            except Exception:
                # A stale/missing Photos cache entry must not abort the full batch.
                continue
            asset_id = str(candidate.get("asset_id") or "")
            candidate_path = Path(str(candidate.get("image_path") or ""))
            if asset_id and asset_id not in seen and candidate_path.exists():
                payload = candidate
                seen.add(asset_id)
                break
        if payload is None:
            continue
        source = Path(str(payload.get("image_path") or ""))
        if not source.exists():
            continue
        suffix = source.suffix.lower() or ".jpg"
        target = day_dir / f"photo-{slot:02d}{suffix}"
        shutil.copy2(source, target)
        safe = {
            key: payload.get(key)
            for key in (
                "person", "orientation", "asset_id", "date_display", "width", "height",
                "title", "description", "favorite", "place_display", "camera_make",
                "camera_model", "f_number", "focal_length_mm", "exposure_seconds",
                "iso", "pixel_width", "pixel_height",
            )
        }
        safe["image_path"] = str(target)
        safe["image_url"] = f"/assets/h5-photo/{day}/{target.name}"
        try:
            editorial = visual_editorial(source, str(safe.get("asset_id") or ""))
        except Exception:
            # The export must remain usable when the optional vision client is unavailable;
            # the scheduled editorial validator supplies reviewed copy afterward.
            editorial = {}
        safe.update({
            "poster_title": editorial.get("poster_title") or "待审照片",
            "poster_english": editorial.get("poster_english") or "PHOTO PENDING REVIEW",
            "ai_caption": editorial.get("ai_caption") or "待完成场景描述。",
            "poster_accent": editorial.get("poster_accent") or "#94A3B8",
            "caption_asset_id": editorial.get("caption_asset_id") or safe.get("asset_id"),
            "caption_source": editorial.get("caption_source") or "pending_review",
        })
        items.append(safe)

    if len(items) < count:
        raise RuntimeError(f"Only exported {len(items)} unique photos; expected {count}")
    manifest = {
        "date": day,
        "person": person,
        "count": len(items),
        "created_at": datetime.now().isoformat(),
        "archived_previous_sets": archived_sets,
        "items": items,
    }
    tmp = manifest_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(manifest_path)

    # Archive only after today's complete set is safely committed, so the
    # previous set remains available if Photos export fails or times out.
    archived_sets = archive_previous_sets(day)
    if archived_sets:
        manifest["archived_previous_sets"] = archived_sets
        tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(manifest_path)

    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--person", default="方宇轩")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    print(json.dumps(build_daily_set(args.person, max(1, args.count), args.force), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
