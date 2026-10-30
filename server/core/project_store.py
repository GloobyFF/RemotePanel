from __future__ import annotations

import json
from pathlib import Path

from .model import Project, create_default_project


def load_project(path: Path | str) -> Project:
    p = Path(path)
    if not p.exists():
        project = create_default_project()
        save_project(project, p)
        return project
    return Project.from_dict(json.loads(p.read_text(encoding="utf-8")))


def save_project(project: Project, path: Path | str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
