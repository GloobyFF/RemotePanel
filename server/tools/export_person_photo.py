#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import random
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from PIL import ExifTags, Image

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None

APP_ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = APP_ROOT / "ipad" / "data" / "person_photos"
ARCHIVE_DIR = CACHE_DIR / "archive"
PERSON_NAME = "方宇轩"
VISION_MODEL = os.environ.get("REMOTE_PANEL_VISION_MODEL", "")
VISION_TIMEOUT = float(os.environ.get("REMOTE_PANEL_VISION_TIMEOUT", "45"))


def reverse_place(latitude: float | None, longitude: float | None) -> str:
    """Return only coarse locality fields; never expose precise GPS."""
    if latitude is None or longitude is None:
        return ""
    url = (
        "https://nominatim.openstreetmap.org/reverse?format=jsonv2"
        f"&lat={latitude:.6f}&lon={longitude:.6f}&accept-language=zh-CN"
    )
    commands = [
        ["curl", "-fsSL", "--max-time", "15", "-A", "RemotePanel/1.0", url],
        ["curl", "--proxy", "socks5h://192.168.28.77:1080", "-fsSL", "--max-time", "20", "-A", "RemotePanel/1.0", url],
    ]
    for command in commands:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=25, check=True)
            address = json.loads(result.stdout).get("address", {})
            province = str(address.get("state") or "").strip()
            city = str(address.get("city") or address.get("town") or address.get("county") or "").strip()
            district = str(address.get("suburb") or address.get("city_district") or "").strip()
            parts = []
            for value in (province, city, district):
                if value and value not in parts:
                    parts.append(value)
            return " · ".join(parts[:3])
        except Exception:
            continue
    return ""


def applescript_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def image_metadata(path: Path) -> dict:
    names = [
        "kMDItemAcquisitionMake", "kMDItemAcquisitionModel",
        "kMDItemFNumber", "kMDItemFocalLength",
        "kMDItemExposureTimeSeconds", "kMDItemISOSpeed",
        "kMDItemPixelWidth", "kMDItemPixelHeight",
    ]
    try:
        command = ["mdls", "-plist"]
        for name in names:
            command.extend(["-name", name])
        command.append(str(path))
        result = subprocess.run(command, capture_output=True, timeout=20, check=True)
        data = plistlib.loads(result.stdout)
    except Exception:
        data = {}

    def value(name):
        raw = data.get(name)
        return None if raw in (None, "(null)", "") else raw

    metadata = {
        "camera_make": value("kMDItemAcquisitionMake"),
        "camera_model": value("kMDItemAcquisitionModel"),
        "f_number": value("kMDItemFNumber"),
        "focal_length_mm": value("kMDItemFocalLength"),
        "exposure_seconds": value("kMDItemExposureTimeSeconds"),
        "iso": value("kMDItemISOSpeed"),
        "pixel_width": value("kMDItemPixelWidth"),
        "pixel_height": value("kMDItemPixelHeight"),
    }
    try:
        image = Image.open(path)
        exif = {ExifTags.TAGS.get(key, key): val for key, val in image.getexif().items()}
        metadata["camera_make"] = metadata["camera_make"] or exif.get("Make")
        metadata["camera_model"] = metadata["camera_model"] or exif.get("Model")
        metadata["f_number"] = metadata["f_number"] or exif.get("FNumber")
        metadata["focal_length_mm"] = metadata["focal_length_mm"] or exif.get("FocalLength")
        metadata["exposure_seconds"] = metadata["exposure_seconds"] or exif.get("ExposureTime")
        metadata["iso"] = metadata["iso"] or exif.get("ISOSpeedRatings") or exif.get("PhotographicSensitivity")
        metadata["pixel_width"] = metadata["pixel_width"] or image.width
        metadata["pixel_height"] = metadata["pixel_height"] or image.height
    except Exception:
        pass
    return metadata


def load_hermes_env() -> None:
    env_path = Path.home() / ".hermes" / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        if value and key.strip() not in os.environ:
            os.environ[key.strip()] = value


def vision_clients():
    load_hermes_env()
    candidates: list[tuple[str, str, str]] = []
    env_key = os.environ.get("REMOTE_PANEL_VISION_API_KEY")
    env_url = os.environ.get("REMOTE_PANEL_VISION_BASE_URL")
    if env_key and env_url:
        candidates.append((env_key, env_url, VISION_MODEL or "gpt-5.6-sol"))
    config_path = Path.home() / ".hermes" / "config.yaml"
    if config_path.exists():
        try:
            import yaml
            config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
            model = config.get("model", {}) if isinstance(config.get("model"), dict) else {}
            provider_id = str(model.get("provider") or "")
            providers = config.get("providers", {}) if isinstance(config.get("providers"), dict) else {}
            provider = providers.get(provider_id, {}) if isinstance(providers.get(provider_id), dict) else {}
            key_env = str(provider.get("key_env") or "")
            key = str(model.get("api_key") or provider.get("api_key") or os.environ.get(key_env, ""))
            url = str(model.get("base_url") or provider.get("base_url") or "")
            model_name = VISION_MODEL or str(model.get("default") or provider.get("model") or "gpt-5.6-sol")
            if key and url and not any(item[:2] == (key, url) for item in candidates):
                candidates.append((key, url, model_name))
        except Exception:
            pass
    for key, url, model_name in candidates:
        yield OpenAI(api_key=key, base_url=url, timeout=VISION_TIMEOUT, max_retries=1), model_name


def visual_editorial(path: Path, asset_id: str) -> dict:
    """Describe the actual image once and return stable, asset-bound copy."""
    if OpenAI is None:
        raise RuntimeError("openai client is unavailable")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    last_error = None
    for client, model_name in vision_clients():
        try:
            response = client.chat.completions.create(
                model=model_name,
                temperature=0.4,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": "你是严谨的照片编辑。只描述图片中高度确定、明确可见的主体、动作和环境，不猜身份、关系或精确地点。看不清具体颜色、物件种类或动作时必须用更宽泛的表述；宁可写建筑玩具，也不要臆测成蓝色桥板。返回严格 JSON，不要 markdown。"},
                    {"role": "user", "content": [
                        {"type": "text", "text": "为这张照片设计屏幕文案。返回 JSON: poster_title(2-8个中文字符), poster_english(2-5个英文单词大写), ai_caption(一段12-24个中文字符的两句场景短诗，使用一个逗号分成前后两个完整分句；两句都必须描述图片中明确可见的主体、动作或环境，句尾使用相同或近似韵母，读起来押韵自然；不要让常用词组跨换行被拆开，末句句号收尾), poster_accent(6位十六进制颜色)。短诗必须来自这张图的可见内容，避免空泛鸡汤；不要为了押韵写无法确认的具体物品、颜色、地点或行为。asset_id=" + asset_id},
                        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + encoded, "detail": "low"}},
                    ]},
                ],
            )
            data = json.loads(response.choices[0].message.content or "{}")
            required = ("poster_title", "poster_english", "ai_caption", "poster_accent")
            if not all(str(data.get(key) or "").strip() for key in required):
                raise ValueError("vision response missing editorial fields")
            accent = str(data["poster_accent"])
            if not accent.startswith("#"):
                accent = "#" + accent
            if not re.fullmatch(r"#[0-9A-Fa-f]{6}", accent):
                raise ValueError("vision response returned invalid accent")
            data["poster_accent"] = accent
            data["caption_asset_id"] = asset_id
            data["caption_source"] = "vision"
            return data
        except Exception as exc:
            last_error = exc
    raise RuntimeError(f"all visual captioning providers failed: {last_error}")


def metadata_editorial(payload: dict) -> dict:
    title = str(payload.get("title") or payload.get("description") or "").strip()
    if title:
        return {"poster_title": title[:8], "poster_english": "PHOTO NOTE", "ai_caption": title.rstrip("。！？") + "。", "poster_accent": "#FFD166", "caption_source": "photos-metadata"}
    return {"poster_title": "照片记录", "poster_english": "PHOTO RECORD", "ai_caption": "画面景物留在眼前，\\n此刻光影值得记全。", "poster_accent": "#94A3B8", "caption_source": "unavailable"}


def materialize_generated_image(path: Path) -> Path:
    """Replace a temporary Photos export with a generated, normalized derivative."""
    generated = path.with_name(f"{path.stem}.generated.jpg")
    with Image.open(path) as image:
        image = image.convert("RGB")
        image.thumbnail((1920, 1920), Image.Resampling.LANCZOS)
        image.save(generated, format="JPEG", quality=88, optimize=True)
    path.unlink(missing_ok=True)
    return generated


def archive_payload(payload: dict, image_path: Path) -> tuple[Path, Path]:
    """Preserve only the generated derivative and matching metadata."""
    orientation = str(payload.get("orientation") or "any")
    orientation_dir = ARCHIVE_DIR / orientation
    orientation_dir.mkdir(parents=True, exist_ok=True)
    created = datetime.now().strftime("%Y%m%d-%H%M%S")
    asset_token = hashlib.sha1(str(payload.get("asset_id") or "unknown").encode("utf-8")).hexdigest()[:16]
    stem = f"{created}-{orientation}-{asset_token}"
    archived_image = orientation_dir / f"{stem}{image_path.suffix.lower() or '.jpg'}"
    archived_json = orientation_dir / f"{stem}.json"
    if not archived_image.exists():
        shutil.copy2(image_path, archived_image)
    archived_payload = dict(payload)
    archived_payload["archive_image_path"] = str(archived_image)
    archived_payload["archived_at"] = datetime.now(timezone.utc).isoformat()
    tmp_json = archived_json.with_suffix(".json.tmp")
    tmp_json.write_text(json.dumps(archived_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_json.replace(archived_json)
    return archived_image, archived_json


def export_random(person: str = PERSON_NAME, orientation: str = "any") -> dict:
    if orientation not in {"any", "portrait", "landscape"}:
        raise ValueError(f"unsupported orientation: {orientation}")
    cache_dir = CACHE_DIR / orientation
    cache_json = cache_dir / "current.json"
    cache_dir.mkdir(parents=True, exist_ok=True)
    orientation_test = {
        "any": "true",
        "portrait": "candidateHeight >= candidateWidth",
        "landscape": "candidateWidth > candidateHeight",
    }[orientation]
    # Photos search is the same native search used by Photos.app. Candidate
    # metadata is inspected in Photos; only one rendered image is exported.
    script = f'''
with timeout of 180 seconds
  tell application "Photos"
    set hits to search for "{applescript_quote(person)}"
    if (count of hits) is 0 then error "No Photos search results found"
    set picked to missing value
    repeat 80 times
      set candidate to item (random number from 1 to (count of hits)) of hits
      try
        set fn to filename of candidate as text
        set candidateWidth to width of candidate
        set candidateHeight to height of candidate
        set lowerFn to do shell script "printf %s " & quoted form of fn & " | tr '[:upper:]' '[:lower:]'"
        if lowerFn does not end with ".mov" and lowerFn does not end with ".mp4" and lowerFn does not end with ".m4v" and ({orientation_test}) then
          set picked to candidate
          exit repeat
        end if
      end try
    end repeat
    if picked is missing value then error "No still photo found after random retries"
    set itemId to id of picked as text
    set itemDate to date of picked as text
    set itemFilename to filename of picked as text
    set itemWidth to width of picked as text
    set itemHeight to height of picked as text
    set itemName to ""
    set itemDescription to ""
    set itemFavorite to favorite of picked as text
    try
      set itemName to name of picked as text
    end try
    try
      set itemDescription to description of picked as text
    end try
    set itemLocation to location of picked
    set latText to ""
    set lonText to ""
    try
      set latText to item 1 of itemLocation as text
      set lonText to item 2 of itemLocation as text
    end try
    set exportFolder to POSIX file "{applescript_quote(str(cache_dir))}"
    export {{picked}} to exportFolder using originals false
    return itemId & linefeed & itemDate & linefeed & itemFilename & linefeed & itemWidth & linefeed & itemHeight & linefeed & latText & linefeed & lonText & linefeed & ((count of hits) as text) & linefeed & itemName & linefeed & itemDescription & linefeed & itemFavorite
  end tell
end timeout
'''
    before = {p.resolve() for p in cache_dir.iterdir() if p.is_file() and p.name != cache_json.name}
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=210, check=True)
    parts = result.stdout.rstrip("\n").split("\n")
    if len(parts) < 11:
        raise RuntimeError(f"Unexpected Photos response with {len(parts)} fields")
    after = [p for p in cache_dir.iterdir() if p.is_file() and p.name != cache_json.name and p.resolve() not in before]
    if not after:
        # Photos may overwrite an existing filename; take the newest image.
        after = [p for p in cache_dir.iterdir() if p.is_file() and p.name != cache_json.name]
    if not after:
        raise RuntimeError("Photos export did not create an image")
    exported = max(after, key=lambda p: p.stat().st_mtime)
    suffix = exported.suffix.lower() if exported.suffix else ".jpg"
    asset_token = hashlib.sha1(parts[0].encode("utf-8")).hexdigest()[:16]
    current = cache_dir / f"asset-{asset_token}{suffix}"
    if exported.resolve() != current.resolve():
        exported.replace(current)
    current = materialize_generated_image(current)
    suffix = current.suffix.lower()

    def number(value: str):
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    payload = {
        "person": person,
        "orientation": orientation,
        "photos_search_count": int(parts[7] or 0),
        "asset_id": parts[0],
        "date_display": parts[1],
        "filename": parts[2],
        "width": int(parts[3] or 0),
        "height": int(parts[4] or 0),
        "latitude": number(parts[5]),
        "longitude": number(parts[6]),
        "image_path": str(current),
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "title": "" if parts[8].strip().lower() in {"missing value", "default"} else parts[8].strip(),
        "description": "" if parts[9].strip().lower() in {"default", "missing value"} else parts[9].strip(),
        "favorite": parts[10].strip().lower() == "true",
    }
    payload.update(image_metadata(current))
    payload["place_display"] = reverse_place(payload["latitude"], payload["longitude"])
    try:
        payload.update(visual_editorial(current, payload["asset_id"]))
    except Exception as exc:
        payload.update(metadata_editorial(payload))
        payload["caption_error"] = f"{type(exc).__name__}: {exc}"[:240]
    archive_image, archive_json = archive_payload(payload, current)
    payload["archive_image_path"] = str(archive_image)
    payload["archive_metadata_path"] = str(archive_json)
    tmp_json = cache_json.with_suffix(".json.tmp")
    tmp_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_json.replace(cache_json)
    # Runtime exports can be cleaned after their permanent archive is committed.
    for path in cache_dir.iterdir():
        if path.is_file() and path not in {current, cache_json} and not path.name.endswith(".tmp"):
            path.unlink(missing_ok=True)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--person", default=PERSON_NAME)
    parser.add_argument("--orientation", choices=("any", "portrait", "landscape"), default="any")
    args = parser.parse_args()
    print(json.dumps(export_random(args.person, args.orientation), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
