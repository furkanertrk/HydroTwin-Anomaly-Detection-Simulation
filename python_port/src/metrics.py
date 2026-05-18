"""Shared detection metrics and output schema helpers."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from math import hypot


SUCCESS_DISTANCE_M = 300.0


def euclidean_distance_m(x1: float, y1: float, x2: float, y2: float) -> float:
    return float(hypot(x1 - x2, y1 - y2))


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
