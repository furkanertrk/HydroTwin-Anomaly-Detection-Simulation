"""SCADA, leak metadata, and MAT loading utilities."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


SCADA_TIME_FORMAT = "%Y-%m-%d %H:%M:%S"


@dataclass(frozen=True)
class PressureScada:
    time: pd.Series
    pressures: np.ndarray
    pressure_names: tuple[str, ...]


@dataclass(frozen=True)
class NominalBaseline:
    p_nominal: np.ndarray
    nominal_time: np.ndarray
    sensor_indices: np.ndarray


def read_scada_csv(path: Path) -> pd.DataFrame:
    """Read BattLeDIM SCADA CSVs with semicolon delimiter and comma decimals."""
    if not path.exists():
        raise FileNotFoundError(f"SCADA file not found: {path}")
    df = pd.read_csv(path, sep=";", decimal=",")
    if df.empty or len(df.columns) < 2:
        raise ValueError(f"SCADA file has no sensor columns: {path}")
    time_col = df.columns[0]
    df[time_col] = pd.to_datetime(
        df[time_col], format=SCADA_TIME_FORMAT, errors="raise"
    )
    for col in df.columns[1:]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def load_pressure_scada(data_dir: Path, year: int) -> PressureScada:
    df = read_scada_csv(data_dir / f"{year}_SCADA_Pressures.csv")
    return PressureScada(
        time=df.iloc[:, 0],
        pressures=df.iloc[:, 1:].to_numpy(dtype=float),
        pressure_names=tuple(str(col) for col in df.columns[1:]),
    )


def read_leak_metadata_csv(path: Path) -> pd.DataFrame:
    """Read leak metadata CSVs for supplemental inspection."""
    if not path.exists():
        raise FileNotFoundError(f"Leak metadata file not found: {path}")
    return pd.read_csv(path, sep=None, engine="python", on_bad_lines="skip")


def loadmat_or_hdf5(path: Path) -> dict[str, Any]:
    """Load MATLAB MAT files using scipy first, then h5py for v7.3/HDF5."""
    if not path.exists():
        raise FileNotFoundError(f"MAT file not found: {path}")
    try:
        from scipy.io import loadmat

        data = loadmat(path, squeeze_me=False, struct_as_record=False)
        return {key: value for key, value in data.items() if not key.startswith("__")}
    except NotImplementedError:
        return _load_hdf5_mat(path)
    except ValueError as exc:
        if "Unknown mat file type" in str(exc):
            return _load_hdf5_mat(path)
        raise


def load_nominal_baseline(path: Path) -> NominalBaseline:
    data = loadmat_or_hdf5(path)
    missing = {"P_nominal", "nominal_time", "sensor_indices"}.difference(data)
    if missing:
        raise ValueError(f"Nominal baseline missing fields: {sorted(missing)}")

    p_nominal = np.asarray(data["P_nominal"], dtype=float)
    if p_nominal.ndim != 2:
        raise ValueError(f"P_nominal must be 2-D, got shape {p_nominal.shape}")
    if p_nominal.shape[0] == 33 and p_nominal.shape[1] != 33:
        p_nominal = p_nominal.T

    nominal_time = np.asarray(data["nominal_time"], dtype=float).reshape(-1)
    sensor_indices = np.asarray(data["sensor_indices"]).reshape(-1)
    return NominalBaseline(
        p_nominal=p_nominal,
        nominal_time=nominal_time,
        sensor_indices=sensor_indices,
    )


def _load_hdf5_mat(path: Path) -> dict[str, Any]:
    import h5py

    out: dict[str, Any] = {}
    with h5py.File(path, "r") as h5:
        for key in h5.keys():
            out[key] = _read_hdf5_value(h5[key])
    return out


def _read_hdf5_value(value: Any) -> Any:
    import h5py

    if isinstance(value, h5py.Dataset):
        arr = value[()]
        if isinstance(arr, bytes):
            return arr.decode("utf-8")
        return np.asarray(arr)
    return {key: _read_hdf5_value(value[key]) for key in value.keys()}
