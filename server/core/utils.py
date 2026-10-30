from __future__ import annotations

import platform
import re
import shutil
import subprocess
import urllib.request
from pathlib import Path


def _run(command: list[str]) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=3)
    except Exception:
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def get_system_metrics() -> dict[str, object]:
    metrics: dict[str, object] = {
        "host": platform.node(),
        "os": f"{platform.system()} {platform.release()}",
        "cpu_user": None,
        "cpu_sys": None,
        "cpu_idle": None,
        "load_1m": None,
        "load_5m": None,
        "load_15m": None,
        "memory_used_gb": None,
        "memory_total_gb": None,
        "memory_pressure": None,
        "disk_used_pct": None,
        "disk_free_gb": None,
        "swapins": None,
        "swapouts": None,
        "thermal_status": "未知",
        "cpu_speed_limit": None,
        "cpu_available": None,
        "uptime": "",
    }
    try:
        disk = shutil.disk_usage(Path.cwd())
        metrics["disk_used_pct"] = int(disk.used / disk.total * 100)
        metrics["disk_free_gb"] = round(disk.free / (1024 ** 3), 1)
    except Exception:
        pass

    top_output = _run(["top", "-l", "1", "-n", "0"])
    if top_output:
        for line in top_output.splitlines():
            line = line.strip()
            if line.startswith("Load Avg:"):
                match = re.search(r"Load Avg:\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)", line)
                if match:
                    metrics["load_1m"] = float(match.group(1))
                    metrics["load_5m"] = float(match.group(2))
                    metrics["load_15m"] = float(match.group(3))
            elif line.startswith("CPU usage:"):
                match = re.search(r"CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys,\s*([\d.]+)% idle", line)
                if match:
                    metrics["cpu_user"] = float(match.group(1))
                    metrics["cpu_sys"] = float(match.group(2))
                    metrics["cpu_idle"] = float(match.group(3))
            elif line.startswith("PhysMem:"):
                match = re.search(r"PhysMem:\s*(\d+)G used .*?,\s*(\d+)M unused", line)
                total_match = re.search(r"hw\.memsize:\s*(\d+)", _run(["sysctl", "hw.memsize"]))
                total_gb = None
                if total_match:
                    total_gb = round(int(total_match.group(1)) / (1024 ** 3))
                    metrics["memory_total_gb"] = total_gb
                if match:
                    used_gb = float(match.group(1))
                    unused_mb = float(match.group(2))
                    metrics["memory_used_gb"] = used_gb
                    if total_gb:
                        metrics["memory_pressure"] = max(0, min(100, round(used_gb / total_gb * 100)))
                    else:
                        total_est = used_gb + unused_mb / 1024
                        metrics["memory_total_gb"] = round(total_est, 1)
                        metrics["memory_pressure"] = max(0, min(100, round(used_gb / total_est * 100)))
            elif line.startswith("VM:"):
                match = re.search(r"(\d+)\(0\) swapins,\s*(\d+)\(0\) swapouts", line)
                if match:
                    metrics["swapins"] = int(match.group(1))
                    metrics["swapouts"] = int(match.group(2))

    pmset_output = _run(["pmset", "-g", "therm"])
    if pmset_output:
        thermal_status = "正常"
        speed_match = re.search(r"CPU_Speed_Limit\s*=\s*(\d+)", pmset_output)
        if speed_match:
            metrics["cpu_speed_limit"] = int(speed_match.group(1))
            if metrics["cpu_speed_limit"] < 100:
                thermal_status = "降频中"
        cpu_match = re.search(r"CPU_Available_CPUs\s*=\s*(\d+)", pmset_output)
        if cpu_match:
            metrics["cpu_available"] = int(cpu_match.group(1))
        if "No thermal warning level has been recorded" not in pmset_output:
            thermal_status = "热警告"
        metrics["thermal_status"] = thermal_status

    uptime_output = _run(["uptime"])
    if uptime_output:
        metrics["uptime"] = uptime_output
    return metrics


def system_lines() -> list[str]:
    metrics = get_system_metrics()
    lines = [f"Host: {metrics.get('host')}", f"OS: {metrics.get('os')}"]
    cpu_user = metrics.get("cpu_user")
    cpu_sys = metrics.get("cpu_sys")
    cpu_idle = metrics.get("cpu_idle")
    if all(value is not None for value in (cpu_user, cpu_sys, cpu_idle)):
        lines.append(f"CPU: U{cpu_user:.1f}% S{cpu_sys:.1f}% I{cpu_idle:.1f}%")
    memory_used = metrics.get("memory_used_gb")
    memory_total = metrics.get("memory_total_gb")
    memory_pressure = metrics.get("memory_pressure")
    if memory_used is not None and memory_total is not None:
        pressure = f" ({memory_pressure}%)" if memory_pressure is not None else ""
        lines.append(f"Memory: {memory_used:.1f}/{memory_total:.1f}GB{pressure}")
    disk_used = metrics.get("disk_used_pct")
    disk_free = metrics.get("disk_free_gb")
    if disk_used is not None and disk_free is not None:
        lines.append(f"Disk: {disk_used}% used, {disk_free:.1f}GB free")
    thermal = metrics.get("thermal_status")
    if thermal:
        lines.append(f"Thermal: {thermal}")
    return lines


def download_image(url: str, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "RemotePanelEInkStudio/0.1"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = r.read()
    dest.write_bytes(data)
    return dest
