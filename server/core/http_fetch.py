"""HTTP fetch that can go direct or through an HTTP/SOCKS proxy via curl."""

from __future__ import annotations

import subprocess
import urllib.request


def fetch_bytes(url: str, timeout: int = 20, proxy: str = "", headers: dict | None = None) -> bytes:
    proxy = str(proxy or "").strip()
    headers = {str(k): str(v) for k, v in (headers or {}).items() if str(k).strip()}
    if not headers.get("User-Agent"):
        headers["User-Agent"] = "RemotePanel/1.0"
    if proxy:
        command = ["curl", "-fsSL", "--max-time", str(timeout), "--connect-timeout", str(min(timeout, 15)), "--proxy", proxy]
        for key, value in headers.items():
            command.extend(["-H", f"{key}: {value}"])
        command.append(url)
        result = subprocess.run(command, capture_output=True, check=False)
        if result.returncode != 0 or not result.stdout:
            message = (result.stderr or result.stdout or b"curl failed").decode("utf-8", "ignore").strip()
            raise RuntimeError(message[:800] or f"curl exit {result.returncode}")
        return result.stdout
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def fetch_text(url: str, timeout: int = 20, proxy: str = "", headers: dict | None = None) -> str:
    return fetch_bytes(url, timeout=timeout, proxy=proxy, headers=headers).decode("utf-8", "ignore")
