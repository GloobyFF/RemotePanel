from __future__ import annotations

import json
import re
import time
from datetime import datetime
import urllib.parse
import urllib.request

WEATHER_CODES = {
    0: "晴", 1: "大部晴", 2: "局部多云", 3: "阴", 45: "雾", 48: "雾凇",
    51: "小毛毛雨", 53: "毛毛雨", 55: "强毛毛雨", 61: "小雨", 63: "雨", 65: "大雨",
    71: "小雪", 73: "雪", 75: "大雪", 80: "阵雨", 81: "阵雨", 82: "强阵雨",
    95: "雷暴", 96: "雷暴冰雹", 99: "强雷暴冰雹",
}

WEEKDAYS_ZH = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

# 中国天气网城市代码。当前面板使用上海；未配置城市继续走 Open-Meteo。
CHINA_WEATHER_CITY_CODES = {"shanghai": "101020100", "上海": "101020100"}
CHINA_WEATHER_CODES = {
    "00": "晴", "01": "多云", "02": "阴", "03": "阵雨", "04": "雷阵雨",
    "05": "雷阵雨伴冰雹", "06": "雨夹雪", "07": "小雨", "08": "中雨",
    "09": "大雨", "10": "暴雨", "11": "大暴雨", "12": "特大暴雨",
    "13": "阵雪", "14": "小雪", "15": "中雪", "16": "大雪", "17": "暴雪",
    "18": "雾", "19": "冻雨", "20": "沙尘暴", "29": "浮尘", "30": "扬沙",
    "31": "强沙尘暴", "53": "霾",
}


def _get_json(url: str, timeout: int = 10, proxy: str = "") -> dict:
    if proxy:
        from core.http_fetch import fetch_bytes
        return json.loads(fetch_bytes(url, timeout=timeout, proxy=proxy, headers={"User-Agent": "RemotePanelEInkStudio/0.1"}).decode("utf-8", "ignore"))
    last_error = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "RemotePanelEInkStudio/0.1"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8", "ignore"))
        except Exception as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(0.8 * (attempt + 1))
    raise last_error


def _get_china_weather_script(path: str, timeout: int = 10) -> str:
    url = "http://d1.weather.com.cn/" + path.lstrip("/")
    last_error = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "Mozilla/5.0 RemotePanel/1.0",
                "Referer": "http://www.weather.com.cn/",
            })
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode("utf-8", "ignore")
        except Exception as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(0.8 * (attempt + 1))
    raise last_error


def _script_json(script: str, variable: str) -> dict:
    match = re.search(rf"var\s+{re.escape(variable)}\s*=\s*(\{{.*?\}})(?:;|$)", script, re.S)
    if not match:
        raise ValueError(f"中国天气网响应缺少 {variable}")
    return json.loads(match.group(1))


def _china_weather_description(day_code: str, night_code: str = "") -> str:
    day = CHINA_WEATHER_CODES.get(str(day_code).zfill(2), "天气")
    night = CHINA_WEATHER_CODES.get(str(night_code).zfill(2), "") if night_code not in (None, "") else ""
    return day if not night or day == night else f"{day}转{night}"


def _china_weather_city_code(city: str) -> str:
    return CHINA_WEATHER_CITY_CODES.get(city.strip().lower(), "") or CHINA_WEATHER_CITY_CODES.get(city.strip(), "")


def _fetch_china_weather_payload(city: str) -> dict:
    city_code = _china_weather_city_code(city)
    script = _get_china_weather_script(f"weather_index/{city_code}.html")
    live = _script_json(script, "dataSK")
    forecast = _script_json(script, "fc").get("f") or []
    today = forecast[0] if forecast else {}
    return {
        "city": city, "name": live.get("cityname") or "上海",
        "temperature": live.get("temp", "?"),
        "wind_speed": re.sub(r"\s*km/h\s*$", "", str(live.get("wse") or live.get("WS") or "?"), flags=re.I),
        "humidity": str(live.get("SD") or "").replace("%", ""),
        "weather_code": live.get("weathercode") or "",
        "description": live.get("weather") or _china_weather_description(today.get("fa", ""), today.get("fb", "")),
        "temp_min": today.get("fd", "?"), "temp_max": today.get("fc", "?"),
        "observed_at": live.get("time") or "", "source": "中国天气网",
        "source_url": f"http://www.weather.com.cn/weather/{city_code}.shtml",
        "updated_at": datetime.now().isoformat(),
    }


def _fetch_china_weekly_payload(city: str, days: int) -> dict:
    city_code = _china_weather_city_code(city)
    script = _get_china_weather_script(f"weixinfc/{city_code}.html")
    rows = (_script_json(script, "fc").get("f") or [])
    items = []
    today = datetime.now().date()
    for row in rows:
        try:
            month, day = [int(part) for part in str(row.get("fi") or "").split("/")[:2]]
            year = today.year + (1 if month < today.month - 6 else 0)
            parsed = datetime(year, month, day)
        except Exception:
            continue
        if parsed.date() < today:
            continue
        day_code, night_code = str(row.get("fa") or ""), str(row.get("fb") or "")
        items.append({
            "date": parsed.strftime("%Y-%m-%d"), "weekday": WEEKDAYS_ZH[parsed.weekday()],
            "temp_min": row.get("fd", "?"), "temp_max": row.get("fc", "?"),
            "weather_code": day_code, "description": _china_weather_description(day_code, night_code),
            "wind": row.get("fe") or row.get("ff") or "", "wind_scale": row.get("fg") or row.get("fh") or "",
        })
        if len(items) >= days:
            break
    return {
        "city": city, "name": "上海", "days": items, "source": "中国天气网",
        "source_url": f"http://www.weather.com.cn/weather/{city_code}.shtml",
        "updated_at": datetime.now().isoformat(), "error": "" if items else f"{city} 中国天气网预报不可用",
    }


def fetch_weather(city: str) -> list[str]:
    data = fetch_weather_payload(city)
    return [
        f"{data['name']}: {data['temperature']}°C {data['description']}",
        f"风速: {data['wind_speed']} km/h",
        f"今日: {data['temp_min']}~{data['temp_max']}°C",
    ]


def fetch_weather_payload(city: str, proxy: str = "") -> dict:
    city = city.strip() or "Beijing"
    if _china_weather_city_code(city):
        try:
            return _fetch_china_weather_payload(city)
        except Exception:
            # 国内源暂时不可用时自动降级，不让天气页变空。
            pass
    geo_url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode({"name": city, "count": 1, "language": "zh", "format": "json"})
    geo = _get_json(geo_url, proxy=proxy)
    results = geo.get("results") or []
    if not results:
        return {"city": city, "name": city, "error": f"找不到城市: {city}"}
    g = results[0]
    lat, lon = g["latitude"], g["longitude"]
    name = g.get("name", city)
    forecast_url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode({
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,weather_code,wind_speed_10m",
        "daily": "temperature_2m_max,temperature_2m_min,weather_code",
        "timezone": "auto",
    })
    data = _get_json(forecast_url, proxy=proxy)
    cur = data.get("current", {})
    daily = data.get("daily", {})
    code = int(cur.get("weather_code", -1)) if cur.get("weather_code") is not None else -1
    desc = WEATHER_CODES.get(code, f"天气码 {code}")
    return {
        "city": city,
        "name": name,
        "temperature": cur.get("temperature_2m", "?"),
        "wind_speed": cur.get("wind_speed_10m", "?"),
        "weather_code": code,
        "description": desc,
        "temp_min": daily.get("temperature_2m_min", ["?"])[0],
        "temp_max": daily.get("temperature_2m_max", ["?"])[0],
        "updated_at": datetime.now().isoformat(),
    }


def fetch_weekly_weather(city: str, days: int = 6) -> list[str]:
    payload = fetch_weekly_weather_payload(city, days)
    if payload.get("error"):
        return [str(payload.get("error"))]
    return [f"{item['weekday']} {item['temp_min']}~{item['temp_max']}° {item['description']}" for item in payload.get("days", [])]


def fetch_weekly_weather_payload(city: str, days: int = 6, proxy: str = "") -> dict:
    city = city.strip() or "Beijing"
    if _china_weather_city_code(city):
        try:
            return _fetch_china_weekly_payload(city, days)
        except Exception:
            # 国内源暂时不可用时自动降级，不让天气页变空。
            pass
    geo_url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode({"name": city, "count": 1, "language": "zh", "format": "json"})
    geo = _get_json(geo_url, proxy=proxy)
    results = geo.get("results") or []
    if not results:
        return {"city": city, "error": f"找不到城市: {city}", "days": []}
    g = results[0]
    lat, lon = g["latitude"], g["longitude"]
    name = g.get("name", city)
    forecast_url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode({
        "latitude": lat,
        "longitude": lon,
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "timezone": "auto",
    })
    data = _get_json(forecast_url, proxy=proxy)
    daily = data.get("daily", {})
    dates = daily.get("time", [])
    maxs = daily.get("temperature_2m_max", [])
    mins = daily.get("temperature_2m_min", [])
    codes = daily.get("weather_code", [])
    items = []
    for day, tmax, tmin, code in zip(dates[:days], maxs[:days], mins[:days], codes[:days]):
        try:
            weekday = WEEKDAYS_ZH[datetime.strptime(day, "%Y-%m-%d").weekday()]
        except Exception:
            weekday = day
        desc = WEATHER_CODES.get(int(code), "天气")
        items.append({
            "date": day,
            "weekday": weekday,
            "temp_min": tmin,
            "temp_max": tmax,
            "weather_code": int(code),
            "description": desc,
        })
    return {"city": city, "name": name, "days": items, "updated_at": datetime.now().isoformat(), "error": "" if items else f"{city} 周预报不可用"}
