from __future__ import annotations

from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

from PIL import Image, ImageTk

from core.hermes_bridge import HermesBridge
from core.config import app_dir, resource_dir
from core.layout_render import render_page, resolve_widget_content
from core.model import Page, Template, Widget
from core.project_store import load_project, save_project
from core.protocol import send_png
from core.scheduler import select_active_template
from core.render import png_to_preview_image
from studio.file_dialogs import choose_existing_file


PALETTE = [
    ("文本", "text"),
    ("时间", "clock"),
    ("天气", "weather"),
    ("新闻", "rss_news"),
    ("VPS流量", "traffic_usage"),
    ("图片", "image"),
    ("Hermes提醒", "hermes_alerts"),
    ("工作状态", "hermes_work_status"),
    ("系统状态", "system_status"),
]


class TemplateDesigner(tk.Toplevel):
    """Visual drag-and-resize template designer."""

    def __init__(self, master, cfg: dict):
        super().__init__(master)
        self.title("可视化模板设计器")
        self.geometry("1280x820")
        self.minsize(1120, 720)
        self.transient(master)
        self.cfg = cfg
        self.project_path = Path(__file__).resolve().parents[1] / "projects" / "default.project.json"
        self.bridge = HermesBridge(Path(__file__).resolve().parents[1] / "hermes_bridge")
        self.project = load_project(self.project_path)
        self.current_template: Template | None = None
        self.current_page: Page | None = None
        self.selected_widget: Widget | None = None
        self.widget_items: dict[int, Widget] = {}
        self.handle_items: set[int] = set()
        self.drag_mode: str | None = None
        self.drag_start = (0, 0)
        self.widget_start = (0, 0, 0, 0)
        self.scale = 0.68
        self.preview_photo = None
        self.live_preview_photo = None
        self.live_preview_job: str | None = None
        self._build_ui()
        self.load_initial()
        self.lift()
        self.focus_force()

    # ---------- UI ----------
    def _build_ui(self):
        self.columnconfigure(1, weight=1)
        self.rowconfigure(1, weight=1)

        top = ttk.Frame(self, padding=6)
        top.grid(row=0, column=0, columnspan=3, sticky="ew")
        ttk.Label(top, text="模板方案").pack(side=tk.LEFT)
        self.template_combo = ttk.Combobox(top, state="readonly", width=24)
        self.template_combo.pack(side=tk.LEFT, padx=4)
        self.template_combo.bind("<<ComboboxSelected>>", lambda e: self.on_template_change())
        ttk.Label(top, text="方案内页面").pack(side=tk.LEFT, padx=(12, 0))
        self.page_combo = ttk.Combobox(top, state="readonly", width=18)
        self.page_combo.pack(side=tk.LEFT, padx=4)
        self.page_combo.bind("<<ComboboxSelected>>", lambda e: self.on_page_change())
        self.selection_hint = tk.StringVar(value="先选模板方案，再选这个方案里的某一页")
        ttk.Label(top, textvariable=self.selection_hint, foreground="#666666").pack(side=tk.LEFT, padx=(10, 0))
        ttk.Label(top, text="字体").pack(side=tk.LEFT, padx=(12, 0))
        self.font_path_var = tk.StringVar(value=str(self.cfg.get("font_path", "")))
        ttk.Entry(top, textvariable=self.font_path_var, width=28).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="选择字体", command=self.choose_template_font).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="保存", command=self.save_project).pack(side=tk.LEFT, padx=8)
        ttk.Button(top, text="新增页面", command=self.add_page).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="复制页面", command=self.duplicate_page).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="重命名页面", command=self.rename_page).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="上移页面", command=lambda: self.move_page(-1)).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="下移页面", command=lambda: self.move_page(1)).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="删除页面", command=self.delete_page).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="发送当前页", command=self.send_current_page).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="发送当前模板", command=self.send_current_template).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="按时间发送", command=self.send_scheduled_template).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="刷新画布", command=self.draw_canvas).pack(side=tk.LEFT, padx=4)
        ttk.Button(top, text="快速预览", command=self.show_real_preview).pack(side=tk.LEFT, padx=4)

        left = ttk.LabelFrame(self, text="添加组件", padding=8)
        left.grid(row=1, column=0, sticky="ns", padx=6, pady=6)
        for label, wtype in PALETTE:
            ttk.Button(left, text=label, command=lambda t=wtype: self.add_widget(t)).pack(fill=tk.X, pady=3)
        ttk.Separator(left).pack(fill=tk.X, pady=8)
        ttk.Button(left, text="复制组件", command=self.duplicate_widget).pack(fill=tk.X, pady=3)
        ttk.Button(left, text="删除组件", command=self.delete_widget).pack(fill=tk.X, pady=3)
        ttk.Label(left, text="\n操作：\n单击选择\n拖动移动\n拖右下角缩放\nDelete 删除", justify=tk.LEFT).pack(anchor="w")

        center = ttk.Frame(self, padding=6)
        center.grid(row=1, column=1, sticky="nsew")
        center.columnconfigure(0, weight=1)
        center.rowconfigure(0, weight=1)
        self.canvas = tk.Canvas(center, bg="#e8e8e8", highlightthickness=0)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        self.canvas.bind("<ButtonPress-1>", self.on_canvas_down)
        self.canvas.bind("<B1-Motion>", self.on_canvas_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_canvas_up)
        self.canvas.bind("<Delete>", lambda e: self.delete_widget())
        self.canvas.focus_set()

        right = ttk.LabelFrame(self, text="属性", padding=8)
        right.grid(row=1, column=2, sticky="ns", padx=6, pady=6)
        self.prop_vars: dict[str, tk.StringVar] = {}
        for label, key in [
            ("名称", "id"), ("类型", "type"), ("X", "x"), ("Y", "y"), ("宽", "w"), ("高", "h"),
            ("字号", "font_size"), ("字体", "font_path"), ("文本", "text"), ("城市", "city"),
            ("RSS", "rss_url"), ("图片", "image_path"),
        ]:
            ttk.Label(right, text=label).pack(anchor="w")
            var = tk.StringVar()
            self.prop_vars[key] = var
            row = ttk.Frame(right)
            row.pack(fill=tk.X, pady=2)
            ttk.Entry(row, textvariable=var, width=28).pack(side=tk.LEFT, fill=tk.X, expand=True)
            if key == "font_path":
                ttk.Button(row, text="选", width=3, command=self.choose_font_for_widget).pack(side=tk.LEFT, padx=2)
            if key == "image_path":
                ttk.Button(row, text="选", width=3, command=self.choose_image_for_widget).pack(side=tk.LEFT, padx=2)
        self.border_var = tk.BooleanVar()
        self.invert_var = tk.BooleanVar()
        ttk.Checkbutton(right, text="边框", variable=self.border_var).pack(anchor="w", pady=3)
        ttk.Checkbutton(right, text="反色", variable=self.invert_var).pack(anchor="w", pady=3)
        ttk.Button(right, text="应用属性", command=self.apply_properties).pack(fill=tk.X, pady=5)
        ttk.Button(right, text="同步到画布", command=self.draw_canvas).pack(fill=tk.X, pady=3)
        ttk.Separator(right).pack(fill=tk.X, pady=8)
        ttk.Button(right, text="模拟Hermes提醒", command=self.mock_hermes_alert).pack(fill=tk.X, pady=3)
        ttk.Button(right, text="清空Hermes提醒", command=self.clear_hermes_alerts).pack(fill=tk.X, pady=3)
        self.live_preview_enabled = tk.BooleanVar(value=True)
        ttk.Checkbutton(right, text="实时预览", variable=self.live_preview_enabled, command=self.schedule_live_preview).pack(anchor="w", pady=(8, 3))
        self.live_preview_label = ttk.Label(right, relief=tk.SUNKEN, anchor="center")
        self.live_preview_label.pack(fill=tk.X, pady=3)
        self.log_text = tk.Text(right, height=8, width=34)
        self.log_text.pack(fill=tk.BOTH, expand=True, pady=5)

    # ---------- loading / selection ----------
    def load_initial(self):
        self.template_combo["values"] = [f"{t.id} - {t.name}" for t in self.project.templates]
        if self.project.templates:
            self.template_combo.current(0)
            self.on_template_change()

    def on_template_change(self):
        idx = self.template_combo.current()
        if idx < 0:
            return
        self.current_template = self.project.templates[idx]
        self.selection_hint.set(f"当前方案：{self.current_template.id} / {self.current_template.name}，再选下面的页面")
        self.refresh_page_choices(0)

    def on_page_change(self):
        if not self.current_template:
            return
        idx = self.page_combo.current()
        if idx < 0:
            return
        self.current_page = self.current_template.pages[idx]
        self.selection_hint.set(f"当前编辑页：{self.current_page.image_id} / {self.current_page.name}")
        self.selected_widget = self.current_page.widgets[0] if self.current_page.widgets else None
        self.load_properties()
        self.draw_canvas()

    def choose_template_font(self):
        fonts_dir = resource_dir() / "fonts"
        if not fonts_dir.exists():
            fonts_dir = app_dir() / "fonts"
        path = choose_existing_file(
            self,
            title="选择模板字体",
            initialdir=str(fonts_dir),
            filetypes=[("Font", "*.ttf *.ttc *.otf"), ("All", "*.*")],
        )
        if path:
            self.font_path_var.set(path)
            self.cfg["font_path"] = path
            if getattr(self.project, "global_style", None):
                self.project.global_style.font_path = path
            self.draw_canvas()

    def refresh_page_choices(self, selected_index: int = 0):
        if not self.current_template:
            self.page_combo["values"] = []
            self.current_page = None
            self.selected_widget = None
            self.draw_canvas()
            return
        self.page_combo["values"] = [f"{p.image_id} - {p.name}" for p in self.current_template.pages]
        if not self.current_template.pages:
            self.current_page = None
            self.selected_widget = None
            self.selection_hint.set(f"当前方案：{self.current_template.id} / {self.current_template.name}，暂无页面")
            self.draw_canvas()
            return
        selected_index = max(0, min(selected_index, len(self.current_template.pages) - 1))
        self.page_combo.current(selected_index)
        self.on_page_change()

    def next_image_id(self) -> int:
        if not self.current_template or not self.current_template.pages:
            return 0
        return max(page.image_id for page in self.current_template.pages) + 1

    def add_page(self):
        if not self.current_template:
            return
        page = Page(image_id=self.next_image_id(), name=f"页面{len(self.current_template.pages) + 1}", widgets=[])
        self.current_template.pages.append(page)
        self.refresh_page_choices(len(self.current_template.pages) - 1)
        self.log(f"已新增页面：{page.name} image_id={page.image_id}")

    def duplicate_page(self):
        if not self.current_template or not self.current_page:
            return
        page = Page.from_dict(self.current_page.to_dict())
        page.image_id = self.next_image_id()
        page.name = f"{self.current_page.name}_copy"
        self.current_template.pages.append(page)
        self.refresh_page_choices(len(self.current_template.pages) - 1)
        self.log(f"已复制页面：{page.name} image_id={page.image_id}")

    def rename_page(self):
        if not self.current_page:
            return
        new_name = simpledialog.askstring("重命名页面", "输入新的页面名称：", initialvalue=self.current_page.name, parent=self)
        if not new_name:
            return
        self.current_page.name = new_name.strip() or self.current_page.name
        current_index = self.page_combo.current()
        self.refresh_page_choices(current_index)
        self.log(f"已重命名页面：{self.current_page.name}")

    def move_page(self, direction: int):
        if not self.current_template or not self.current_page:
            return
        current_index = self.page_combo.current()
        target_index = current_index + direction
        if current_index < 0 or target_index < 0 or target_index >= len(self.current_template.pages):
            return
        pages = self.current_template.pages
        pages[current_index], pages[target_index] = pages[target_index], pages[current_index]
        self.refresh_page_choices(target_index)
        self.log(f"已移动页面到位置：{target_index + 1}")

    def delete_page(self):
        if not self.current_template or not self.current_page:
            return
        if len(self.current_template.pages) <= 1:
            messagebox.showerror("无法删除", "每个模板至少保留一个页面")
            return
        current_index = self.page_combo.current()
        self.current_template.pages = [page for page in self.current_template.pages if page is not self.current_page]
        self.refresh_page_choices(max(0, current_index - 1))
        self.log("已删除当前页面")

    # ---------- coordinate helpers ----------
    def sx(self, x: int) -> int:
        return int(x * self.scale) + self.origin_x

    def sy(self, y: int) -> int:
        return int(y * self.scale) + self.origin_y

    def sw(self, w: int) -> int:
        return max(1, int(w * self.scale))

    def screen_to_model(self, x: int, y: int) -> tuple[int, int]:
        return int((x - self.origin_x) / self.scale), int((y - self.origin_y) / self.scale)

    # ---------- canvas drawing ----------
    def draw_canvas(self):
        self.canvas.delete("all")
        self.widget_items.clear()
        self.handle_items.clear()
        if not self.current_page:
            return
        cw = max(800, self.canvas.winfo_width())
        ch = max(650, self.canvas.winfo_height())
        device = self.project.device
        self.scale = min((cw - 60) / device.width, (ch - 60) / device.height, 0.9)
        self.origin_x = max(20, (cw - self.sw(device.width)) // 2)
        self.origin_y = max(20, (ch - self.sw(device.height)) // 2)

        # Design mode must stay lightweight. Do NOT call render_page() here:
        # render_page may fetch weather/RSS/traffic data, and draw_canvas runs on every drag event.
        # Full black/white rendering is done only when sending the page/template.
        self.canvas.create_rectangle(self.origin_x, self.origin_y, self.sx(device.width), self.sy(device.height), fill="white", outline="black", width=2)
        # light grid
        for gx in range(0, device.width + 1, 50):
            self.canvas.create_line(self.sx(gx), self.origin_y, self.sx(gx), self.sy(device.height), fill="#dddddd")
        for gy in range(0, device.height + 1, 50):
            self.canvas.create_line(self.origin_x, self.sy(gy), self.sx(device.width), self.sy(gy), fill="#dddddd")

        for widget in self.current_page.widgets:
            self.draw_widget_box(widget)
        self.schedule_live_preview()

    def draw_widget_box(self, widget: Widget):
        x1, y1 = self.sx(widget.x), self.sy(widget.y)
        x2, y2 = self.sx(widget.x + widget.w), self.sy(widget.y + widget.h)
        selected = widget is self.selected_widget
        color = "#0066ff" if selected else "#444444"
        width = 3 if selected else 1
        item = self.canvas.create_rectangle(x1, y1, x2, y2, outline=color, width=width, tags=("widget",))
        self.widget_items[item] = widget
        preview_text = self.widget_preview_text(widget)
        label = self.canvas.create_text(
            x1 + 6,
            y1 + 6,
            anchor="nw",
            text=preview_text,
            fill=color,
            width=max(40, x2 - x1 - 12),
            font=("Arial", 10, "bold" if selected else "normal"),
            tags=("widget",),
        )
        self.widget_items[label] = widget
        if selected:
            h = self.canvas.create_rectangle(x2 - 10, y2 - 10, x2 + 4, y2 + 4, fill="#0066ff", outline="white", tags=("resize",))
            self.handle_items.add(h)

    def widget_preview_text(self, widget: Widget) -> str:
        try:
            content = resolve_widget_content(widget, self.bridge, live_data=False).strip()
        except Exception:
            content = widget.text.strip() or widget.type
        content = content.replace("\r", "")
        lines = [line.strip() for line in content.splitlines() if line.strip()]
        sample = "\n".join(lines[:3]) if lines else widget.type
        return f"{widget.id}\n{sample}"

    # ---------- mouse ----------
    def on_canvas_down(self, event):
        self.canvas.focus_set()
        item = self.canvas.find_closest(event.x, event.y)[0] if self.canvas.find_closest(event.x, event.y) else None
        self.drag_start = (event.x, event.y)
        self.drag_mode = None
        if item in self.handle_items and self.selected_widget:
            self.drag_mode = "resize"
            w = self.selected_widget
            self.widget_start = (w.x, w.y, w.w, w.h)
            return
        widget = self.widget_items.get(item)
        if widget:
            self.selected_widget = widget
            w = widget
            self.widget_start = (w.x, w.y, w.w, w.h)
            self.drag_mode = "move"
            self.load_properties()
            self.draw_canvas()
        else:
            self.selected_widget = None
            self.load_properties()
            self.draw_canvas()

    def on_canvas_drag(self, event):
        if not self.selected_widget or not self.drag_mode:
            return
        dx = int((event.x - self.drag_start[0]) / self.scale)
        dy = int((event.y - self.drag_start[1]) / self.scale)
        x, y, w, h = self.widget_start
        if self.drag_mode == "move":
            self.selected_widget.x = max(0, x + dx)
            self.selected_widget.y = max(0, y + dy)
        elif self.drag_mode == "resize":
            self.selected_widget.w = max(20, w + dx)
            self.selected_widget.h = max(20, h + dy)
        self.load_properties()
        self.draw_canvas()

    def on_canvas_up(self, event):
        self.drag_mode = None

    # ---------- widgets ----------
    def add_widget(self, wtype: str):
        if not self.current_page:
            return
        idx = len(self.current_page.widgets) + 1
        defaults = {
            "text": {"text": "今日重点\n- 检查墨水屏链路\n- 更新 morning 模板", "font_size": 28},
            "clock": {"text": "%Y-%m-%d\n%H:%M", "font_size": 30},
            "weather": {"city": "Beijing", "font_size": 20},
            "rss_news": {"rss_url": "https://hnrss.org/frontpage", "font_size": 18, "max_items": 3},
            "traffic_usage": {"font_size": 18},
            "image": {"font_size": 18},
            "hermes_alerts": {"font_size": 20},
            "hermes_work_status": {"font_size": 20},
            "system_status": {"font_size": 18},
        }.get(wtype, {})
        widget = Widget(id=f"{wtype}{idx}", type=wtype, x=40, y=40 + idx * 25, w=300, h=140, border=True, **defaults)
        self.current_page.widgets.append(widget)
        self.selected_widget = widget
        self.load_properties()
        self.draw_canvas()
        self.log(f"已添加组件：{widget.id}")

    def duplicate_widget(self):
        if not self.current_page or not self.selected_widget:
            return
        src = self.selected_widget
        data = src.to_dict()
        data["id"] = src.id + "_copy"
        data["x"] = src.x + 20
        data["y"] = src.y + 20
        widget = Widget.from_dict(data)
        self.current_page.widgets.append(widget)
        self.selected_widget = widget
        self.load_properties()
        self.draw_canvas()

    def delete_widget(self):
        if not self.current_page or not self.selected_widget:
            return
        self.current_page.widgets = [w for w in self.current_page.widgets if w is not self.selected_widget]
        self.selected_widget = self.current_page.widgets[0] if self.current_page.widgets else None
        self.load_properties()
        self.draw_canvas()

    # ---------- properties ----------
    def load_properties(self):
        w = self.selected_widget
        for var in self.prop_vars.values():
            var.set("")
        if not w:
            self.border_var.set(False)
            self.invert_var.set(False)
            return
        for key, var in self.prop_vars.items():
            var.set(str(getattr(w, key, "")))
        self.border_var.set(w.border)
        self.invert_var.set(w.invert)

    def apply_properties(self):
        w = self.selected_widget
        if not w:
            return
        try:
            for key in ["id", "type", "font_path", "text", "city", "rss_url", "image_path"]:
                setattr(w, key, self.prop_vars[key].get())
            for key in ["x", "y", "w", "h", "font_size"]:
                setattr(w, key, int(self.prop_vars[key].get()))
            w.border = self.border_var.get()
            w.invert = self.invert_var.get()
            self.draw_canvas()
            self.schedule_live_preview()
            self.log("属性已应用")
        except Exception as exc:
            messagebox.showerror("属性错误", str(exc))

    def choose_font_for_widget(self):
        fonts_dir = resource_dir() / "fonts"
        if not fonts_dir.exists():
            fonts_dir = app_dir() / "fonts"
        path = choose_existing_file(
            self,
            title="选择字体",
            initialdir=str(fonts_dir),
            filetypes=[("Font", "*.ttf *.ttc *.otf"), ("All", "*.*")],
        )
        self._restore_window_focus()
        if path:
            self.prop_vars["font_path"].set(path)
            self.apply_properties()

    def choose_image_for_widget(self):
        path = choose_existing_file(
            self,
            title="选择图片",
            initialdir=app_dir(),
            filetypes=[("Images", "*.png *.jpg *.jpeg *.bmp *.gif"), ("All", "*.*")],
        )
        self._restore_window_focus()
        if path:
            self.prop_vars["image_path"].set(path)
            self.apply_properties()

    def _restore_window_focus(self):
        self.after_idle(lambda: (self.deiconify(), self.lift(), self.focus_force()))

    def show_real_preview(self):
        if not self.current_page:
            return
        try:
            png = render_page(self.current_page, self.project.device, self.project.global_style, bridge=self.bridge, live_data=False)
            preview = png_to_preview_image(png, (420, 560))
            top = tk.Toplevel(self)
            top.title("快速黑白预览")
            photo = ImageTk.PhotoImage(preview)
            label = ttk.Label(top, image=photo)
            label.image = photo
            label.pack(padx=10, pady=10)
            ttk.Button(top, text="关闭", command=top.destroy).pack(pady=(0, 10))
            self.log("快速预览已生成")
        except Exception as exc:
            self.log(f"快速预览失败：{exc}")
            messagebox.showerror("快速预览失败", str(exc))

    def schedule_live_preview(self):
        if not hasattr(self, "live_preview_enabled") or not self.live_preview_enabled.get():
            return
        if self.live_preview_job:
            self.after_cancel(self.live_preview_job)
        self.live_preview_job = self.after(250, self.render_live_preview)

    def render_live_preview(self):
        self.live_preview_job = None
        if not self.current_page:
            return
        try:
            png = render_page(self.current_page, self.project.device, self.project.global_style, bridge=self.bridge, live_data=False)
            preview = png_to_preview_image(png, (190, 250))
            self.live_preview_photo = ImageTk.PhotoImage(preview)
            self.live_preview_label.configure(image=self.live_preview_photo)
        except Exception as exc:
            self.live_preview_label.configure(image="", text="预览失败")
            self.log(f"实时预览失败：{exc}")

    # ---------- project/send ----------
    def save_project(self):
        save_project(self.project, self.project_path)
        self.log(f"已保存项目：{self.project_path}")

    def send_current_page(self):
        if not self.current_page:
            return
        try:
            png = render_page(self.current_page, self.project.device, self.project.global_style, bridge=self.bridge)
            sent = send_png(self.project.device.host, self.project.device.port, png, self.current_page.image_id)
            self.bridge.write_state(last_sent_at=datetime.now().isoformat(), active_template_id=self.current_template.id if self.current_template else "", active_pages=[self.current_page.image_id], device_online=True, last_error="")
            self.log(f"已发送页面 image_id={self.current_page.image_id}, {sent} bytes")
        except Exception as exc:
            self.log(f"发送失败：{exc}")
            messagebox.showerror("发送失败", str(exc))

    def send_current_template(self):
        if not self.current_template:
            return
        pages = []
        try:
            for page in self.current_template.pages:
                png = render_page(page, self.project.device, self.project.global_style, bridge=self.bridge)
                sent = send_png(self.project.device.host, self.project.device.port, png, page.image_id)
                pages.append(page.image_id)
                self.log(f"已发送 {self.current_template.id}/{page.name} image_id={page.image_id}, {sent} bytes")
            self.bridge.write_state(last_sent_at=datetime.now().isoformat(), active_template_id=self.current_template.id, active_pages=pages, device_online=True, last_error="")
        except Exception as exc:
            self.log(f"发送失败：{exc}")
            messagebox.showerror("发送失败", str(exc))

    def send_scheduled_template(self):
        template = select_active_template(self.project, datetime.now())
        for i, t in enumerate(self.project.templates):
            if t.id == template.id:
                self.template_combo.current(i)
                self.on_template_change()
                break
        self.send_current_template()

    # ---------- schedule/hermes ----------
    def refresh_schedule_text(self):
        if not hasattr(self, "schedule_text"):
            active = select_active_template(self.project, datetime.now()).id if self.project.templates else ""
            self.log(f"当前激活模板：{active}")
            return
        self.schedule_text.delete("1.0", tk.END)
        active = select_active_template(self.project, datetime.now()).id if self.project.templates else ""
        self.schedule_text.insert(tk.END, f"当前时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        self.schedule_text.insert(tk.END, f"当前激活模板：{active}\n\n")
        for t in self.project.templates:
            self.schedule_text.insert(tk.END, f"{t.id} - {t.name}\n")
            self.schedule_text.insert(tk.END, f"  enabled: {t.enabled}\n")
            self.schedule_text.insert(tk.END, f"  schedule: {t.schedule.type} {t.schedule.start}-{t.schedule.end} times={t.schedule.times}\n")
            self.schedule_text.insert(tk.END, f"  pages: {[p.image_id for p in t.pages]}\n\n")

    def refresh_hermes_text(self):
        if not hasattr(self, "hermes_text"):
            active = self.bridge.read_inbox(include_acknowledged=False)
            self.log(f"Hermes提醒：{len(active)} 条活动消息")
            return
        self.hermes_text.delete("1.0", tk.END)
        self.hermes_text.insert(tk.END, "Inbox:\n")
        for m in self.bridge.read_inbox(include_acknowledged=True):
            self.hermes_text.insert(tk.END, f"- [{m.get('severity')}] {m.get('title')}: {m.get('body')}\n")
        self.hermes_text.insert(tk.END, "\nDaily:\n" + str(self.bridge.read_daily()) + "\n")
        self.hermes_text.insert(tk.END, "\nWork status:\n" + str(self.bridge.read_work_status()) + "\n")
        self.hermes_text.insert(tk.END, "\nCommand:\n" + str(self.bridge.read_command()) + "\n")
        self.hermes_text.insert(tk.END, "\nState:\n" + str(self.bridge.read_state()) + "\n")

    def mock_hermes_alert(self):
        self.bridge.notify("critical", "Hermes", "这是一条来自 Hermes Bridge 的测试提醒。")
        self.refresh_hermes_text()
        self.draw_canvas()

    def clear_hermes_alerts(self):
        self.bridge.clear_inbox()
        self.refresh_hermes_text()
        self.draw_canvas()

    def log(self, text: str):
        self.log_text.insert(tk.END, f"[{datetime.now().strftime('%H:%M:%S')}] {text}\n")
        self.log_text.see(tk.END)
