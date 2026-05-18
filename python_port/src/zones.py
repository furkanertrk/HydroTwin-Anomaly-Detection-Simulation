"""Junction zone map loading for localization."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pandas as pd


EXPECTED_ZONES = 30
EXPECTED_JUNCTIONS = 782
REQUIRED_COLUMNS = ("junction_id", "junction_index", "x", "y", "zone_id")


@dataclass(frozen=True)
class ZoneMap:
    table: pd.DataFrame
    junction_to_zone: dict[str, int]
    zone_to_junctions: dict[int, tuple[str, ...]]

    @property
    def zone_count(self) -> int:
        return len(self.zone_to_junctions)

    @property
    def junction_count(self) -> int:
        return len(self.table)

    def zone_size_summary(self) -> dict[str, float]:
        counts = [len(nodes) for nodes in self.zone_to_junctions.values()]
        return {
            "min": float(min(counts)),
            "mean": float(sum(counts) / len(counts)),
            "max": float(max(counts)),
        }


def load_node_zone_map(path: Path) -> ZoneMap:
    """Load `node_zone_map.csv`; CSV is safer than MATLAB table decoding."""
    if not path.exists():
        raise FileNotFoundError(f"Node zone map CSV not found: {path}")
    table = pd.read_csv(path)
    missing = set(REQUIRED_COLUMNS).difference(table.columns)
    if missing:
        raise ValueError(f"node_zone_map.csv missing columns: {sorted(missing)}")

    table = table.loc[:, REQUIRED_COLUMNS].copy()
    table["junction_id"] = table["junction_id"].astype(str)
    table["junction_index"] = pd.to_numeric(table["junction_index"], errors="raise").astype(int)
    table["x"] = pd.to_numeric(table["x"], errors="raise")
    table["y"] = pd.to_numeric(table["y"], errors="raise")
    table["zone_id"] = pd.to_numeric(table["zone_id"], errors="raise").astype(int)

    if len(table) != EXPECTED_JUNCTIONS:
        raise ValueError(f"Expected {EXPECTED_JUNCTIONS} zone-map junctions, got {len(table)}")
    if table["junction_id"].duplicated().any():
        raise ValueError("node_zone_map.csv contains duplicate junction_id values.")

    junction_to_zone = dict(zip(table["junction_id"], table["zone_id"]))
    zone_to_junctions = {
        int(zone_id): tuple(group["junction_id"].astype(str).tolist())
        for zone_id, group in table.groupby("zone_id", sort=True)
    }
    if len(zone_to_junctions) != EXPECTED_ZONES:
        raise ValueError(f"Expected {EXPECTED_ZONES} zones, got {len(zone_to_junctions)}")

    return ZoneMap(
        table=table,
        junction_to_zone={str(k): int(v) for k, v in junction_to_zone.items()},
        zone_to_junctions=zone_to_junctions,
    )
