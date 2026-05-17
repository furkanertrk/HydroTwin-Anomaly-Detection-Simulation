"""Dataset configuration loading for the HydroTwin detection port."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


CONFIG_TIME_FORMAT = "%Y-%m-%d %H:%M"


@dataclass(frozen=True)
class Leakage:
    link_id: str
    start_time: datetime
    end_time: datetime
    diameter_m: float
    leak_type: str
    peak_time: datetime

    @property
    def year(self) -> int:
        return self.start_time.year


@dataclass(frozen=True)
class HydroTwinConfig:
    config_path: Path
    network_filename: str
    leakages: tuple[Leakage, ...]
    pressure_sensors: tuple[str, ...]
    flow_sensors: tuple[str, ...]
    level_sensors: tuple[str, ...]
    amrs: tuple[str, ...]


def load_config(config_path: Path) -> HydroTwinConfig:
    """Parse `dataset_configuration.yaml` using the same fields as MATLAB."""
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    sections: dict[str, list[str]] = {}
    scalar_sections: dict[str, dict[str, str]] = {}
    section = ""

    for raw_line in config_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith(":") and not line.startswith("-"):
            section = line[:-1].strip()
            sections.setdefault(section, [])
            scalar_sections.setdefault(section, {})
            continue
        if not section:
            continue
        if line.startswith("- "):
            value = line[2:].strip()
            if value.startswith("#"):
                continue
            sections.setdefault(section, []).append(value)
        elif ":" in line:
            key, value = line.split(":", 1)
            scalar_sections.setdefault(section, {})[key.strip()] = value.strip()

    required = ("leakages", "pressure_sensors", "flow_sensors", "level_sensors", "amrs")
    missing = [name for name in required if not sections.get(name)]
    if missing:
        raise ValueError(
            "Config is missing required non-empty sections: " + ", ".join(missing)
        )

    network_filename = scalar_sections.get("Network", {}).get("filename", "")
    if not network_filename:
        raise ValueError("Config is missing Network.filename")

    leakages = tuple(_parse_leakage(row, config_path) for row in sections["leakages"])
    return HydroTwinConfig(
        config_path=config_path,
        network_filename=network_filename,
        leakages=leakages,
        pressure_sensors=tuple(sections["pressure_sensors"]),
        flow_sensors=tuple(sections["flow_sensors"]),
        level_sensors=tuple(sections["level_sensors"]),
        amrs=tuple(sections["amrs"]),
    )


def _parse_leakage(row: str, config_path: Path) -> Leakage:
    parts = [part.strip() for part in row.split(",")]
    if len(parts) != 6:
        raise ValueError(f"Invalid leakage row in {config_path}: {row!r}")
    link_id, start_text, end_text, diameter_text, leak_type, peak_text = parts
    try:
        return Leakage(
            link_id=link_id,
            start_time=datetime.strptime(start_text, CONFIG_TIME_FORMAT),
            end_time=datetime.strptime(end_text, CONFIG_TIME_FORMAT),
            diameter_m=float(diameter_text),
            leak_type=leak_type,
            peak_time=datetime.strptime(peak_text, CONFIG_TIME_FORMAT),
        )
    except ValueError as exc:
        raise ValueError(f"Invalid leakage row in {config_path}: {row!r}") from exc
