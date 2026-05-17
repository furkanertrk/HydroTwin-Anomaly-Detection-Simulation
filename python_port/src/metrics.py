"""Shared detection metrics and output schema helpers."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


SUCCESS_DISTANCE_M = 300.0


@dataclass(frozen=True)
class DetectionMetrics:
    method: str
    leak_id: str
    leak_start_time: datetime
    leak_end_time: datetime
    alarmed: bool
    detected: bool
    missed: bool
    false_alarm_before_leak: bool
    alarm_time: datetime | None
    detection_delay_hours: float | None
    threshold: float | None
    calib_center: float | None
    calib_scale: float | None
