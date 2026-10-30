from __future__ import annotations

import os
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

from core.config import app_dir, resource_dir


def choose_existing_file(parent: tk.Misc, title: str, initialdir: Path | str, filetypes: list[tuple[str, str]]) -> str | None:
    return _FilePicker(parent, title, Path(initialdir), filetypes, save_mode=False).show()


def choose_save_file(
    parent: tk.Misc,
    title: str,
    initialdir: Path | str,
    default_name: str,
    defaultextension: str,
    filetypes: list[tuple[str, str]],
) -> str | None:
    picker = _FilePicker(parent, title, Path(initialdir), filetypes, save_mode=True, default_name=default_name, defaultextension=defaultextension)
    return picker.show()


class _FilePicker:
    """Small Tk-only file picker.

    This avoids relying on platform-native file dialogs so the same code path
    works in bundled macOS apps and other environments.
    """

    def __init__(
        self,
        parent: tk.Misc,
        title: str,
        initialdir: Path,
        filetypes: list[tuple[str, str]],
        save_mode: bool,
        default_name: str = "",
        defaultextension: str = "",
    ):
        self.parent = parent
        self.title = title
        self.current_dir = self._safe_dir(initialdir)
        self.filetypes = filetypes
        self.save_mode = save_mode
        self.defaultextension = defaultextension
        self.result: str | None = None
        self.entries: list[Path] = []

        self.top = tk.Toplevel(parent)
        self.top.title(title)
        self.top.geometry("760x520")
        self.top.minsize(620, 420)
        self.top.transient(parent.winfo_toplevel())
        self.top.columnconfigure(0, weight=1)
        self.top.rowconfigure(1, weight=1)

        self.path_var = tk.StringVar(value=str(self.current_dir))
        self.name_var = tk.StringVar(value=default_name)
        self.status_var = tk.StringVar()
        self._build_ui()
        self.refresh()

    def show(self) -> str | None:
        self.top.grab_set()
        self.top.focus_force()
        self.parent.wait_window(self.top)
        return self.result

    def _build_ui(self):
        nav = ttk.Frame(self.top, padding=8)
        nav.grid(row=0, column=0, sticky="ew")
        nav.columnconfigure(1, weight=1)

        ttk.Button(nav, text="上级", command=self.go_up).grid(row=0, column=0, padx=(0, 4))
        ttk.Entry(nav, textvariable=self.path_var).grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(nav, text="打开", command=self.go_path).grid(row=0, column=2, padx=4)
        ttk.Button(nav, text="刷新", command=self.refresh).grid(row=0, column=3, padx=4)

        shortcuts = ttk.Frame(nav)
        shortcuts.grid(row=1, column=0, columnspan=4, sticky="ew", pady=(6, 0))
        for label, path in self._shortcut_dirs():
            ttk.Button(shortcuts, text=label, command=lambda p=path: self.set_dir(p)).pack(side=tk.LEFT, padx=(0, 4))
        self._build_listbox()

    def _shortcut_dirs(self) -> list[tuple[str, Path]]:
        candidates: list[tuple[str, Path]] = [
            ("项目字体", resource_dir() / "fonts"),
            ("程序目录", app_dir()),
            ("资源目录", resource_dir()),
        ]
        win_fonts = Path(os.environ.get("WINDIR", "C:\\Windows")) / "Fonts"
        candidates.append(("系统字体", win_fonts))
        current_drive = Path.cwd().anchor
        if current_drive:
            candidates.append((current_drive.rstrip("\\"), Path(current_drive)))
        seen: set[str] = set()
        shortcuts: list[tuple[str, Path]] = []
        for label, path in candidates:
            try:
                resolved = str(path.resolve())
            except OSError:
                continue
            if resolved.lower() in seen or not path.exists():
                continue
            seen.add(resolved.lower())
            shortcuts.append((label, path))
        return shortcuts

    def _build_listbox(self):
        self.listbox = tk.Listbox(self.top, activestyle="dotbox")
        self.listbox.grid(row=1, column=0, sticky="nsew", padx=8)
        self.listbox.bind("<Double-Button-1>", lambda _event: self.open_selected())
        self.listbox.bind("<<ListboxSelect>>", lambda _event: self.fill_selected_name())

        bottom = ttk.Frame(self.top, padding=8)
        bottom.grid(row=2, column=0, sticky="ew")
        bottom.columnconfigure(1, weight=1)
        ttk.Label(bottom, text="文件名").grid(row=0, column=0, sticky="w", padx=(0, 6))
        ttk.Entry(bottom, textvariable=self.name_var).grid(row=0, column=1, sticky="ew")
        ttk.Button(bottom, text="确定", command=self.accept).grid(row=0, column=2, padx=6)
        ttk.Button(bottom, text="取消", command=self.top.destroy).grid(row=0, column=3)
        ttk.Label(bottom, textvariable=self.status_var).grid(row=1, column=0, columnspan=4, sticky="w", pady=(6, 0))

        self.top.bind("<Return>", lambda _event: self.accept())
        self.top.bind("<Escape>", lambda _event: self.top.destroy())

    def _safe_dir(self, path: Path) -> Path:
        try:
            if path.is_file():
                return path.parent
            if path.exists():
                return path
        except OSError:
            pass
        return resource_dir() if resource_dir().exists() else app_dir()

    def _allowed_extensions(self) -> set[str]:
        exts: set[str] = set()
        for _label, patterns in self.filetypes:
            for pattern in patterns.split():
                suffix = Path(pattern.replace("*", "")).suffix.lower()
                if suffix:
                    exts.add(suffix)
        return exts

    def _matches(self, path: Path) -> bool:
        exts = self._allowed_extensions()
        return not exts or path.suffix.lower() in exts

    def set_dir(self, path: Path):
        self.current_dir = self._safe_dir(path)
        self.path_var.set(str(self.current_dir))
        self.refresh()

    def go_up(self):
        parent = self.current_dir.parent
        if parent != self.current_dir:
            self.set_dir(parent)

    def go_path(self):
        self.set_dir(Path(self.path_var.get()).expanduser())

    def refresh(self):
        self.listbox.delete(0, tk.END)
        self.entries = []
        try:
            items = list(self.current_dir.iterdir())
        except OSError as exc:
            self.status_var.set(str(exc))
            return

        dirs = sorted([p for p in items if p.is_dir()], key=lambda p: p.name.lower())
        files = sorted([p for p in items if p.is_file() and self._matches(p)], key=lambda p: p.name.lower())
        for path in dirs + files:
            self.entries.append(path)
            prefix = "[目录] " if path.is_dir() else "       "
            self.listbox.insert(tk.END, prefix + path.name)
        self.status_var.set(f"{self.current_dir}    {len(dirs)} 个目录，{len(files)} 个文件")

    def selected_path(self) -> Path | None:
        selection = self.listbox.curselection()
        if not selection:
            return None
        idx = int(selection[0])
        if 0 <= idx < len(self.entries):
            return self.entries[idx]
        return None

    def fill_selected_name(self):
        path = self.selected_path()
        if path and path.is_file():
            self.name_var.set(path.name)

    def open_selected(self):
        path = self.selected_path()
        if not path:
            return
        if path.is_dir():
            self.set_dir(path)
            return
        self.name_var.set(path.name)
        self.accept()

    def accept(self):
        selected = self.selected_path()
        if selected and selected.is_dir():
            self.set_dir(selected)
            return

        name = self.name_var.get().strip()
        if selected and selected.is_file() and not name:
            name = selected.name
        if not name:
            messagebox.showerror(self.title, "请输入或选择文件名", parent=self.top)
            return

        path = Path(name)
        if not path.is_absolute():
            path = self.current_dir / path
        if self.save_mode and self.defaultextension and not path.suffix:
            path = path.with_suffix(self.defaultextension)

        if not self.save_mode:
            if not path.is_file():
                messagebox.showerror(self.title, "文件不存在", parent=self.top)
                return
            if not self._matches(path):
                messagebox.showerror(self.title, "文件类型不匹配", parent=self.top)
                return
        elif path.exists():
            if not messagebox.askyesno(self.title, "文件已存在，是否覆盖？", parent=self.top):
                return

        self.result = str(path)
        self.top.destroy()
