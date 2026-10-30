from __future__ import annotations

from datetime import datetime, time

from .model import Project, Schedule, Template


def parse_hhmm(value: str) -> time:
    hour, minute = value.split(":", 1)
    return time(int(hour), int(minute))


def time_in_range(now: time, start: time, end: time) -> bool:
    if start <= end:
        return start <= now <= end
    return now >= start or now <= end


def matches_schedule(schedule: Schedule, now: datetime | None = None) -> bool:
    now = now or datetime.now()
    if schedule.type == "manual":
        return False
    if schedule.type == "always":
        return True
    if schedule.type == "daily_range":
        return time_in_range(now.time().replace(second=0, microsecond=0), parse_hhmm(schedule.start), parse_hhmm(schedule.end))
    if schedule.type == "exact_times":
        current = now.strftime("%H:%M")
        return current in schedule.times
    return False


def select_active_template(project: Project, now: datetime | None = None, forced_template_id: str | None = None) -> Template:
    now = now or datetime.now()
    enabled = [t for t in project.templates if t.enabled]
    if forced_template_id:
        for template in enabled:
            if template.id == forced_template_id:
                return template
    for template in enabled:
        if template.schedule.type == "exact_times" and matches_schedule(template.schedule, now):
            return template
    for template in enabled:
        if template.schedule.type == "daily_range" and matches_schedule(template.schedule, now):
            return template
    for template in enabled:
        if template.schedule.type == "always":
            return template
    if not enabled:
        raise ValueError("project has no enabled templates")
    return enabled[0]
