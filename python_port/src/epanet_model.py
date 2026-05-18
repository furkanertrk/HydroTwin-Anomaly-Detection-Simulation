"""WNTR-based EPANET model access for localization smoke tests."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


def find_ltown_inp(data_dir: Path) -> Path:
    for name in ("L-TOWN.inp", "L-TOWN_Real.inp", "L-TOWN_temp.inp"):
        candidate = data_dir / name
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"No L-TOWN .inp file found in {data_dir}")


@dataclass(frozen=True)
class PipeMidpoint:
    pipe_id: str
    x: float
    y: float
    start_node: str
    end_node: str


@dataclass
class LTownModel:
    inp_path: Path
    wn: object
    junction_coordinates: pd.DataFrame
    link_endpoints: pd.DataFrame
    pipe_count: int

    @property
    def junction_count(self) -> int:
        return int(len(self.junction_coordinates))

    @property
    def link_count(self) -> int:
        return int(len(self.link_endpoints))

    def get_pipe_midpoint(self, pipe_id: str) -> PipeMidpoint:
        pipe_id = str(pipe_id)
        if pipe_id not in self.wn.link_name_list:
            raise KeyError(f"Pipe/link ID not found in WNTR model: {pipe_id}")
        link = self.wn.get_link(pipe_id)
        start_node = str(link.start_node_name)
        end_node = str(link.end_node_name)
        start = self.wn.get_node(start_node).coordinates
        end = self.wn.get_node(end_node).coordinates
        return PipeMidpoint(
            pipe_id=pipe_id,
            x=float((start[0] + end[0]) / 2.0),
            y=float((start[1] + end[1]) / 2.0),
            start_node=start_node,
            end_node=end_node,
        )

    def distance_junction_to_pipe_midpoint(self, junction_id: str, pipe_id: str) -> float:
        junction_id = str(junction_id)
        if junction_id not in self.wn.node_name_list:
            raise KeyError(f"Junction/node ID not found in WNTR model: {junction_id}")
        node = self.wn.get_node(junction_id)
        midpoint = self.get_pipe_midpoint(pipe_id)
        return float(np.hypot(node.coordinates[0] - midpoint.x, node.coordinates[1] - midpoint.y))

    def smoke_summary(self) -> dict[str, object]:
        sample_junction = self.junction_coordinates.iloc[0].to_dict()
        sample_link = self.link_endpoints.iloc[0].to_dict()
        sample_midpoint = self.get_pipe_midpoint(str(sample_link["link_id"]))
        return {
            "inp_path": str(self.inp_path),
            "junction_count": self.junction_count,
            "link_count": self.link_count,
            "pipe_count": self.pipe_count,
            "sample_junction": sample_junction,
            "sample_link": sample_link,
            "sample_midpoint": {
                "pipe_id": sample_midpoint.pipe_id,
                "x": sample_midpoint.x,
                "y": sample_midpoint.y,
                "start_node": sample_midpoint.start_node,
                "end_node": sample_midpoint.end_node,
            },
        }


def load_ltown_model(data_dir: Path) -> LTownModel:
    """Load L-TOWN with WNTR and expose ID-based mapping tables."""
    try:
        import wntr
    except Exception as exc:  # pragma: no cover - depends on environment
        raise RuntimeError("WNTR is required for L-TOWN mapping. Install `wntr`.") from exc

    inp_path = find_ltown_inp(data_dir)
    wn = wntr.network.WaterNetworkModel(str(inp_path))

    junction_rows = []
    for junction_id in wn.junction_name_list:
        node = wn.get_node(junction_id)
        x, y = node.coordinates
        junction_rows.append({"junction_id": str(junction_id), "x": float(x), "y": float(y)})

    endpoint_rows = []
    for link_id in wn.link_name_list:
        link = wn.get_link(link_id)
        endpoint_rows.append(
            {
                "link_id": str(link_id),
                "start_node": str(link.start_node_name),
                "end_node": str(link.end_node_name),
            }
        )

    return LTownModel(
        inp_path=inp_path,
        wn=wn,
        junction_coordinates=pd.DataFrame(junction_rows),
        link_endpoints=pd.DataFrame(endpoint_rows),
        pipe_count=int(len(wn.pipe_name_list)),
    )
