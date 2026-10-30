from __future__ import annotations

import subprocess
import socket
import struct

CMD_CLEAR_SCREEN = 1
CMD_SEND_IMAGE = 2
CMD_CLEAR_SCREEN_EX = 3
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def build_packet(command: int, image_id: int = 0, payload: bytes = b"") -> bytes:
    if not 0 <= image_id <= 9:
        raise ValueError("image_id must be 0..9")
    if command == CMD_SEND_IMAGE and not payload.startswith(PNG_MAGIC):
        raise ValueError("payload must be PNG")
    if command != CMD_SEND_IMAGE:
        payload = b""
    return struct.pack(">III", command, image_id, len(payload)) + payload


def send_png(host: str, port: int, png: bytes, image_id: int = 0, timeout: float = 5.0) -> int:
    packet = build_packet(CMD_SEND_IMAGE, image_id, png)
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(packet)
    return len(packet)


def test_connection(host: str, port: int, timeout: float = 3.0) -> bool:
    with socket.create_connection((host, port), timeout=timeout):
        return True


def adb_forward(local_port: int = 38000, remote_port: int = 38000, adb_path: str = "adb") -> str:
    subprocess.run([adb_path, "forward", f"tcp:{local_port}", f"tcp:{remote_port}"], check=True, capture_output=True, text=True)
    result = subprocess.run([adb_path, "forward", "--list"], check=True, capture_output=True, text=True)
    return result.stdout.strip()
