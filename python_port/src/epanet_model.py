"""WNTR-based EPANET model access.

Port target for MATLAB EPANET Toolkit usage in `load_ltown.m`,
`s2_build_sensitivity_matrix.m`, and `s2b_build_nominal_baseline.m`.
"""

from __future__ import annotations

from pathlib import Path


def find_ltown_inp(data_dir: Path) -> Path:
    for name in ("L-TOWN_Real.inp", "L-TOWN.inp", "L-TOWN_temp.inp"):
        candidate = data_dir / name
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"No L-TOWN .inp file found in {data_dir}")
